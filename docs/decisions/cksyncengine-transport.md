# Decision record: CloudKit transport on CKSyncEngine

**Status:** Accepted 2026-09-30. The transport runs on `CKSyncEngine`, and
schema migration `002_retire_custom_sync_transport` removes the retired
protocol's tables and columns (see "Schema").

## Context

Lorvex syncs a full local SQLite database per device through the user's
private CloudKit database. The sync stack has two layers:

- **Transport** (`LorvexCloudSync`, about 10,000 lines): moves records between
  SQLite and CloudKit. It implemented its own protocol on top of raw CloudKit
  operations: an account-qualified *generation* of custom zones named
  `LorvexGeneration-e<epoch>-<generation>`, a default-zone control record that
  every request re-read before and after its I/O, a rebuild lease, traversal
  witnesses and incremental cursors stored in SQLite, generation snapshots used
  to compact tombstones, an authoritative-snapshot adoption flow, and a synced
  retention frontier plus physical-delete queue for `ai_changelog`.
- **Apply layer** (`LorvexSync` in the core package): decodes envelopes, runs
  hybrid-logical-clock (HLC) last-writer-wins merges, grouped registers,
  entity redirects, the pending inbox, payload shadows, and future-record holds.

The apply layer has been stable. The transport has been the source of nearly
every sync incident: a cycle that deleted and republished its traversal witness
on every pass, retention metadata saved twice per cycle even when unchanged,
about a hundred sequential CloudKit requests per cycle caused by per-request
boundary checks, a progress predicate that could never report "no progress",
pull failures that blocked pushes, and scheduling, retry, subscription, and
stall-guard logic reimplemented per platform. Each fix added protocol surface,
and the protocol had no second implementation or server-side counterpart to
check it against.

Apple ships `CKSyncEngine` (iOS 17, macOS 14) for exactly this shape: one
private-database zone, records mirrored from a local store, change-token
bookkeeping, push subscriptions, system-scheduled sync, automatic retry and
throttling, account-change and zone-deletion events. The deployment floor is
the 26 SDKs, so it is available everywhere Lorvex runs.

## Decision

Replace the custom transport with a `CKSyncEngine`-based one. Keep the record
format and the entire apply layer. Delete the generation, witness, snapshot,
lease, and audit-retention protocol together with the SQLite tables that only
that protocol used.

## What stays

- **Record format.** One record type, `LorvexEntity`, whose seven wire fields
  are all end-to-end encrypted, with the SHA-256 opaque record name
  `SyncRecordName.opaque(entityType:entityId:)`. `CloudSyncEnvelopeRecord`
  encodes and decodes it unchanged. Production CloudKit record types cannot be
  deleted, so the schema in `cloudkit/` stays compatible.
- **Logical deletes.** A delete is a `LorvexEntity` record with
  `operation = delete`, never a CloudKit record deletion. The apply layer needs
  the tombstone's HLC to order a delete against a concurrent edit.
- **The apply layer** (`applyInbound`, the pending inbox, redirects,
  future-record holds, payload shadows) and the payload manifests in
  `schema/sync_payload/`.
- **The outbox** (`sync_outbox`) as the durable authority for what this device
  still has to upload, including its retry and future-record-hold dispositions.
- **Conflict classification.** A `serverRecordChanged` rejection is classified
  exactly as before: exact semantic replay confirms, a schema-ahead server
  record is parked, typed semantic joins and equal-HLC contenders go to Core's
  transactional reconciliation, and otherwise the HLC decides. The classifier
  becomes a pure function of the client and server records.
- **The pause and consent model**, reduced to the reasons that still exist
  (below), and the user-facing Settings flows for turning sync on, adopting a
  different iCloud account, and deleting iCloud data.

## What goes

- Custom zone generations, the default-zone control record, rebuild leases,
  retired-zone ledgers, and the zone epoch.
- Traversal witnesses, incremental cursors, traversal progress, corrupt-record
  fences, and per-request account and generation boundary checks.
- Generation snapshots and tombstone compaction. Tombstones stay in CloudKit
  for the life of the zone. A personal task database produces a few thousand
  small records a year, far below any quota concern, and keeping tombstones
  removes the only reason the snapshot protocol existed.
- Authoritative-snapshot adoption and its outbox discard fence.
- Synced `ai_changelog` rows, the retention frontier, the audit cloud-presence
  ledger, and the physical-delete purge queue. See "Assistant change log".
- The hand-written push subscription, retry wake, pacing breaker, stall guard,
  and the `recordPlan` debug mode. `CKSyncEngine` owns scheduling, retry,
  throttling, and subscriptions.

## Design

### Ownership

Only the macOS app and the iOS/iPadOS app construct the transport, one engine
per process for the private database. MCP, widgets, App Intents, the watch,
and CarPlay still write only through `LorvexCoreServicing`, whose mutations
enqueue outbox rows. The main app learns about helper-process writes through
`DatabaseChangeSignal` and hands the new outbox rows to the engine.

The engine is created soon after launch whenever sync is on, with
`automaticallySync = true`, and torn down when sync is turned off.

### Zone

All records live in one zone, `Lorvex`, in the private database. The zone is
created by a pending `saveZone` database change before the first record batch.

A local checkpoint, `cloudkit.zone_established`, records that this device has
successfully saved to or fetched from the zone. It distinguishes the first
upload (create the zone) from a zone that disappeared (see "Zone deletion").

### Engine state

The engine's `stateSerialization` is stored as base64 JSON in
`sync_checkpoints` under `cloudkit.engine_state`, written on every
`stateUpdate` event.

The engine delivers events one at a time and waits for each handler.
`fetchedRecordZoneChanges` is therefore always applied before the
`stateUpdate` that covers it. If the process dies between the two, the next
launch fetches the same records again, and the HLC apply treats them as
replays. The state and the apply do not need to share a transaction.

The one failure that must not be absorbed is an apply that throws (for example
while iOS has suspended the database in the background). When an apply fails,
the transport stops persisting state for the rest of that engine's lifetime
and sets the engine aside, so it stops fetching batches that cannot be
applied. A new engine is built from the last persisted state on the next
explicit sync, or after a backoff that starts at 30 seconds and doubles with
every consecutive failure up to 10 minutes. A successful fetch resets the
backoff. A record is never marked fetched unless it was applied or durably
parked.

An engine that has been set aside, for any reason, can no longer act: every
callback first checks that it comes from the current engine, and a sent batch
whose engine was replaced while it was being committed is not committed. Its
rows stay unsynced and go out on the next engine.

### Outbound

1. Canonical mutations enqueue outbox rows, as today.
2. Before each explicit sync, and whenever `DatabaseChangeSignal` fires, the
   transport adds a `saveRecord` pending change for every record name with an
   unsynced, eligible outbox row. `CKSyncEngine` deduplicates pending changes.
3. `nextRecordZoneChangeBatch` reads the next page of pending outbound
   envelopes from the outbox (coalesced per entity by Core, rows in
   `retry_wait` excluded until due), builds `LorvexEntity` records on top of
   the cached server system fields when present, and records which outbox ids
   each record carried. When the outbox has nothing eligible, it removes the
   remaining record-zone saves from the engine state.
4. `sentRecordZoneChanges` commits the whole result through
   `reconcileOutbound` in one transaction: saved records confirm their outbox
   ids and cache the returned system fields; failures are classified below.

If the process dies after CloudKit saved a batch but before the
reconciliation committed, the outbox rows stay unsynced and are sent again.
The server now holds the same HLC, so the save conflicts, the classifier finds
an exact replay, and the rows are confirmed.

### Failed saves

| CloudKit error | Handling |
| --- | --- |
| `serverRecordChanged` | Classify client versus server record. Server wins: apply the server envelope and confirm. Local wins: cache the server record's system fields and re-add the pending save, so the next batch writes on top of the current change tag. Exact replay: confirm. Typed join or equal-HLC contender: hand the collision to `reconcileOutbound`. Schema-ahead server record: park it and hold the local intent. |
| `zoneNotFound` | Zone never established: add `saveZone` and re-add the save. Zone established: treat as a zone deletion. |
| `unknownItem` | Drop the cached system fields and re-add the save. |
| `quotaExceeded` | Leave the rows unsynced, surface "iCloud storage is full", and re-add pending saves on the next foreground. |
| Transient (network, zone busy, throttled, not authenticated) | Nothing; the engine retries. |
| Anything else | Record a per-record failure on the outbox row, which applies the existing retry and give-up policy. |

When Core records that outbox rows were lost (rows dropped at the outbox cap
while sync could not drain it, or rows a backfill had to skip), it sets the
`reseed_required` checkpoint. Every engine start and explicit sync then runs
the full backfill again, which clears the checkpoint once it re-queued every
row. After a record saves, any newer local edit of it that is still unsynced
is queued again, so an edit made while an older version was in flight is not
left waiting for the next local change.

### Inbound

`fetchedRecordZoneChanges` decodes each modification. Decoded envelopes and
schema-ahead raw records go to Core in one `applyInbound` call; corrupt records
are counted as undecodable; foreign record types are ignored. Record deletions
are ignored: Lorvex never deletes records individually. The fetched records'
system fields are cached so a later local edit does not start with a conflict.

After each fetch or send completes, the transport publishes a report
(applied entity kinds, counts, errors) that the app uses to reload the affected
surfaces, exactly as it did with cycle reports. Syncs started by the engine on
its own (a push, the system scheduler) publish the same report.

### Account changes

When the engine reports an account change, or the app receives
`CKAccountChanged`, the running engine is set aside before anything else
happens, so no record crosses between accounts while the account is checked.
The account is then evaluated again, and one of the rules below applies.

The transport keeps the existing account fingerprint store (a hash of the
CloudKit user record ID) to know which account the local data was last synced
with.

- **Sign in** to the same account as the fingerprint, or with no fingerprint:
  sync continues. With no fingerprint the device uploads everything it has
  (a full backfill into the outbox) and merges what it fetches.
- **Sign in to a different account, or switch accounts:** pause with
  `accountChanged`. Local data is kept. When the user chooses to sync with the
  new account, the transport discards the engine state and cached system
  fields, stores the new fingerprint, enqueues a full backfill, and starts a
  fresh engine. Both sides then merge by HLC.
- **Sign out:** stop syncing and keep local data. Nothing is deleted locally;
  Lorvex is local-first.

### Zone deletion

`fetchedDatabaseChanges` reports deleted zones with a reason.

- **`deleted` or `purged`** (Delete iCloud Data on another device, or the user
  removed Lorvex's data in iCloud settings): pause with `userDeletedZone`,
  discard engine state and cached system fields, and keep local data. Turning
  sync back on is an explicit user action that re-uploads everything into a new
  zone.
- **`encryptedDataReset`** (the user reset their iCloud Keychain end-to-end
  encryption keys): the data was lost, not withdrawn. Discard engine state and
  re-upload everything automatically, as Apple recommends.

**Delete iCloud Data** on this device queues `deleteZone` for `Lorvex`, sends
it, pauses with `userDeletedZone`, and discards engine state. Other devices see
the deletion on their next fetch. A device whose database change token has
expired would not see the deletion event; it sees `zoneNotFound` on its next
save instead, which the established-zone checkpoint turns into the same pause
rather than a silent re-upload.

When sync is off or paused, Delete iCloud Data borrows a temporary engine
created with automatic sync turned off. While it runs, the transport neither
applies what it fetches, sends records, nor persists its state: it only
deletes the zone.

### Pause reasons

`accountChanged` and `userDeletedZone` remain. `adoptionInProgress` and
`backfillFailed` are removed: a backfill is now one local transaction that
enqueues outbox rows, so it cannot be half-done in a way that needs a pause.

### Assistant change log

`ai_changelog` becomes device-local and is no longer synced. Each device keeps
the record of the assistant writes it executed, which is where MCP runs, and
Settings > Diagnostics and `get_ai_changelog` read it. The retention policy
(how long to keep entries, or off) is a local setting stored as its JSON wire
value in `device_state` under `ai_changelog_retention_policy`; an absent row
means the maximum, so choosing the maximum deletes the row. Pruning is a plain
local delete in `LorvexStore.AuditRetention`. Not syncing the log removes the
need to delete cloud copies when the policy shortens, which was the purpose of
the purge queue and the retention frontier. The payload manifests keep the
`ai_changelog` entity so the wire contract is unchanged; Core refuses to
enqueue it and skips it inbound.

### Future-record holds

A local write whose record name is occupied by a record this build cannot
understand stays in the outbox with the `future_record_hold` disposition.
When a later build understands the held record, the hold resolves by HLC
last-writer-wins, like any other conflict. There is no separate replay policy.

### Leaving the old zones

The first fetch on a device running this transport lists the private
database's zones. Every zone named `LorvexGeneration-*` is deleted with a
pending `deleteZone`. The records in those zones are copies of data that every
device also holds locally, and they include synced assistant change-log rows
that should not linger. The default-zone control records are left in place;
nothing reads them.

Devices on the new transport do not interoperate with builds on the old one.
Both of the owner's devices update together from TestFlight, and each device
re-uploads its local database into the new zone, where HLC merging converges
them.

### Import

Settings import does not quiesce the engine. When sync is live, the store runs
one best-effort sync pass first, so the importer's skip-if-present decisions
see the other devices' latest rows; the import is local and proceeds when that
pass fails. The importer then commits record by record, each in its own
transaction. SQLite transactions serialize those writes against the engine's
inbound applies, and HLC last-writer-wins settles any overlap. The store
refreshes afterwards, and the imported rows reach CloudKit through the outbox
like any other mutation.

Import rejects only with `LorvexDataImporter.BusyError`, which is thrown while
another import, factory reset, or iCloud-data deletion is running. Shipping
surfaces call `AppStore.applyDataImport` and `MobileStore.applyDataImport`,
never `LorvexDataImporter.apply` directly.

### Background on iOS

When the app leaves the foreground, it begins a `UIApplication` background
task, runs one sync pass (`BackgroundSyncFlush` in `LorvexMobileApp`), and
suspends the database when that pass ends or the task expires, whichever comes
first. If the app returns to the foreground before then, the database resumes
as usual and the late suspension is skipped.

Silent pushes are handled by the engine. The app delegate only keeps the app
awake for them, with a 22-second deadline inside Apple's silent-push budget. A
sync that the system starts while the database is suspended fails its apply
and is retried through the rule under "Engine state".

## Schema

Migration `002_retire_custom_sync_transport` makes these changes in one
transaction:

- It drops the tables that only the removed protocol used:
  `sync_cloudkit_account_binding` (the account fingerprint store covers its
  purpose), `sync_cloudkit_authority_witness`,
  `sync_cloudkit_generation_descriptor`, the five `sync_generation_snapshot_*`
  tables, `sync_cloudkit_traversal_progress`, `sync_cloudkit_traversal_witness`,
  `sync_cloudkit_incremental_cursor`, `sync_cloudkit_corrupt_record_fences`,
  `sync_authoritative_snapshot`, `sync_authoritative_snapshot_records`, and the
  six `audit_*` tables.
- It copies the active account's audit retention policy (or the unbound one
  when no account was bound) into `device_state`, unless it is the maximum.
- It rebuilds `sync_outbox` without the `authoritative_adoption` disposition,
  its session column, and the future-record resolution column, keeping every
  row id and the AUTOINCREMENT high-water. Queued `ai_changelog` rows and
  authoritative-adoption fences are deleted first.
- It rebuilds `ai_changelog` without its retention epoch and account columns,
  keeping every row and entity link, and drops
  `sync_tombstones.cloud_confirmed_at`, since tombstones are kept for the life
  of the zone.
- It deletes the checkpoint keys only the old transport wrote.

## Testing

Real CloudKit is not available to tests. The transport separates the
`CKSyncEngine` delegate from a pure event handler that takes engine events,
the outbox, and Core, and returns the decisions (records to send, pending
changes to add, pause reasons, reports). Unit tests drive the handler with
simulated events: fetched modifications, sent batches with each error class,
account changes of every type, zone deletions of every reason, apply failures,
and crash-between-steps replays. Core's apply and reconciliation tests stay as
they are. The owner verifies two-device behavior on TestFlight builds.

## Alternatives considered

- **Keep the custom transport and fix the audited defects.** The defects were
  individually fixable, but each fix to date added protocol state, and the
  protocol's complexity is the underlying cause. Rejected.
- **`NSPersistentCloudKitContainer`.** Requires Core Data as the store and its
  own record schema, and gives no control over merge semantics. Rejected; the
  HLC apply layer is the part that works.
- **`CKSyncEngine` with one CloudKit record type per entity.** Would make
  records readable in the CloudKit console but gains nothing for sync, loses
  the encrypted single-type envelope, and would need a production schema
  migration. Rejected.
