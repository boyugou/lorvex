# Independent Apple Schema and Sync Finalization Audit — 2026-07-14

## Scope and baseline

- Audited branch: `main`.
- Audited commit: `61600c8706137486686b000fcf4d7e360dfaab0d`.
- At audit start, `HEAD` and `origin/main` matched and the worktree was clean.
- During final write-up, `origin/main` advanced to `25fd47b4924538154396ac8c372df15db35fda93`
  (`feat(apple): route contact/privacy/support entry points to lorvex.app`). A scoped diff confirms that
  commit changes no schema, migration, sync-core, CloudKit, retention, or audited write-funnel file, so
  every schema/sync conclusion below also applies to that newer `origin/main`.
- Scope: the Apple Swift implementation, with a deep review of the canonical SQLite schema,
  embedded schema, migration/freeze machinery, all syncable aggregates, CloudKit record mapping,
  inbound/outbound queues, LWW/HLC conflict handling, tombstones, forward compatibility, account and
  zone recovery, import interactions, diagnostics, packaging gates, and relevant current Apple
  documentation.
- This was a source-level and automated-gate audit. It did not use CUA, simulator clicking, or a live
  Apple Developer account.
- This review makes no product-code, schema, entitlement, or build-configuration changes. It adds only
  this audit record.

## Executive verdict

**No: the schema/sync system cannot yet be described as completely finalized.**

The important nuance is that the repository is not generally in poor shape. The relational SQLite
schema and most of the convergence engine are unusually mature, and all available local gates pass.
The remaining problems are concentrated in a few lifecycle boundaries that green unit tests do not
currently model:

1. AI activity-log retention can delete local rows while leaving their full-content unsynced upserts
   queued for a later iCloud enablement; CloudKit audit records are soft-deleted rather than physically
   removed, so cloud record count and privacy-sensitive content do not obey the UI's apparent retention
   contract.
2. **Resolved after this audit:** zone rebuilds now use a crash-durable
   `beginZoneRebuild` / `completeZoneRebuild` lease state machine with
   `.ifServerRecordUnchanged` CAS transitions and durable local recovery state.
3. “Adopt the zone as truth” intentionally leaves local rows that are absent remotely as ordinary live
   rows. A later edit gives such a row a fresh HLC and can publish it fleet-wide, so the accepted
   single-device divergence is not durably isolated.

The first and third findings remain freeze decisions in this audit snapshot; the former zone-generation
blocker is resolved. The third needs an explicit product/protocol decision before the schema is frozen,
because the clean solution may require durable quarantine/suppression metadata.

Separately, the freeze tripwire is still deliberately dormant and the production CloudKit container
has not been proven. Therefore the current state is best described as a **strong pre-release schema
candidate**, not a frozen schema or a submission-ready sync system.

## What was independently verified as strong

### SQLite and migrations

- `schema/schema.sql` loads successfully in SQLite; `PRAGMA integrity_check` returns `ok`.
- Every ordinary application table is `STRICT`.
- The schema currently declares 42 ordinary application/infrastructure tables and 3 FTS virtual
  tables; SQLite materializes 58 table objects after including FTS internals. It also creates 102
  indexes including automatic/FTS indexes and 14 triggers.
- Foreign keys, parent-owned materializations, relation-edge identities, recurrence uniqueness,
  inbox/list deletion handling, enum checks, hot-query indexes, FTS maintenance, outbox coalescing,
  pending-inbox identity, and tombstone identities are deliberately modeled rather than accidental.
- The canonical schema, the Apple embedded schema, checksum locks, and the empty pre-launch migration
  ladder pass their parity and integrity gates.
- The runtime migration runner validates checksums, never replays the frozen baseline, requires a
  contiguous append-only ladder, uses an atomic `BEGIN IMMEDIATE` migration transaction, rejects
  downgrade/unknown states, and handles concurrent initialization.
- Managed-store opening performs schema-completeness and SQLite health checks and quarantines a corrupt
  database rather than silently continuing.

### Sync and CloudKit

- The current inventory contains 18 syncable entity kinds and the readiness verifier covers all 18.
- A single encrypted `LorvexEntity` record shape carries every syncable kind. The record name is an
  opaque SHA-256 of type and identity; all seven custom envelope fields are stored through
  `encryptedValues`.
- Normal entity writes use CloudKit change tags through `.ifServerRecordUnchanged`, then resolve a
  `serverRecordChanged` conflict with the canonical HLC comparison. This is the correct shape for a
  custom LWW engine.
- Inbound change tokens are saved only after records apply or are durably parked, and per-record fetch
  failures withhold the token.
- Account identity, user consent, storage-instance replacement, encrypted-key reset, zone recreation,
  system-field caches, subscription results, partial CloudKit operation results, and transient error
  classification all receive explicit treatment.
- All current syncable kinds have outbound/inbound field-round-trip probes. Descriptor-backed field
  sets, unknown-field shadows, pending-inbox retention, tombstone/redirect handling, unique-key merge
  convergence, task-list fallback, and full-resync backfill are extensively tested.
- The permanent compact tombstone ledger and its full-resync backfill close the common stale-upsert
  resurrection path in a stable or correctly rebuilt zone.

These positives matter: the right conclusion is not “rewrite sync.” It is “do not freeze the remaining
edge contracts before closing or consciously accepting them.”

## Freeze-blocking findings

### B1 — HIGH — AI activity retention and the outbound/cloud lifecycle do not form one contract

Relevant implementation:

- `apps/apple/core/Sources/LorvexSync/AuditRetention.swift`
- `apps/apple/core/Sources/LorvexSync/SyncRetention.swift`
- `apps/apple/core/Sources/LorvexSync/FullResyncBackfill.swift`
- `apps/apple/core/Sources/LorvexSync/Tombstone.swift`
- `apps/apple/Sources/LorvexCore/Services/SwiftLorvexCoreService+WriteSurface.swift`
- `apps/apple/Sources/LorvexCore/Services/SwiftLorvexCoreService+Preferences.swift`
- the macOS and mobile Activity Log Retention settings surfaces

There are three different retention planes, and they currently disagree:

1. **Local SQLite rows.** `.days` and `.maximum` prune old rows; `.off` deletes every local row and
   suppresses new local audit writes.
2. **The unsynced outbox.** While sync is off, local maintenance calls retention without an emit hook.
   It deletes the `ai_changelog` row but intentionally keeps ordinary unsynced outbox entries under the
   50,000-row cap so a future iCloud enablement can drain them.
3. **CloudKit.** Retention “deletes” overwrite a `LorvexEntity` record with a marked delete envelope.
   They do not physically delete the CKRecord. `.off` emits no per-row deletion at all.

#### Concrete failing sequence

1. Cloud sync is off.
2. A mutation creates an `ai_changelog` row and a full-content outbox upsert.
3. The row ages outside a `.days` window, or the user changes the policy to `.off`.
4. Local maintenance deletes the audit row with `emit: nil`; `.off` also deliberately emits nothing.
5. The matching unsynced full-content outbox upsert remains pending.
6. The user later enables iCloud.
7. The old audit payload can now upload even though the local retention policy already deleted it.

Existing maintenance tests explicitly assert that a within-cap unsynced outbox row survives the
sync-off sweep. Existing retention tests prove local deletion and the live-sync marked-delete path,
but do not compose the two behaviors for an audit upsert.

Receivers may discard the row according to their local horizon, but that does not undo the upload or
remove the full-content CKRecord. The private database counts against the user's iCloud quota, and one
soft-deleted record remains for every lifetime audit entry. The UI strings “Off (never store)” and
“clears existing entries on all your devices” are therefore stronger than the cloud-storage behavior.

This is both a correctness/privacy issue and the dominant CloudKit scale risk: every ordinary mutation
can create an audit record containing before/after material, while neither `.off` nor the normal
retention path guarantees physical cloud removal.

#### Required decision before freeze

Choose one product contract, then test it across all three planes:

- **Recommended simplest contract:** keep `ai_changelog` device-local and do not sync it. The durable
  MCP idempotency/audit requirements can remain local; ordinary domain data still syncs.
- **If cross-device activity history is required:** add durable purge knowledge (for example a synced
  cutoff/generation), cancel or replace matching pending audit upserts when retention prunes them, and
  design safe physical CKRecord deletion/compaction. A separate audit zone is worth considering.

At minimum, a local retention prune must remove or coalesce any unsynced audit upsert for the same ID,
and `.off` must prove that old payloads cannot upload after sync is re-enabled. That minimum fix alone
does not solve monotonic CloudKit record-count growth.

### B2 — RESOLVED — Zone rebuild generation is CAS-serialized and crash-durable

Relevant implementation:

- `apps/apple/Sources/LorvexCloudSync/CloudSyncRecordPushing.swift`
- `apps/apple/Sources/LorvexCloudSync/CloudSyncEngineCoordinator+ZoneEpoch.swift`
- `apps/apple/Sources/LorvexCloudSync/CloudSyncEngineCoordinator+AccountGate.swift`
- `apps/apple/Sources/LorvexCloudSync/CloudSyncEngineCoordinator+AccountAdopt.swift`

`LorvexZoneEpoch` remains in the private database's default zone so it survives deletion of the custom
sync zone. A rebuild now first claims a `rebuilding` lease with a bounded
`.ifServerRecordUnchanged` CAS loop, persists that exact lease locally, rebuilds and confirms the full
baseline, then CAS-publishes `ready` and enrolls locally. Ordinary sync fails closed while the remote
generation is rebuilding. `serverRecordChanged` retries re-fetch the winning record, stale leases have
a bounded takeover policy, and the completing lease remains as an idempotency witness for
remote-success/local-failure recovery.

The prior one-step epoch API and `.changedKeys` update path have been removed. Tests now cover
concurrent claims, missing per-record results, account-boundary changes immediately before CAS,
default-zone survival, lagging-device monotonicity, remote failure across relaunch, and local
completion failure without inventing another generation.

### B3 — MED-HIGH — “Adopt zone as truth” does not durably isolate rows absent from that truth

Relevant implementation:

- `apps/apple/Sources/LorvexCloudSync/CloudSyncEngineCoordinator+ZoneEpoch.swift`
- the over-window branches in `CloudSyncEngineCoordinator+AccountGate.swift`
- outbox quarantine/re-arm behavior in `Outbox.swift` and `OutboxCoalesce.swift`

The over-window path correctly quarantines pre-adoption pending outbox entries and forces a nil-token
pull. The permanent tombstone ledger means a normal delete record that is present in the rebuilt zone
will delete a stale local row. Those are real improvements over the earlier implementation.

However, the code explicitly says that an ordinary local row absent from the adopted zone is left live
as “accepted single-device divergence.” Nothing durably marks that row as quarantined or local-only.
After adoption saves a fresh checkpoint, a later user/assistant edit mints a new HLC and the normal
coalescing path re-arms or replaces the exhausted outbox entry. The row can then publish to the fleet.

The dangerous case is the one the epoch protocol exists to handle: a long-inactive device becomes the
rebuilder of an empty/replaced zone and lacks another device's deletion knowledge. It adopts the empty
zone, retains its stale live row, and can later edit that visible row. A healthy peer's older permanent
tombstone will lose to the newly minted HLC, so the entity is resurrected rather than merely lingering
on one device.

This behavior may be chosen intentionally, but it is not a true “remote is authoritative” snapshot and
the divergence is not permanently unsynced.

#### Required decision before freeze

- **Authoritative adoption:** inventory the complete zone and atomically remove/quarantine local synced
  rows absent from it, preserving explicitly local-only tables. Create a safety export before destructive
  reconciliation if desired.
- **Recovery-area adoption:** move absent local rows into a visible recovery/quarantine set and require
  an explicit user action to recreate them with a new identity/HLC.
- **Intentional resurrection semantics:** rename/document the behavior honestly and add a test proving
  what happens when the retained row is edited after adoption.

The first two options may need durable schema state, which is why this must be decided before arming the
SQLite freeze.

## Other correctness and future-compatibility findings

### H1 — MEDIUM — CloudKit inbound decoding does not execute the canonical envelope validation contract

`SyncEnvelope.validate()` says every incoming transport must call it. It checks canonical entity IDs,
field lengths, device-ID bounds, payload size, JSON validity/depth, and an absurdly-ahead payload schema
version. Outbox enqueue/coalesce calls it; `CloudSyncEnvelopeRecord.decode` does not.

The CloudKit decoder checks record type, required encrypted fields, record-name binding, canonical HLC,
future-clock skew, canonical integer parsing, and known/future type/operation handling. It then returns
the constructed envelope directly. `Apply.applyEnvelope` also does not call the full validator.

Consequently, a CloudKit record can reach apply/parking with envelope properties the shared transport
contract says are invalid, including an empty/oversized device ID or a schema version more than 100
generations ahead. JSON parsing and some entity-specific validation catch part of the surface later,
but not the whole contract at the wire boundary.

Construct a known envelope in `decode`, call `validate()`, and map failure to `.corrupt`. Define equivalent
bounded checks for the raw unknown-type parking lane. Add tests for every cap and for token advancement
past a rejected record.

Related low-level issue: `maxEnvelopePayloadBytes` is exactly 1 MiB, while Apple's 1 MiB CKRecord limit
includes all non-asset fields, not just `payload`. Current first-party aggregate caps make a near-limit
payload unlikely, but the transport constant should reserve encryption/field overhead or prove a lower
aggregate-wide bound.

### H2 — MEDIUM — A dead-lettered outbound entity has no automatic recovery trigger

An outbox row is excluded after ten permanent/wholesale failures; repeated identical per-record errors
can fast-forward at the third observation. Seven days later retention deletes the dead-letter row after
writing a diagnostic breadcrumb.

An equal-version full-resync backfill can re-arm an exhausted row, which is good. The missing link is
that exhausting a row does not set `reseed_required` or any other durable full-resync trigger. A future
app version that fixes the encoder/server mismatch does not automatically revisit the entity. Unless the
user edits it or an unrelated reseed happens, the server can retain stale state forever.

Diagnostics expose `failed_count`, but there is no user/MCP recovery action that requeues the current
entity snapshot. Before deleting a dead letter, set a durable reseed/requeue marker or retain a compact
entity/version failure ledger. Re-arm valid current snapshots on a compatible app/payload-schema upgrade.
Keep intentional over-window quarantine distinct so a generic requeue cannot revive deliberately dropped
pre-adoption state.

#### Follow-up resolution — closed in the post-audit working tree

Ordinary exhaustion now enters typed `retry_wait` with a persisted due time and
recovery round. The canonical pending read re-arms due rows in bounded slices on
an increasing 1h / 6h / 1d / 3d / 7d schedule; neither age retention nor the
sync-off active-backlog cap deletes them. `consecutive_error_count` makes the
three-identical-error acceleration a real per-record streak and is reset by
transient/wholesale failures and by each due recovery round. In contrast,
snapshot adoption uses `authoritative_adoption`, has no due time, is excluded
from failed-outbox diagnostics, and cannot be revived by an equal-version
backfill. New partial indexes cover active pending reads, due retries, and the
normally-empty authoritative-fence retention partition. Unit and service tests
pin due boundaries, increasing backoff/no tight loop, decode-poison recovery,
LWW coalescing, adoption isolation, both GC paths, diagnostics, and the
`A, B, B` versus `A, B, B, B` streak distinction.

### H3 — MEDIUM — Task lifecycle state is not coupled to `completed_at`

The schema constrains `tasks.status` to `open|in_progress|completed|cancelled|someday`, but it does not
couple the value to `completed_at`. The inbound task applier requires `status` while treating
`completed_at` as an optional partial field. Its own `InProgressSyncTests` apply a fresh `completed`
payload without `completed_at` and accept it.

This permits both:

- `status = 'completed'` with `completed_at IS NULL`;
- a reopened/in-progress task that preserves an old non-null `completed_at` when a partial payload omits
  the clear.

Completion-history, overview, and weekly-review reads use `completed_at`, so a row can be visibly complete
but absent from completion-period reporting, or open while carrying stale completion chronology.

Decide the invariant now. The clean contract is `completed` iff `completed_at` is non-null, with every
lifecycle transition transmitting both fields atomically. Enforce it at the inbound aggregate boundary;
a DB `CHECK` is also reasonable if all rolling-version payloads are normalized before SQL execution.

### H4 — MEDIUM — No release gate binds sync-field evolution to `payloadSchemaVersion`

The forward-compatibility design is strong, but it depends on authors bumping
`LorvexVersion.payloadSchemaVersion` when a new synced payload field or incompatible semantic is shipped.
The current value is `1`. Field round-trip tests prove current outbound/inbound symmetry, but no verifier
compares the released per-kind payload-field manifest with the new tree and requires a version bump.

If a developer adds a field without bumping the generation, an old client treats the envelope as fully
understood rather than forward-compatible. It may edit and re-emit the entity without preserving the new
field, defeating the payload-shadow system.

Before the first release, freeze a machine-readable manifest of every kind's wire fields and relevant
semantics. A gate should require one of:

- no manifest change;
- a deliberate payload-schema bump plus forward/backward tests;
- an explicitly classified non-wire change.

SQLite migration versioning and sync payload versioning are separate contracts; arming one does not
protect the other.

### H5 — MEDIUM design acceptance — Permanent soft-deletion is correct but unbounded

`sync_tombstones` is now a permanent local death ledger, and every entity's CloudKit record is overwritten
with a delete envelope rather than physically removed. This is a conservative and coherent convergence
choice for indefinitely offline peers. It also means both the local ledger and CloudKit record population
grow by one per lifetime entity deletion.

For normal task/list/habit volume, this can be an acceptable explicit tradeoff. It should not be called
bounded: one compact row per lifetime delete is not a fixed bound, and the CloudKit private database uses
the user's iCloud quota. The audit stream in B1 makes the scale difference material.

Record an expected lifetime scale envelope and test a realistic high-water database/backfill. If the
product accepts permanent ordinary-entity tombstones, that decision does not itself block launch. The
high-frequency `ai_changelog` stream still needs a different lifecycle.

### H6 — LOW — Current-state documentation still overstates or misstates parts of the implementation

Examples at this commit:

- `cloudkit/schema.ckdb` says “All 20 syncable entity types”; the verified inventory is 18.
- `SwiftLorvexCoreService+OutboxFlush.swift` still says there is no delete lane and retention is
  device-local, while live audit retention now emits marked delete envelopes.
- Several comments say the zone or ledger is “bounded” when they mean compact per record, not bounded in
  lifetime record count.
- Some sync-semantics documentation retains Rust/cross-runtime language after Apple schema ownership was
  decoupled.
- Finalization backlog text says all CloudKit hardening residuals are closed, but it does not cover the
  epoch CAS, epoch durability, or post-adoption edit sequence above.

These are not runtime blockers, but stale protocol prose is dangerous immediately before a schema/wire
freeze because future changes will use it as the design authority.

## Freeze and production state

There are three independent freezes; none should be conflated:

1. **SQLite schema freeze.** `schema/migration_policy.json` still contains `"launched": false`, a null
   frozen baseline, and an empty ladder. `verify_schema_freeze.py` correctly reports the tripwire as
   dormant. MAS/iOS archive scripts intentionally refuse a normal release archive until it is armed.
2. **Sync payload protocol freeze.** There is no released-field manifest/version-bump gate yet, and the
   findings above can affect wire behavior even without changing a SQLite column.
3. **CloudKit production schema.** A source `schema.ckdb` and readiness verifier are not proof that the
   exact types, encryption flags, and fields exist in Production. App Store builds use Production only,
   and production changes are additive: deployed types/fields cannot simply be deleted later.

Therefore the correct sequence is to resolve schema/wire decisions first, then arm the SQLite freeze,
then deploy the final CloudKit schema and test the production environment. Promoting CloudKit first would
turn easily editable pre-release choices into permanent additive history.

## Verification evidence

The following all passed on the audited commit:

| Gate | Result |
| --- | --- |
| `cd apps/apple/core && swift test` | 2,211 tests, 0 failures; 23 benchmark skips |
| `cd apps/apple && swift test` | 2,312 Swift Testing tests in 131 suites, 0 failures |
| `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` | PASS |
| Python verifier tests inside the full gate | 520 passed |
| SQLite schema/embed/checksum/migration ladder | PASS; freeze DORMANT |
| CloudKit readiness | PASS; 18 syncable kinds covered |
| MCP manifest and stdio smoke | PASS; `tools/list` returned 118 tools |
| Localization catalogs | PASS; 13 languages in the gate |
| Release build/package-structure/local-sign checks | PASS |

The full gate intentionally did not prove GUI signing identity, notarization, a real MAS provisioning
profile, App Store upload, or a live production CloudKit container. Those require the account/artifact
phase.

## Required production evidence after code convergence

Before claiming release readiness:

1. Arm the SQLite schema freeze only after B1–B3 and H3–H4 are decided.
2. Re-run the full gate from a clean release worktree.
3. Import/deploy the final CloudKit schema to Development, inspect the pending diff, then promote the exact
   schema to Production.
4. Export or otherwise record the Production schema as release evidence; verify both record types, every
   field type, and encryption status.
5. Run a production/TestFlight two-device matrix covering concurrent edits, deletes, offline return,
   account change, user cloud-data deletion/re-opt-in, encrypted-data-key reset, custom-zone deletion,
   concurrent rebuild, app termination mid-push/pull, and a deliberately injected per-record failure.
6. Test sync-off retention followed by sync enablement and confirm through CloudKit Console that forbidden
   audit payloads never upload and any required physical deletions actually occur.
7. Build the exact signed MAS archive with final profiles/entitlements, generate Xcode's privacy report,
   validate the upload, and retain the signed-artifact evidence.

## Recommended implementation order

1. Decide whether `ai_changelog` is local-only or a true cross-device product; fix the three-plane
   retention contract.
2. Make zone generation advancement CAS-based and durably retryable.
3. Decide true authoritative replacement versus explicit recovery quarantine for over-window adoption.
4. Enforce CloudKit inbound envelope validation.
5. Add dead-letter recovery and separate it from intentional adoption quarantine.
6. Lock task lifecycle/completion chronology and add the sync-field manifest/version gate.
7. Reconcile current protocol documentation and rerun all gates.
8. Arm the SQLite freeze.
9. Promote and prove the CloudKit Production schema.
10. Run signed-artifact and real multi-device release validation.

## Apple contracts used in this audit

- [CKModifyRecordsOperation save policy](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/savepolicy):
  `.ifServerRecordUnchanged` compares record change tags; `.changedKeys` does not.
- [Deploying an iCloud container's schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema):
  App Store builds access Production, and production schema changes are additive.
- [CKContainer privateCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase):
  private-database data counts against the user's iCloud storage quota.
- [CKRecord](https://developer.apple.com/documentation/cloudkit/ckrecord): non-asset data in one record
  must not exceed 1 MiB, and Production rejects unknown types/keys.
- [Deciding whether CloudKit is right for your app](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app):
  the low-level CloudKit API leaves records, conflicts, account changes, notifications, and change tokens
  to the application.

## Final classification

- **Relational schema quality:** strong, close to freeze.
- **Migration machinery:** strong and appropriately fail-closed; intentionally not armed.
- **Ordinary entity convergence:** strong, with unusually broad test coverage.
- **Audit retention/cloud lifecycle:** not final; freeze blocker.
- **Zone rebuild/wipe generation protocol:** not final; freeze blocker.
- **Over-window adoption semantics:** unresolved product/protocol contract; decide before freeze.
- **Rolling-version payload governance:** implementation strong, release-process gate incomplete.
- **CloudKit Production readiness:** not yet evidenced.
- **Overall:** **NO-GO for the claim “schema and sync are completely finalized”; GO for a focused final
  hardening pass rather than architectural replacement.**
