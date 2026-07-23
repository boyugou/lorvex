# Apple schema and sync finalization worklog — 2026-07-14

Status: source-level checkpoint complete at `c66c2436`; external release evidence remains pending.
This acceptance log records repository evidence, not the signed-build or Apple-account evidence listed below.

Baseline: `main` at `1b9af6290`; completed checkpoint:
`c66c2436c1af162f870a0379ed3ddf44e16d89fc` (`Finalize Apple data schema and
CloudKit sync`). There are no released users, so the implementation corrected
the version-1 schema and wire contract in place rather than preserving unshipped
compatibility debt.

## Accepted final contracts

- `schema/schema.sql` is the Apple schema authority; the embedded Apple copy is
  byte-identical. Tauri is not a parity constraint.
- The first Apple sync payload contract remains version 1 until release. Its
  operation-specific field inventory lives in `schema/sync_payload/001.json`.
- Ordinary domain entities use HLC LWW and bounded, generation-safe compact
  tombstones. Ordinary local GC never reclaims them; only exact CloudKit receipts
  covered by a server-derived cutoff in a successfully published generation do.
  A database lacking a strictly later completed-baseline server witness adopts
  that generation authoritatively instead of unioning stale state.
- `ai_changelog` is a bounded, cross-device audit stream. Retention is an
  account- and CloudKit-generation-scoped monotonic frontier; expired cloud
  records are physically deleted after durable mark-before-cloud evidence.
- Every CloudKit generation uses a unique custom zone. A change-tag-CAS control
  record in the default zone is the authority; stale owners can mutate only
  their abandoned zone. User cloud-data deletion leaves a fleet-visible deleted
  barrier until explicit re-opt-in.
- A nil-token traversal is not trusted from a cache file alone. SQLite stores
  its account, physical database, zone, generation, continuation and terminal
  witness atomically with apply/reconciliation state.
- Over-window adoption is a true authoritative snapshot: local syncable rows
  absent from the complete remote inventory do not remain as silently
  resurrectable live rows.

## Implemented and accepted in the source checkpoint

- Operation-specific payload manifest and release verifier.
- Canonical inbound envelope validation and bounded raw/decoded payloads.
- Task `in_progress` lifecycle and the database invariant that `completed_at`
  is present exactly when status is `completed`.
- Typed retry-wait versus authoritative-adoption outbox states.
- Durable authoritative snapshot staging and required-inbox repair.
- Account-bound HLC/reseed/factory-reset safety and serialized sync operations.
- Account/zone-scoped audit-retention frontier, authorization, cloud-presence
  evidence and physical-purge queue.
- Physical-purge paging is scoped by exact account and generation zone in SQL
  before the page limit. Retired-zone backlog therefore cannot starve active
  privacy deletes; composite indexes cover exact-zone due work and reverse
  entity-presence lookups.
- Durable traversal progress/witness storage and transactional service APIs.
- Unique-zone-per-generation CloudKit orchestration is wired through ordinary
  and authoritative transport.

## Additional findings discovered during implementation

### Import task resurrection gap — resolved in checkpoint

`SwiftLorvexCoreService.importTaskRecordTransactionally` currently checks only
whether a live task row exists. Unlike the matching list, habit, event, memory,
review and focus import entries, it does not reject an existing `task`
tombstone. A stale backup can therefore recreate a task with a fresh HLC and
publish it fleet-wide. The atomic import test matrix also omits the task
tombstone case even though the protocol docstring promises that guard.

The MCP `original_id` create paths for task/list/habit/event first probe
presence and then call an overwrite-capable import in a separate transaction.
That creates a check/write race and, for an absent tombstoned identity, can
resurrect deleted state. Production should call the typed atomic
`...IfAbsent`/transactional import capability directly. A deliberate new entity
can always be created without reusing a deleted identity.

The transactional task importer now checks live state and tombstones under the
same write lock; all four MCP `original_id` paths call their typed atomic
if-absent import instead of probing first. Tests cover tombstoned identities and
the task `in_progress` transition. The unshipped `"deferred"` import alias was
also removed: it is a derived UI lane, not a persisted task status, so a drifted
archive now fails per record instead of being silently coerced to `open`.

### Import primitive versus restore policy — resolved contract

The low-level `LorvexCalendarServicing`, `LorvexHabitServicing`, and
`LorvexListTagServicing` import methods remain overwrite-capable identity-
preserving primitives. The user-facing restore path calls the separate
`...IfAbsent` entry points, whose implementation docstrings and transaction
guards make the non-destructive, skip-if-present/tombstoned policy explicit.
The two contracts are intentionally distinct.

### Retention naming and duplicate state — resolved

The UI/wire policy is now `maximum`, shown as “Maximum (10,000 entries).” The
unpublished `forever` token and enum case were removed without a compatibility
alias; absent, malformed, and unknown values still fail safely to `.maximum`
rather than triggering a purge.

Cloud-presence evidence is keyed by `(account, zone, entity)`. The redundant
scalar `ai_changelog.cloud_presence_possible` column was removed; the scoped
evidence table is the only production truth.

### Audit-delete protocol prose — reconciled

The accepted implementation uses a monotonic retention frontier and physical
CloudKit record deletion. Source comments and the release-facing contract now
describe that model instead of the superseded marked-delete/tombstone design.

### Durable same-type identity aliases — resolved in checkpoint

Aggregate dedup no longer overloads ordinary tombstones with redirect metadata.
`sync_entity_redirects` is a separate permanent, upsert-only ledger and
`entity_redirect` is an independent wire kind. Generation capture, legacy full
resync, authoritative adoption, inbound batch ordering, dependency closure and
payload-shadow movement all preserve the alias independently from the loser's
ordinary death record.

Aliases are restricted to the six aggregate kinds with merge hooks and always
point to a lexicographically smaller same-type id. Competing targets perform a
true component union: the displaced terminal aggregate is merged/aliased to the
minimum terminal, rather than merely rewriting the original source row and
leaving two live aggregates. Path compression emits dominating corrective
records. Missing targets defer without side effects, including when the alias
and its later live/dead target arrive on separate CloudKit pages. Focused tests
cover both arrival orders, deleted terminals, pending replay, generation
enumeration, and authoritative replay.

### Far-future HLC domination — resolved with a detached transaction lane

Passive observation remains clamped, while an explicit edit that must dominate
a future-authored row switches that transaction to a durable, surface-scoped
detached HLC lane. Its replay can dominate the row without advancing the normal
process clock, so unrelated later writes do not inherit the future timestamp.

### Durable CloudKit traversal proof — resolved in checkpoint

The SQLite proof now binds an exact account, physical database lineage, unique
zone generation, generation-root identifier, ready-seal witness and per-fetch
traversal witness. Baseline and incremental cursors are distinct: only a
nil-token baseline that observes all three remote witnesses and commits every
page with its local effects may enroll a generation. An incremental cursor can
resume transport but can neither create nor replace that full-history proof.

An append-only, account-scoped generation-descriptor ledger prevents a canceled
or crashed newer traversal from erasing anti-rollback history. Account switching
clears local-content proof while retaining each account's descriptor history;
explicit physical-database lineage rotation clears both. The ledger rejects a
lower epoch, same-epoch descriptor drift, and cross-generation reuse of a zone,
generation root or ready witness. Descriptor reservation plus traversal begin,
and terminal cursor/witness transitions, each use an internal SQLite savepoint
so a caller that catches an error cannot commit half of the state transition.

The fleet deletion barrier and every explicit sync re-enable are monotonic
generation transitions. Missing or externally wiped control state is not
permission to synthesize generation 0/1, reuse a historical zone/descriptor, or
clear the local descriptor ledger: recovery fails closed and requires an
explicit strongly authorized repair/re-enable transition. Only a deliberate
physical-database lineage rotation may clear the local anti-rollback ledger.

Page delivery now performs a transaction-local disposition preflight before any
domain apply or authoritative staging. A durable replay returns before conflict,
error-log, repair, changelog or staging effects run; a new page applies effects
and then must win the same-transaction cursor CAS. Authoritative-session begin
atomically stores the exact descriptor and starts its nil-token traversal;
restart resets both, cancel removes both, and terminal reconciliation plus the
baseline witness are one transaction. Authoritative begin, restart, page
staging, cancel and final reconciliation also use internal savepoints, so even a
low-level caller that catches an operation error inside a larger write
transaction cannot persist a partial phase transition, page inventory or fence
release.

### Account-scoped audit-retention finalization — resolved in checkpoint

The audit stream now has one account-scoped working set. Changing iCloud
accounts atomically clears audit content plus its outbox, inbox, shadow,
quarantine and tombstone derivatives, while retaining only the durable
account/zone cloud-presence and exact-zone purge evidence needed to finish
privacy deletion. First binding also repairs rows explicitly owned by a foreign
account without deleting unbound device-local forensic entries.

The retention policy is a virtual control-plane preference: it remains visible
through product preference APIs but is never persisted, exported, imported,
backfilled, staged or applied as an ordinary `preference` entity. Its sole sync
authority is the generation-local retention metadata record. Explicit writes
are strictly validated; tolerant parsing remains limited to durable reads so
corruption fails toward `maximum` instead of triggering a purge.

Audit uploads are atomic batches of at most 199 audit records plus the exact
unchanged metadata record, saved with CloudKit change-tag CAS. Only a missing or
stale guard is retried after metadata refresh; transport and malformed atomic
results fail out. Exact-zone physical purges drain bounded 200-record pages in
one cycle (with an overall safety bound) and advertise remaining work to the
coordinator instead of stranding rows beyond the first page.

All nine custom fields of `LorvexAuditRetentionMetadata` are written and read
only through `CKRecord.encryptedValues`; the CloudKit template declares each
field `ENCRYPTED`, and the readiness verifier pins the complete Swift/schema
field and type mapping. Plaintext sibling fields are deliberately not accepted
as a decoder fallback.

## Source-level checkpoint completed — 2026-07-15

The implementation items above are closed in this checkpoint. The final pass
connected the unique-generation transport and durable traversal witness across
ordinary and authoritative fetches, completed deletion/retirement and
account-scoped audit-retention handling, reconciled the embedded SQLite schema
and CloudKit reference schema, and added adversarial coverage for the documented
crash, account, lineage, continuation, lease, purge and re-opt-in boundaries.

The complete local acceptance set passed after the final behavior-preserving
source splits:

- Apple package: 2,274 tests in 136 suites, zero failures.
- Core package: 2,408 tests, zero failures; 23 opt-in benchmarks skipped by
  design because `LORVEX_BENCH` was not enabled.
- Python release/verifier tests: 558 tests, zero failures.
- Schema embedding, empty pre-launch migration ladder, sync-payload contract,
  dormant pre-launch freeze tripwire, CloudKit readiness for all 19 syncable
  kinds, MCP typed registry/unchanged 118-tool manifest, localization, privacy,
  source entitlements, repository hygiene, source hotspots, SQLite portability,
  XcodeGen project generation and user-documentation gates all passed.
- Both the development MCP host and the packaged helper passed the stdio smoke
  (`tools/list` returned 118 tools), and the locally signed production bundle
  passed packaging plus Mach-O distribution and dependency-closure checks.

The schema freeze deliberately remains dormant (`launched=false`). This is the
correct pre-launch state: arm it against the exact SQLite baseline and sync
payload contract used for the first public App Store release, not an earlier
internal checkpoint.

## Independent post-checkpoint hardening — 2026-07-15

A fresh review of current `main` did not treat the preceding acceptance totals
as proof that all compositions were safe. It reproduced and closed five
additional release-model/runtime boundaries:

1. A one-page in-window reseed unconditionally cleared `reseed_required` after
   the terminal pull, even when `enqueueFullResyncBackfill` had skipped a
   malformed tombstone and deliberately reasserted the marker. The coordinator
   no longer owns a blind clear; complete backfill and authoritative snapshot
   transactions are the only recovery-completion authorities. The now-dead
   public `clearReseedRequired` protocol surface was removed.
2. macOS constructed a new off-mode maintenance coordinator per access. Delete
   and re-enable could therefore have independent operation gates and actors
   over the same CloudSyncState directory. The store now retains one coordinator
   graph, shares it with live sync and factory reset, and authorizes deleted-zone
   re-enable inside that coordinator gate. A request-time epoch rejects a mode
   toggle captured before a later deletion even if its UI Task starts only after
   deletion completes; barrier and delayed-request tests pin both orderings.
3. Mobile's off-mode deletion maintenance could overlap a mode transition built
   from another coordinator graph. Mobile now retains/reuses the same graph and
   queues mode intent until cleanup completes. Its Settings binding also stamps
   requests with the current deletion epoch, so a pre-deletion Task cannot wake
   late and recreate cloud data. Deterministic tests prove both properties.
4. Release archives previously checked only that the freeze sentinel was armed.
   Their preflight now always reruns Apple schema-embed parity, semantic ladder
   validation, sync-payload validation, and strict release freeze coverage. An
   armed-but-not-rearmed new migration/payload cannot enter a distributable.
5. A migration's released identity is now `(name, normalized SHA-256)`, checked
   by both repository gates and `SchemaMigrationRunner`. The destructive ladder
   verifier also models trigger-body dependencies (including INSERT/REPLACE,
   qualified and comma-separated FROM sources, and OLD/NEW columns), so a
   migration cannot leave a trigger that fails only on a later ordinary write.

The earlier backlog note claiming live-but-signed-out retention was uncovered
was rechecked and removed as stale. Both macOS and Mobile run local retention at
the start of every refresh before account/pause/transport gating; live mode
preserves active outbox rows while still applying age/policy retention.

Acceptance evidence for this checkpoint: the Apple package passed 2,309 tests;
the core package passed 2,409 tests with only 23 explicitly gated benchmark
skips; the repository script suite passed 615 tests; and
`LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` completed successfully,
including the release-mode products, signed local bundle checks, all schema and
sync gates, and both MCP stdio smokes with 118 registered tools. No simulator or
GUI automation was used.

## External release evidence still required

The repository can prove source and locally packaged behavior, but it cannot
prove external Apple state. Before submitting the first public build, retain
release evidence for:

- the deployed CloudKit **Production** schema and container permissions;
- the exact distribution-signed/notarized archive, including its effective
  entitlements and generated privacy report;
- an installed-build App Group read/write check across the app, MCP helper and
  widget, plus a real multi-device iCloud smoke test; and
- arming the schema/sync-payload freeze against that exact first-public-release
  baseline.

## Mobile and aggregate convergence checkpoint — 2026-07-15

A new composition-focused pass found that green schema/sync unit suites still
left several mobile and aggregate boundaries unsafe. The checkpoint containing
this section closes the reproduced defects below without changing the frozen
wire shape:

1. `current_focus` and `focus_schedule` composed snapshots now carry the root
   row's stored HLC into pre-delete capture. Clearing a peer future-stamped
   aggregate therefore mints a dominating delete/tombstone instead of letting the
   remote upsert resurrect it. The same shared path replaces calendar's former
   one-off version injection.
2. iOS/iPadOS/visionOS/watchOS/tvOS storage resolution now fails closed as
   sandboxed. An unavailable App Group can no longer be misclassified as an
   unsandboxed build and fall back to a private per-process database.
3. Mobile Cloud sync cycles are single-flight with a trailing pass. Their
   lifecycle result and complete applied-kind report are folded across all
   passes, so an overlapping foreground refresh cannot consume a push handoff,
   publish pre-apply state, and then mistake the background apply for `.noData`.
   Foreground push delivery performs full fan-out; background delivery remains a
   deadline-bounded sync-only drain with a durable handoff.
4. Mobile task/list/habit views now carry observable domain revision keys.
   Paginated pages and routed details re-read after canonical inbound changes;
   confirmed task deletion evicts cached copies while a transient read error
   preserves last-good UI.
5. Mobile task editing now produces a field-level `TaskUpdateDraft` relative to
   its opening baseline. Editing only a title no longer writes stale notes,
   dates, tags or dependencies over a newer MCP/Cloud edit.
6. macOS, iOS and visionOS app entry points share one application-process
   database-change bootstrap. In-process App Intent/notification/CarPlay writes
   reach open stores; Darwin writes from sibling processes are relayed. Mobile
   inbound CloudKit apply posts an origin-tagged signal for CarPlay/independent
   stores, while the already-reconciled origin ignores it.
7. Mobile's outer refresh flight now folds lifecycle results as well as the inner
   Cloud sync flight, so a trailing no-op refresh cannot erase `.newData` already
   produced by the pass that applied a silent push. Active-push delegate
   completion is deadline-bounded without cancelling the full foreground
   fan-out. Every arrival owns a persisted token, and only a real successful
   cycle may compare-and-clear the same token; failed/no-cycle work and an older
   coalesced waiter therefore cannot acknowledge newer CloudKit debt.
8. A task route's revision-keyed reload now wraps its content, loading and
   not-found states. Transient reads and a delete-then-recreate sequence therefore
   recover on the next canonical revision instead of becoming a permanent error
   screen. Detached-window reloads validate their observer epoch after every
   suspended DB read, so a result owned by a closed/restarted window can never be
   adopted late. Core replacement also advances the epoch before swapping the
   service, and a new epoch's pending invalidation is handed forward.

Focused regression coverage includes future-stamped aggregate deletes, mobile
sandbox policy, coalesced cycle report preservation, active/background push
routing, view-owned revision invalidation, patch-safe task editing, application
process signal configuration, origin-gated inbound broadcasts, nested-flight
result folding, bounded active-push completion, token-scoped handoff
acknowledgement, route recovery, suspended detached-read rejection and
old-core read rejection after database replacement.

Acceptance evidence for this checkpoint: the Apple package passed 2,322 tests
in 136 suites; the core package passed 2,409 tests with only 23 explicitly gated
benchmark skips; and the 615-test verifier suite passed. The full local package,
Mach-O/resource/dependency closure, signed-bundle validation, install/archive
verification and packaged MCP smokes all passed. The deliberately non-notarized
local archive then stopped at notarization preflight because a Developer ID
signature is unavailable; the canonical source gate is therefore run with
`LORVEX_VERIFY_SKIP_PACKAGING=1`, while real distribution-signing/notarization
remains external release evidence.

The same bounded review also confirmed the next-pass items now tracked in
`FINDINGS_BACKLOG.md`: crash-resumable account adoption; exact cursor-expiry
recovery for ordinary baseline/candidate readback/predecessor drain; typed
per-record fetch retry; canonical calendar timing validation; additive-only
payload evolution enforcement; focus-schedule event provenance; manifest-backed
runtime formats; and application-ACK durability for Watch offline mutations.
They are explicitly not represented as closed by this checkpoint.

## SQLite traversal and account-adoption finalization — 2026-07-16

This checkpoint closes the remaining crash/composition gaps in the CloudKit
cursor and account-consent model. It deliberately does not expand the product
schema: both authoritative `schema.sql` copies remain structurally unchanged;
only their architecture comment was corrected.

1. The CloudKit change token now has exactly one durable authority: the managed
   SQLite traversal tables. Every inbound page's domain effects, witness
   observation, continuation state, and successor token commit in one database
   transaction. The external checkpoint store and its second commit point were
   deleted; `CloudSyncChangeCursor` is only a transient transport value.
2. Invalid or expired cursors reset the exact bound traversal in SQLite. This is
   implemented for ordinary incrementals, nil-token baselines, candidate
   readback, predecessor drain, and authoritative snapshots. Persistent
   per-record fetch failures withhold the token and trigger the same exact reset
   only at the bounded recovery threshold.
3. Traversal-witness publication is crash-resumable. The local traversal ID is
   committed before remote publication and reused after failure; the preceding
   terminal witness is deleted before a new traversal starts. Terminal page
   commit has no later fallible witness cleanup. A failure after an already
   committed page carries a typed partial report so UI surfaces can immediately
   adopt the committed prefix without falsely declaring the transport healthy.
4. Explicit account adoption is authorized by an opaque capability binding the
   signed-in account, physical database instance, raw source binding, recorded
   account identity, exact revisioned pause event, and (for deleted-zone
   re-enable) deletion generation. Confirmation revalidates the entire boundary
   inside the coordinator operation gate and uses SQLite's transactional
   adoption operation. Stale dialogs, restored databases, repeated account
   notifications, and deletion/re-enable interleavings therefore fail closed.
5. Pause revisions remain monotonic across clear and relaunch, preventing a
   same-reason ABA from reviving stale consent. SQLite account binding is the
   start-gate authority; a missing matching sidecar identity is repaired, while
   a genuine SQLite account mismatch remains closed until explicit adoption.
6. `CloudSyncState/Cache` now names its actual role: only reconstructible
   CKRecord system fields live in the backup-excluded cache. Revisioned
   account/consent safety files remain in the parent state directory, and change
   tokens remain in SQLite. macOS and Mobile each retain one coordinator actor
   graph across live sync and off-mode deletion maintenance.
7. Dead checkpoint-only APIs, tests, fields, path helpers, and documentation
   were removed or renamed. Current architecture/user/release docs and their
   drift verifier now describe atomic SQLite page/token commits rather than the
   deleted sidecar model.

Acceptance evidence for this checkpoint:

- `swift build` passed.
- Focused account/deletion/cursor/witness/post-commit coverage passed 39 tests
  across 5 Apple suites; focused CloudTraversal/install-lineage coverage passed
  15 core tests.
- The full Apple package passed 2,348 tests in 136 suites.
- The full core package passed 2,409 tests with 23 benchmark-only skips and no
  failures.
- The repository verifier suite passed 615 tests.
- `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` completed successfully,
  including schema/payload/freeze gates, production product builds, XcodeGen,
  local signed-bundle and Mach-O/resource/dependency-closure checks, and both MCP
  stdio smokes with 118 tools. No simulator, GUI automation, or CUA was used.

The remaining release boundary is external evidence, not an unresolved local
schema/sync implementation: promote and inspect the CloudKit Production schema,
then validate a distribution-signed installed build across real devices and its
App Group, privacy report, effective entitlements, and multi-device convergence.

## Canonical calendar timing trust boundary — 2026-07-16

This bounded checkpoint closes the first remaining schema-freeze blocker found
after the traversal/account checkpoint. It supersedes the preceding paragraph's
claim that only external evidence remained; the independent re-audit found
additional pre-freeze contracts, which are now kept open in
`FINDINGS_BACKLOG.md` until each is separately implemented and gated.

1. CloudKit calendar-event upserts now parse the five temporal fields into the
   domain's closed `CalendarEventTiming` enum before any SQL. Missing timed
   starts, reversed dates/times, and incomplete multi-day endpoints surface as
   per-envelope `invalidPayload` outcomes instead of materializing impossible
   rows or escaping as batch-fatal SQLite constraints.
2. Recurrence `UNTIL >= start_date` has one domain validator shared by workflow
   and sync writes. Optional timezones are trimmed and accepted only when
   Foundation resolves them as IANA identifiers. An explicit same-instant end is
   consistently legal across domain, workflow, sync, and SQLite; an omitted end
   remains the canonical point-event representation.
3. The baseline schema independently checks real canonical dates, canonical
   `HH:MM` values, all-day/timed field coupling, chronological order, required
   multi-day endpoints, and the generated recurrence bound. The repo remains in
   its declared pre-launch regime, so the baseline checksum was intentionally
   reseeded and mirrored rather than creating a fake migration for an unreleased
   schema.
4. New focused apply and raw-SQL tests pin both rejection and acceptance paths.
   Existing tests/benchmarks were corrected to create valid events. The generic
   field-round-trip probe no longer uses `INSERT OR IGNORE` for its calendar
   parent, because that construct swallowed CHECK failures and later reported a
   misleading child FK error.

Acceptance evidence: the full core package passed 2,420 tests with 23
benchmark-only skips; the full Apple package passed its 385 XCTest tests plus
2,348 Swift Testing tests. The 615-test repository verifier suite passed.
`LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` then completed the full
source gate: schema/payload/freeze and CloudKit-readiness checks, production app,
widget and MCP builds, XcodeGen generation, local signed-bundle validation,
Mach-O/resource/dependency closure, and both 118-tool MCP stdio smokes. Only the
credential-dependent GUI launch and distribution signing/notarization path was
intentionally skipped; no simulator, CUA or GUI automation was used.

## Payload evolution and calendar override finalization — 2026-07-16

This checkpoint closes the additive payload-evolution and calendar-override
schema blockers found by the post-timing independent review. The repository is
still pre-launch: the authoritative baseline was corrected in place, its
checksum reseeded, and both embedded Apple resources kept byte-identical.

> **Correction after a deeper convergence audit (2026-07-16):** item 4 below
> closed the local duplicate-ID/content-merge invariant only. It did **not**
> make scoped occurrence intent a single sync aggregate. Master EXDATE and the
> override still compete independently, and the master's EXDATE registry is a
> whole-set LWW field. The P0 redesign is tracked in `FINDINGS_BACKLOG.md`; this
> historical checkpoint must not be read as a claim that calendar occurrence
> sync is finalized.

1. Sync payload contract format 3 makes field evolution executable rather than
   documentary. Every field added to an existing entity must declare its
   introduction version, legacy-insert default, and stable meaning; numbered
   manifests may add entities or optional fields but cannot mutate released
   meanings or shapes. Reserved shadow spellings cannot later become wire keys.
   Canonical golden upserts populate every declared field, and strict JSON
   parsing rejects named nonfinite values and exponent overflow.
2. Runtime shadow handling now preserves opaque future fields through legacy
   updates and exact pending-inbox replays, advances the shadow base version,
   and re-emits a complete snapshot under a fresh dominating HLC. Schema version
   zero, non-`UInt32` versions, missing or corrupt shadows, and payload/version
   mismatches fail closed in apply, promotion, and generation-snapshot paths.
3. Any natural-key collision spanning two entity IDs defers while either
   participant carries an opaque future shadow. This prevents already-shipped
   older runtimes from irreversibly choosing one participant's known fields and
   deleting the other's unknown fields. A typed per-aggregate adapter registry
   is the explicit future escape hatch when a newer schema can merge those
   fields safely.
4. Calendar masters and materialized occurrence overrides now share one domain
   invariant across workflow, import, sync apply, and raw SQLite writes. An
   override must carry its series/date pair, cannot carry recurrence or own
   EXDATE rows, and natural-key collision convergence selects all content —
   including attendee annotations — from the max-HLC participant while keeping
   deterministic identity. Divergence diagnostics redact attendee PII.
5. Calendar and EXDATE civil-date constraints force normalization with
   `date(value, '+0 days')`, which behaves consistently on older Apple system
   SQLite releases, and reject year zero to match the Swift domain parser.
   Trigger coverage protects both child insertion/repointing and parent
   transitions into the override shape.
6. The contract verifier reports malformed reserved-key structures instead of
   crashing, and the structural field-round-trip probe now exercises recurring
   masters and materialized overrides as separate legal variants.

Acceptance evidence for this checkpoint:

- The repository Python verifier suite passed 633 tests.
- The full core package passed 2,474 tests with 23 benchmark-only skips and no
  failures.
- The full Apple package passed 2,349 tests in 136 suites.
- Schema embed, migration-ladder, schema-freeze, payload-contract, source
  hygiene, privacy, localization, CloudKit-readiness, XcodeGen, production
  product builds, local signed-bundle, Mach-O/resource/dependency closure, and
  both MCP stdio smokes passed under
  `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh`; `tools/list` returned
  all 118 tools. No simulator, CUA, or GUI automation was used.

Distribution-signed archive/device evidence and CloudKit Production promotion
remain external release work. The next local finalization pass remains bounded
to the still-open items in `FINDINGS_BACKLOG.md`; this checkpoint does not claim
those follow-up contracts are already closed.

## Runtime payload and focus-schedule provenance finalization — 2026-07-16

This checkpoint turns the numbered payload specification into an executable
runtime boundary and closes the focus-schedule arrival-order/privacy defects
before the pre-launch schema is frozen. The authoritative baseline and payload
version remain pre-release contracts, so their checksums and embedded resource
copies were intentionally reseeded in place rather than represented as a
fictional migration.

1. `LorvexSync` now loads the numbered payload manifest from a bundled SwiftPM
   resource and validates every inbound sync envelope before any hold, LWW/FK
   decision, payload-shadow write, or row mutation. The final coalesced outbound
   envelope crosses the same boundary. Current and historical contracts are
   exact; a future schema may add opaque top-level fields, but cannot mutate the
   type, enum, format, nested shape, identity, or cross-field semantics of a
   known field.
2. External import timestamps are canonicalized to UTC millisecond RFC 3339 at
   ingress. Reminder anchors now enforce both-or-neither local-time/timezone
   presence, canonical `HH:MM`, and a trimmed Foundation-resolvable timezone;
   SQLite independently rejects partial or malformed anchors.
3. Every saved focus event block carries explicit `canonical`, `provider`, or
   `freeform` provenance. Canonical event and task references are canonical
   UUIDs; provider/freeform blocks cannot fabricate one. Serialization no
   longer infers provenance from transient calendar-row presence, so arbitrary
   aggregate arrival order and full-resync order preserve canonical identity.
4. Calendar occurrences used for a proposal remain distinct display blocks,
   even when they overlap. A separate provenance-free interval union drives
   task packing and available-minute accounting. This preserves both event
   identities/titles without double-counting occupied time. Blocks are ordered
   children rather than globally identifiable values; the macOS and mobile
   lists key them by schedule position, so duplicate provider holds remain two
   legitimate rows.
5. Provider-derived titles are local calendar detail. Sync and all export paths
   neutralize them to `Event`; MCP/App-Intent reads additionally honor the
   device's calendar AI-access tier, omitting provider blocks at `off` and
   exposing only neutral occupancy at `busyOnly`. A detail-tier downgrade
   atomically scrubs already-saved provider labels without minting a new HLC,
   because the externally visible schedule was already neutral.
6. The app, nested MCP helper, and widget package the schema, checksum lock, and
   numbered payload resources. The release verifier checks the exact manifest
   inventory and byte identity in every executable surface rather than merely
   checking that a bundle directory exists. Test-only raw outbox insertion was
   removed from production source, and every test fixture crossing the runtime
   boundary now constructs a complete canonical envelope.
7. Oversized `ai_changelog` snapshots remain valid JSON: the writer emits a
   bounded structured truncation sentinel instead of slicing serialized UTF-8,
   and SQLite independently applies `json_valid` to both state columns. This
   closes the production failure exposed when the runtime manifest first
   rejected a sufficiently large task-with-reminders audit envelope.

Acceptance evidence for this checkpoint:

- The full Apple package passed 397 XCTest tests plus 2,354 Swift Testing tests
  in 136 suites, with no failures.
- The full core package passed 2,500 tests with 23 benchmark-only skips and no
  failures.
- The repository Python verifier suite passed 644 tests. Schema embed,
  checksum, empty pre-launch migration ladder, schema-freeze, runtime payload,
  CloudKit-readiness, localization, privacy, entitlement-source, metadata,
  source-hygiene, hotspot, and XcodeGen checks all passed.
- `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` completed with exit
  status zero. It built the production app, widget, and MCP products; validated
  the local signed bundle, exact packaged schema/checksum/payload resources,
  Mach-O files and dependency closure; and passed both the direct and packaged
  MCP stdio smokes with all 118 tools.

The credential-dependent GUI launch, distribution identity, notarization, and
installed-device evidence remain release-account work. No simulator, CUA, or
GUI automation was used for this checkpoint.

## Durable Watch command delivery finalization — 2026-07-16

This checkpoint replaces the best-effort Watch mutation bridge with a durable,
crash-safe command protocol while keeping the Watch a read-only replica of the
phone's authoritative Core database. The two local durability tables are
device-transport infrastructure, not user data: they are intentionally absent
from sync payloads, CloudKit records, native export/import, and MCP surfaces.

1. Every Watch mutation is wrapped in a strict, versioned, checksummed command
   envelope carrying a stable Watch installation ID and monotonically increasing
   sequence. The Watch atomically journals the command before changing UI state,
   never capacity-evicts unacknowledged work, drains in FIFO order, and removes a
   command only after an identity-bound application ACK. Retryable outcomes keep
   the head; deterministic rejections remain visible until explicit dismissal.
2. The phone owns a SQLite-backed high-water mark and immutable terminal receipt
   ledger. A terminal receipt and its domain mutation commit in the same write
   transaction, so process death cannot produce a mutation without a replayable
   ACK or an ACK without the mutation. Replays are idempotent indefinitely;
   command-ID/checksum collisions, sequence reuse, gaps, and workspace mismatch
   fail closed with typed outcomes.
3. Watch reads now come from a separate strict `watch_replica_v1.json` envelope
   delivered as replaceable latest state through `updateApplicationContext`.
   The projection is explicitly bounded (focus, habits, and briefing) and its
   complete binary-plist application context is kept below the transport limit.
   The Watch never falls back to opening a writable Core database.
4. Replica callbacks reserve a synchronous ingress sequence before entering an
   asynchronous task. The replica actor consumes that order before decoding or
   writing, preventing an older callback task from overwriting a newer workspace
   and then rejecting valid commands against the wrong workspace fence.
5. Watch `removeFromFocus` rechecks membership under the same `BEGIN IMMEDIATE`
   transaction that records its applied receipt. This closes the interleaving in
   which another writer could add the task after an external no-op check and the
   Watch would otherwise acknowledge a removal that never happened.
6. The old UserDefaults replay cache, in-process apply coordinator, mobile-store
   Watch mutation gate, and writable-snapshot fallback were removed. Current-state
   architecture and user documentation now describe the durable journal/ledger,
   application ACK, bounded replica, and user-visible pending/rejected states.

Acceptance evidence for this checkpoint:

- The Watch-focused matrix passed 117 tests in 18 Swift Testing suites plus the
  7 Core command-service XCTest cases, with no failures.
- The full Apple package passed 404 XCTest tests and 2,380 Swift Testing tests in
  137 suites, with no failures. The full Core package passed 2,507 tests with 23
  benchmark-only skips and no failures.
- The repository Python verifier suite passed 644 tests. Schema embed/checksum,
  empty pre-launch migration ladder, schema-freeze, payload-contract,
  CloudKit-readiness for all 19 syncable kinds, localization, privacy,
  entitlement-source, source-hygiene, hotspot, XcodeGen, production builds,
  local signed-bundle validation, Mach-O/resource/dependency closure, and both
  118-tool MCP stdio smokes passed under
  `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh`.
- A separate Xcode generic-device build compiled and validated the Watch app and
  embedded complication against the watchOS 26.5 SDK for both arm64 and arm64_32
  with `CODE_SIGNING_ALLOWED=NO`; this exercised the platform-only
  `.backgroundTask(.watchConnectivity)` branch that macOS SwiftPM builds omit.

The credential-dependent GUI launch, distribution signing/notarization, and
installed-device WatchConnectivity evidence remain release-account/device work.
No simulator, CUA, or GUI automation was used for this checkpoint.

## Recurrence editor and scoped-calendar contract checkpoint — 2026-07-16

This bounded checkpoint closes the lossy task-recurrence editors and the local
calendar recurrence patch/scoped-operation defects found during the next
independent audit. It does not claim the recurrence data model is sync-final:
the two cross-aggregate P0 findings below were discovered while validating this
work and remain the next schema-freeze checkpoint.

1. macOS and Mobile share a typed `TaskRecurrenceEditorDraft`. An unchanged
   editor round trip preserves the complete rule, including positional,
   termination, week-start, and anchor fields. Visible edits patch only their
   axis; independent peer edits merge, same-axis conflicts fail closed, and
   edits made during an asynchronous save rebase onto the persisted result.
   Explicit removal also refuses to overwrite a recurrence a peer added or
   changed after editing began.
2. Both stores include recurrence in dirty/fingerprint and selective-reload
   decisions, prevent overlapping saves, preserve current navigation, and map
   typed validation/concurrency errors through all 13 localization catalogs.
   Mobile exposes completion anchoring and reuses the localized shared weekday
   picker instead of raw RRULE tokens.
3. Calendar recurrence update is a typed `unset` / `clear` / `set` patch across
   service, stores, and MCP. A future opaque rule remains untouched until the
   user explicitly changes it; explicit None clears it. Frequency changes clear
   incompatible positional axes while preserving termination, and automatically
   derived weekday/month-day values follow date edits until the user overrides
   that axis.
4. MCP recurrence validation is strict at runtime: present-but-wrong-typed
   scalars and explicit empty create rules are rejected, ordinal BYDAY values
   are represented by the schema, and update omission remains distinguishable
   from explicit null. The frozen 118-tool manifest was regenerated only for
   these intentional schema-contract corrections.
5. Scoped calendar operations validate COUNT/UNTIL membership before writing,
   accept master or override identity, reuse an existing override, honor a moved
   replacement date, preserve cross-midnight/multi-day duration, support
   clearing optional fields, clean the known tail on split/all operations, and
   report truthful no-ops. EventKit now removes the old mirror only after the
   replacement write succeeds and routes override-addressed operations through
   the canonical series identity.
6. The audit proved that master EXDATE plus an independent override is still not
   one CloudKit aggregate: whole-set EXDATE LWW can lose concurrent skips or
   converge beside a surviving override. It also proved that recurring-task
   parent completion and successor creation can converge as `parent.open +
   successor.open`. Both are recorded as P0 in `FINDINGS_BACKLOG.md`; the older
   “schema already optimal” design note is explicitly superseded until they
   land.

Acceptance evidence for this checkpoint:

- The final full Apple run passed 2,410 Swift Testing cases in 138 suites; the
  full Core package passed 2,507 tests with 23 benchmark-only skips. An earlier
  parallel run hit the repository's documented
  `appStoreRefreshesLoadedTaskWorkspaceAfterStatusMutations` load flake; the
  exact test passed alone, and the final full run passed it in-suite.
- The repository Python verifier suite passed all 644 tests. Schema/checksum
  embed, empty pre-launch migration ladder, payload contract, CloudKit readiness
  for all 19 syncable kinds, 13-language catalogs, privacy, entitlement-source,
  metadata, source hygiene, hotspot, XcodeGen, and the unchanged 118-tool MCP
  catalog all passed.
- `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` exited zero after
  release-mode app/widget/MCP builds, local signed-bundle and Mach-O/resource
  closure validation, and both direct and packaged MCP stdio smokes.

Distribution signing/notarization, real App-Group entitlement validation, and
installed-device evidence still require the release account and real signed
archive. No simulator, CUA, or GUI automation was used for this checkpoint.
