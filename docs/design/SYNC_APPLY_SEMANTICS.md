# Sync Apply Semantics

Current contract for the Apple sync core. The implementation is under
`apps/apple/core/Sources/LorvexSync`; code and executable tests remain the
ultimate authority.

## Canonical envelope

Every synced record is a `SyncEnvelope` containing:

- `entityType`: a typed `EntityKind`;
- `entityId`: the kind's canonical identity;
- `operation`: `upsert` or `delete`;
- `version`: a canonical HLC;
- `payloadSchemaVersion`;
- canonical JSON `payload`;
- the originating `deviceId`.

CloudKit record names are fixed-width lower-case SHA-256 identities derived from
the wire `entity_type` and `entity_id`. They do not contain either raw string,
but enumerable low-entropy pairs remain dictionary-testable by an observer of
record metadata. Transport metadata never participates in LWW conflict
resolution.

Payload JSON is compact and key-sorted. User-authored strings are preserved;
only fields with an explicit comparison contract, such as a tag lookup key,
are normalized.

`EntityKind.allSyncableTypes` in
`core/Sources/LorvexDomain/NamingEntity.swift` is the wire inventory. Local
control kinds such as `device_state` and `import_session` never enter CloudKit.

## Local MCP mutation idempotency

MCP idempotency receipts are device-local and never enter a sync envelope. A
keyed tool call computes a canonical request checksum and claims
`(tool_name, idempotency_key)` before its domain body inside the same SQLite
`BEGIN IMMEDIATE` transaction. A live row with a different checksum aborts the
transaction; a matching row from another call replays its response or reports
`idempotency_response_unavailable` when only the applied marker survived.

Batch tools carry one private claim token across their component transactions.
This lets the owning call continue while every other process remains fenced.
After the complete tool result is built, a compare-and-swap replaces only that
private claim with the replay payload. An expired row may be deleted and reused;
an unexpired conflicting row is never overwritten.

## Transaction boundary

`Apply.applyEnvelope` must run inside the caller's SQLite write transaction.
It opens a per-envelope savepoint. A deferred result rolls that savepoint back,
so an envelope parked for retry leaves no partial tombstone removal, conflict
log, alias, shadow, or domain-row mutation behind.

One apply timestamp is captured at entry and shared by the domain rows written
by that envelope. Outbox rows minted during apply stamp their `created_at`
with fresh wall clock, and merge-loser tombstones' `deleted_at` diagnostics
may differ between merge paths; none of those timestamps participates in LWW
or GC decisions.

## Ordinary apply pipeline

For a normal domain or edge envelope, apply proceeds in this order:

1. Validate `payloadSchemaVersion`. A payload newer than the supported
   compatibility window defers. A forward-compatible `ai_changelog` payload
   also defers because append-only audit rows have no later LWW promotion seam.
2. Reject local-only kinds and validate the canonical entity id.
3. For composite edges, resolve each parent through permanent aliases and
   rebuild the composite id before any death or LWW gate.
4. Look up a permanent alias for the exact identity. Alias handling precedes
   ordinary tombstones and is described below.
5. Gate an equal-HLC mutation semantically, before the tombstone and LWW
   gates. An envelope whose version equals a local mutation at the same
   identity (live row or tombstone) is compared as a semantic mutation: an
   exact semantic replay skips; two DIFFERENT semantic mutations reusing one
   HLC return the `resolveEqualVersionCollision` repair obligation described
   under "Repair obligations". Grouped-register kinds (task, base calendar
   event) and the upsert-only series cutover pass through to their appliers'
   deterministic joins instead of the whole-row repair.
6. Gate against the exact ordinary tombstone. A strictly newer upsert
   supersedes the death barrier; an older upsert loses. A newer delete
   advances the death frontier without recreating a row.
7. Compare the local row version with the envelope HLC. A strictly stale
   mutation skips for whole-row kinds. For the grouped-register kinds a stale
   whole-row envelope still reaches its applier when it carries a winning
   independent register (see "LWW and conflict records").
8. For upserts, check hard dependencies after LWW. Missing parents return a
   typed deferral for the durable pending inbox.
9. For an admitted upsert, prepare its forward-compatible payload shadow before
   dispatch. A natural-key merge may delete the addressed identity inside the
   applier, so post-dispatch shadow storage is too late.
10. Dispatch to the registered typed applier and finalize any delete state.

An ordinary successful delete removes the live row and writes only this shape:

```text
sync_tombstones(entity_type, entity_id, version, deleted_at)
```

`sync_tombstones` contains death knowledge only. It carries no redirect target
or cross-type metadata.

## LWW and conflict records

Whole-row aggregates and independent children use entity-level HLC LWW.
Composite relations use their canonical composite identity. Parent-owned child
collections embedded in an aggregate payload are replaced or merged according
to that aggregate's typed applier. `ai_changelog` is append-only and
id-deduplicated rather than row-version LWW.

`task` and base `calendar_event` rows are grouped registers, not whole-row
LWW. A task carries four independently versioned registers — content,
schedule, lifecycle, archive — and a base calendar event carries two —
content and topology. The row `version` is only the transport/delete
high-water mark: a whole-row envelope that is strictly stale on `version`
still reaches the typed applier when it carries a winning register clock, and
only that register's fields apply. Equal register clocks resolve through the
deterministic canonical-byte join, so opposite arrival orders converge.

Equal envelope HLCs are compared semantically before the tombstone and LWW
gates. An exact semantic replay is a skip. Two different semantic mutations
reusing one HLC produce the deterministic byte-max join of the local and
remote mutations as a contender and return the `resolveEqualVersionCollision`
repair obligation: the consuming transaction mints a strict-successor HLC,
applies the contender (which may carry the remote content), and re-emits the
canonical result. Promotion paths may explicitly accept equal versions where
needed to replay a retained forward-compatible payload.

Whenever local state wins a meaningful contest, `sync_conflict_log` records the
winner version, loser version/device/payload where permitted, timestamp, and a
typed resolution name. Conflict logs are local diagnostics, not synced state.

## Repair obligations

`Apply.applyEnvelope` can return `repairRequired` with a typed obligation that
the caller must discharge inside the same transaction that consumes the
envelope, before the triggering CloudKit page is acknowledged:

- `reassertRequiredInbox`: a peer deleted the canonical inbox list. Keep the
  local row and replace the peer's shared delete record with an upsert whose
  HLC dominates the remote delete version.
- `reassertCalendarSeriesCutover`: reassert the upsert-only recurring-series
  boundary after an invalid peer delete targeted its CloudKit record.
- `propagateCalendarCleanup`: a durable cutover invalidated materialized
  calendar payloads or references. Replace every affected shared record with a
  strict-successor delete or current upsert.
- `propagateTaskRollover`: a task lifecycle decision normalized task-graph
  records. Re-emit every canonical task/reminder/day-root snapshot and
  dependency tombstone.
- `resolveEqualVersionCollision`: two different semantic mutations reused one
  HLC. Apply the deterministic join at a freshly minted strict successor and
  enqueue the resulting canonical state.

Each obligation names the entity kinds its repair may mutate, so the caller's
reload/report surface covers every derived write rather than only the
triggering envelope's kind.

## Convergence re-emit

Some applies deliberately land a row that differs from the envelope's payload:
an older-schema envelope that omits an absence-preserved child collection
keeps the local children; a list delete re-homes the list's live tasks to the
inbox; a grouped-register join composes fields from both contenders. In each
case the applying device re-emits the complete merged snapshot at a fresh
dominating HLC so peers and rebuilt generations converge on the composed
state instead of the envelope's partial view.

The re-emit's fresh HLC can, in a one-round-trip window, overwrite a peer's
subsequent genuine edit that lands between the omitting envelope's version and
the re-emit's version — an accepted low-frequency trade-off with no cheap
mitigation.

## Durable pending inbox

Missing hard dependencies and future-compatible envelopes are retained in
`sync_pending_inbox` with the complete envelope and typed reason. Retry is
event-driven by relevant local or inbound changes. HOLD-class future records do
not consume the ordinary retry budget.

The FK declaration used by normal apply is also used by authoritative-snapshot
dependency closure. Adding a hard dependency in only one of those paths is a
protocol bug.

## Permanent entity redirects

An identity merge produces two independent facts:

1. the loser is dead as an ordinary domain identity; and
2. future references to that identity resolve to the canonical winner.

The second fact lives in:

```text
sync_entity_redirects(
  source_type, source_id, target_id, version, created_at
)
```

It is synced as the independent, upsert-only `entity_redirect` kind. It is not
a special tombstone. A wire redirect payload contains exactly
`source_type`, `source_id`, `target_id`, and `version`; its opaque wire id is the
digest of the source tuple.

Redirect invariants:

- source and target have the same supported aggregate kind;
- `target_id < source_id`, making cycles impossible for valid stored edges;
- only `tag`, `habit`, `memory`, and `habit_reminder_policy` may be aliased —
  the schema CHECK on `sync_entity_redirects.source_type` enforces the same
  closed set. Task identity collisions (duplicate recurrence-instance claims)
  fail closed through the tasks recurrence-instance UNIQUE index instead of
  merging, and calendar events never alias;
- the record is permanent and has no delete operation;
- competing targets union their complete terminal components at the
  lexicographically smallest terminal target. Any displaced live terminal is
  aggregate-merged and gains its own permanent alias/death record; changing only
  the original source alias would leave two live aggregates;
- chains are compressed to one hop, and every changed predecessor emits a
  dominating corrective alias upsert;
- a missing live/dead terminal target defers with zero side effects;
- a terminal target's ordinary tombstone satisfies the dependency: the alias is
  retained and any live source is suppressed rather than resurrecting data.

An incremental CloudKit physical deletion of an `entity_redirect` slot does
not delete the local alias. The inbound page resolves the opaque record name
against the local redirect table and establishes the same canonical upsert in
the outbox before its traversal cursor commits. An already-eligible exact
upsert satisfies that obligation idempotently; a newer row or a future/adoption
fence does not. The same direct slot detection reasserts the permanent inbox and
`calendar_series_cutover` invariants even when no pending-inbox or retry row
exists. By contrast, an explicit complete-zone/account adoption clears
pre-session aliases and rebuilds only the aliases present in the adopted zone:
"permanent" is a store/generation invariant, not authority over a deliberate
adopt-cloud-truth boundary.

An alias may arrive on an earlier CloudKit page than its target record. It stays
in the durable pending inbox; either a later live target upsert or a later target
tombstone satisfies the dependency and replays the alias.

A next-payload-generation alias is held whole rather than partially applied.
Identity aliases are irreversible control state, so unknown future fields cannot
be truncated and repaired later through an ordinary aggregate payload shadow.

When an ordinary envelope addresses an alias source:

- an upsert remaps to the terminal winner, rewrites identity-bearing payload
  fields, and then runs target tombstone, LWW, and FK gates;
- a delete is dropped. A delete authored against a stale loser identity must
  never be translated into deletion of the winner.

Forward-compatible payload shadows follow the same alias path. The shadow that
belongs to the selected content participant moves to the winner as one complete
snapshot; fields from different participants are never unioned. Redirects never
cross entity types.

## Deterministic aggregate merge

Natural-key collisions for tag, habit, memory, and habit reminder policy use
`AggregateMergeEngine`.

- Identity winner: `min(id)`.
- Content winner: the canonical max-HLC participant, with min id on an equal HLC.
- Merge version: the smallest canonical HLC successor of all parent
  participants, using the dominating participant's suffix.
- Children: re-pointed with their own HLC floors preserved.
- `created_at` (tag, habit, habit reminder policy; memory has no such column):
  a min-register, neither content nor identity-pinned. A merge folds the winner
  to the participant-set minimum, and every apply of a payload addressed to the
  row — including a payload remapped through a permanent alias, and including
  LWW-rejected payloads — folds `min(existing, incoming)`. The fold uses only
  envelope-local information, so a peer that saw the alias before ever
  materializing the target row converges to the same floor as a peer that
  collapsed both live rows.

One atomic merge emits current state for all three independent facts:

- canonical winner upsert;
- permanent `entity_redirect` upsert for every loser;
- ordinary domain delete for every loser.

This means another device and a rebuilt CloudKit generation do not need to
rediscover the original collision to preserve alias semantics.

## Generation and full-resync reconstruction

A generation snapshot enumerates durable SQLite state, not only the current
outbox:

- every live syncable row/edge;
- every ordinary tombstone as a delete, except exact CloudKit-confirmed deletes
  at or before an explicitly published compaction cutoff;
- every `sync_entity_redirects` row as an `entity_redirect` upsert;
- account-routed audit state allowed by its retention frontier.

`entity_redirect` tombstones are never counted or emitted. The capture manifest
and terminal readback digest cover redirect records like every other current
record.

Legacy full-resync backfill follows the same separation: live rows, ordinary
deletes, and permanent aliases are independently reconstructed at their stored
versions.

Delete compaction is generation-bound, not ordinary time-based GC. A device may
propose a cutoff only from its greatest exact CloudKit record modification time;
candidate receipts remain lease-local until the matching seal is read back and
the ready control CAS publishes the same cutoff. Publication atomically promotes
those exact receipts and removes only matching tombstone/outbox delete versions.
The cutoff is covered only by a completed nil-token baseline whose exact
per-traversal witness has a strictly later CloudKit modification time. Equality
at millisecond precision is insufficient. A database without that proof adopts
the complete generation snapshot authoritatively rather than unioning stale
local rows. Device wall clocks, incremental receipts, and checkpoint save times
never establish compaction or recovery authority.

## Authoritative snapshot adoption

Over-window recovery stages a complete remote inventory before touching live
domain state. Finalization is one SQLite transaction:

1. capture genuine post-session local outbox intents and their hard-dependency
   closure;
2. remove superseded local rows and clear the old death, alias, pending, and
   payload-shadow ledgers;
3. replay remote ordinary upserts in parent-first topological order;
4. replay remote ordinary deletes in child-first topological order;
5. replay remote `entity_redirect` upserts last;
6. restamp and replay post-session local ordinary upserts, deletes, then aliases
   with the same phase ordering;
7. remove the durable session only after every replay succeeds.

An alias target is a hard dependency for both remote and post-session replay.
A target ordinary tombstone satisfies that dependency. If any staged record is
unknown, corrupt, or cannot apply, the whole finalization rolls back and the
session remains recoverable.

## Payload shadows

When a supported newer payload generation contains unknown keys, the typed
known subset may apply while the original canonical payload is retained in
`sync_payload_shadow`. Preparation happens immediately before dispatch in the
same per-envelope savepoint. Outbound snapshots overlay the live known fields
onto the retained unknown object and preserve the higher payload-schema version.

An older-schema update cannot express an intentional clear for a field it does
not know. When it supersedes a same-identity row that carries a higher-schema
shadow, the shadow is retained and its base HLC advances atomically to the new
live version. The receiver then emits the complete merged snapshot at a fresh
dominating HLC. This makes a fresh/rebuilt peer recover the preserved value
instead of recreating only the legacy insert default.

Promotion is fail-closed. The shadow and live row must name the exact same HLC;
a missing row, corrupt version, schema-version value outside `1...UInt32.max`,
or any provenance mismatch leaves the shadow intact and emits diagnostics.
Generation capture enforces the same equal-version and exact-schema rules.

For a same-type natural-key collision, any participant payload shadow makes the
entire merge defer. The shadow contains fields this binary cannot interpret, so
even whole-row HLC arbitration cannot tell whether a field absent from an
independently-authored older-schema duplicate means preserve or clear. This
generic hold is present in the version-1 binary: after an upgrade promotes the
opaque fields and removes the shadows, the typed merge can proceed. Redirects
outside an aggregate collision still move one complete HLC-selected shadow;
unknown keys from different participants are never unioned.

Released payload contracts evolve only by optional top-level additions with
immutable legacy insert-default/update-preserve metadata. Cross-ID collision
aggregates (`habit`, `habit_reminder_policy`, `memory`, and `tag`) reject
additive field evolution by default: without persisted
per-field provenance, every collision needs an executable entity-specific
adapter and opposite-arrival-order convergence coverage. See
`schema/sync_payload/README.md`.

Calendar occurrence decisions add a related storage invariant. A base row has
no series linkage and owns both register clocks. A decision row has a nonempty
series id, the master's recurrence generation, a real original occurrence date,
and one of `replacement`, `cancelled`, or `inherit`; it owns neither base-event
register clock. Its UUIDv8 id is derived deterministically from that complete
address, so every device writes the same LWW identity for the same occurrence.
Shared domain validation covers sync, import and workflow writes, while SQLite
CHECKs/triggers make direct writers obey the same shape.

## Outbox recovery and authoritative fences

`sync_outbox.disposition` distinguishes three non-retryable-by-default
states from ordinary pending rows:

- `retry_wait` keeps the full envelope and a bounded backoff schedule;
- `authoritative_adoption` quarantines pre-session writes intentionally and is
  never rearmed by generic retry;
- `future_record_hold` preserves a local intent fenced by a future-authored
  CloudKit record, carrying that record's maximum HLC
  (`future_record_version`) and a durable `future_record_resolution` policy
  (`lww`, `remote_authoritative`, or `local_after_future`) for the upgraded
  build that eventually understands the opaque record.

Post-session user/MCP writes remain active, are captured before adoption, and
are replayed on top of the remote baseline. Successful finalize or explicit
cancel deletes the owned fences; it does not revive stale pre-adoption intent.

A queued base calendar-event or task Upsert also carries the device-local
`sync_outbox.register_intent` bitmask (calendar: content/topology bits; task:
the four task-register bits). It is not wire data. Recovery re-authors only
the registers the local write actually changed; a zero-bit convergence/no-op
snapshot is discarded rather than resurrecting a remotely absent record.
During ordinary outbox coalescing, an old bit survives only when that
register's clock and every known field are byte-equivalent in the replacement
payload. This preserves a pending local content edit across a remote topology
winner without mislabeling remote content as local intent.

## Primary implementation and tests

- Pipeline: `core/Sources/LorvexSync/Apply.swift` and
  `ApplyEnvelopeFlow.swift`
- Permanent aliases: `EntityRedirect.swift`, `ApplyRedirect.swift`
- Aggregate merges: `AggregateMergeEngine.swift`
- Deferred work: `PendingInboxDrain.swift`
- Generation snapshot: `GenerationSnapshot*.swift`
- Authoritative adoption: `AuthoritativeSnapshot*.swift`
- Schema authority: `schema/schema.sql`
- Focused contracts: `EntityRedirectTests.swift`,
  `AuthoritativeSnapshotTests.swift`, `GenerationSnapshotStagingTests.swift`,
  and the per-aggregate merge test suites
