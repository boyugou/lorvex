# Unique CloudKit Zone per Sync Generation

Status: implemented finalization protocol; recovery-state update verified 2026-07-16

Date: 2026-07-14

Original design baseline: `1b9af6290`. The document now describes the implemented protocol. The
pre-implementation hazard list remains at the end as historical design evidence, not as a list of
current defects.

## Decision

Each Lorvex CloudKit sync generation gets a new, globally unique custom-zone name. A singleton
control record in the private database's default zone names the one active custom zone. A rebuild
fully prepares a new candidate zone and then changes authority with one change-tag compare-and-swap
of that control record. Old zones are retired asynchronously.

This replaces the fixed physical zone named `LorvexZone` as the generation boundary. A generation
root record remains useful as a completeness and identity witness inside each custom zone, but a
parent reference in one fixed zone is not the primary fence.

The reason is fundamental: CloudKit has no conditional custom-zone deletion and cannot atomically
compare a record in the default zone while deleting or modifying a different custom zone. With one
fixed zone, a suspended former rebuild owner can resume an already-authorized `deleteZone` request
after a takeover and delete the successor's complete generation. A parent record does not protect a
zone-level deletion. A unique zone ID makes the namespace itself the fence: a stale request can only
write to or delete the stale zone named in that request.

This is a prelaunch protocol change. There are no released users and no requirement to migrate a
production fixed-zone fleet. Development-container cleanup and reset procedures still need to be
explicit.

## Goals

- A stale device, process, lease owner, request, server change token, or cached record change tag can
  never mutate or delete the current generation.
- Automatic rebuild takeover remains safe; safety does not depend on a wall-clock lease expiring at
  exactly the right moment.
- `ready` means a complete, validated baseline exists in the named active zone.
- Ordinary writes that race a generation transition are never falsely confirmed.
- A nil-token authoritative traversal is durably bound to one account, physical local database,
  custom zone, generation, and traversal witness.
- Every crash point resumes idempotently without publishing a partial generation or losing an
  outbox row.
- Retired zones are cleaned durably and remain bounded.
- User-requested cloud-data deletion covers every Lorvex generation zone and cannot be undone by a
  stale device.

## Non-goals

- This protocol does not replace HLC last-writer-wins inside one ready generation.
- It does not make CloudKit operations and SQLite transactions cross-system atomic.
- It does not promise that silent push notifications are delivered immediately or exactly once.
- It does not use a growing zone set as history or backup. Retired zones are garbage, not revisions.
- It does not make Apple and Tauri schemas identical.

## Verified CloudKit constraints

The design relies on the following Apple-documented behavior:

- Custom-zone names are unique within the database, contain no more than 255 ASCII characters, and
  do not begin with an underscore. A UUID is an explicitly documented way to create a unique name.
  See [CKRecordZone init(zoneName:)](https://developer.apple.com/documentation/cloudkit/ckrecordzone/init%28zonename%3A%29).
- Custom zones are available in the private database and act as independent units. Records and
  references do not cross zone boundaries. See
  [CKRecordZone](https://developer.apple.com/documentation/cloudkit/ckrecordzone).
- A database subscription observes changes in custom zones, but explicitly excludes the private
  database's default zone. See
  [CKDatabaseSubscription](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription).
- Query subscriptions are supported in private databases and can be scoped to a zone. The
  implementation should add a query subscription for the control-record type in the default zone
  and prove it in the development environment. See
  [Remote Records](https://developer.apple.com/documentation/cloudkit/remote-records) and
  [CKQuerySubscription.zoneID](https://developer.apple.com/documentation/cloudkit/ckquerysubscription/zoneid).
- A record-zone change token is a point in one zone's history. A nil token asks CloudKit to return
  all changes for that zone, in pages, until `moreComing` is false. See
  [CKFetchRecordZoneChangesOperation](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation).
- The default zone does not support custom-zone capabilities such as atomic multi-record saves or
  record-zone change traversal. The control protocol must therefore use one singleton record for
  every state transition that must be atomic. See
  [CKRecordZone.default()](https://developer.apple.com/documentation/cloudkit/ckrecordzone/default%28%29).
- A record parent must be in the same zone and must already exist or be part of the same save. Parent
  references cannot compare against the default-zone control record. See
  [CKRecord.parent](https://developer.apple.com/documentation/cloudkit/ckrecord/parent).
- The private database can enumerate its record zones, which is useful for deletion and orphan
  cleanup. See [CKDatabase](https://developer.apple.com/documentation/cloudkit/ckdatabase).

Apple does not document a safe unbounded custom-zone count. Lorvex must keep the number of active,
candidate, and retired zones explicitly bounded even though zones are cheap enough for a short
rebuild transition.

## Identities and records

### Generation descriptor

All transport operations carry an immutable descriptor:

```text
GenerationDescriptor
  accountIdentifier
  epoch                 monotonically increasing Int64
  generationID          opaque random identifier; prevents ABA
  zoneName              unique custom-zone name
  rootRecordName        fixed within the unique zone
  readyWitness          opaque candidate-completion witness
```

Equality is exact across every field. Comparing only `epoch`, only `zoneName`, or only the record's
CloudKit change tag is insufficient.

The zone name should be short, ASCII, non-sensitive, and prefix-identifiable, for example:

```text
LorvexData-e42-6f8a20c1b59e4c13a04d59ed289d3d43
```

The epoch supports inactivity/recovery policy and diagnostics. The random generation ID and unique
zone name provide identity and ABA resistance.

### Default-zone control record

Keep one fixed record name in the private default zone. The existing `LorvexZoneEpoch` type may be
evolved rather than introducing a second authority. Its logical shape is:

```text
ZoneControl
  protocolVersion
  state                  ready | rebuilding | cloudDataDeleted
  epoch
  generationID
  activeZoneName         nullable before first ready generation
  activeReadyWitness     nullable before first ready generation
  candidateZoneName      present only while rebuilding
  candidateGenerationID  present only while rebuilding
  rebuildLeaseID         present only while rebuilding
  rebuildOwnerID         present only while rebuilding
  rebuildPhase           claimed | preparing | sealing | publishing
  leaseHeartbeatAt       server-observed liveness hint, never a safety fence
  retiredZoneNames       bounded list
  deletionGeneration     monotonic user-wipe witness
```

All fields that participate in one transition live in this one record. Every mutation uses
`.ifServerRecordUnchanged`, validates the per-record result, refetches after a change-tag conflict,
and checks the complete decoded state. The default zone cannot provide atomicity across a separate
retirement record, so the retirement obligation belongs in the singleton itself.

`retiredZoneNames` has a hard protocol cap. A value such as four is enough for active + candidate
turnover while keeping the control record small. A new rebuild may not start when adding its
possible retiree would exceed the cap; cleanup runs first. Never silently drop the oldest name.

### Candidate root

Every generation zone contains one fixed-name `LorvexGenerationRoot` record stamped with:

```text
protocolVersion
epoch
generationID
zoneName
rebuildLeaseID
createdByDatabaseInstanceID
```

The zone ID already provides the hard generation fence. The root is an explicit proof that the
zone was initialized by the matching control-state transition and gives snapshot/rebuild validation
a required record. It must be created before any `LorvexEntity` baseline records.

Using the root as the parent of every entity is optional defense in depth. It is not required for
cross-generation isolation once zone names are unique. If parent references are adopted, the root
must never be deleted while the zone is active.

### Candidate completion seal

Before publishing a candidate, create a `LorvexGenerationSeal` record in that candidate zone. It
contains only protocol metadata:

```text
generationID
epoch
rebuildLeaseID
sealID
expectedEntityCount
expectedManifestDigest
sourceLocalChangeSequence
```

The manifest digest is over a canonical, sorted sequence of record identity and envelope digest,
not over iteration order. At minimum include `recordName`, operation, HLC version, payload schema,
and canonical payload digest. The seal is not a substitute for traversal: the candidate must be
read back from a nil token and independently produce the same count and digest.

The control record's `activeReadyWitness` is the accepted seal ID or a digest that identifies it.

### Per-traversal witness

An authoritative nil-token adoption uses a separate `LorvexTraversalWitness` record whose record
name includes the local snapshot session token. It contains:

```text
generationID
zoneName
sessionToken
createdByDatabaseInstanceID
```

The intent and planned witness identity are durable in SQLite before the witness save. The witness
is then saved into the exact active zone under the ordinary exact-descriptor pre/post fence. A
snapshot cannot finalize until its nil-token traversal has observed this exact witness and reached a
terminal change token. This proves the traversal is not an accidentally resumed old cursor and that
it traversed the intended physical generation through a known server-side event.

The witness does not freeze concurrent ordinary writes. It proves a frontier. Changes after the
terminal token remain ordinary incremental input and must never be overwritten merely because they
were absent at that frontier.

## State machine

### Bootstrap

1. Account and consent gates pass.
2. Read the control record.
3. If no valid control record exists, CAS-create `rebuilding` with epoch 1, a random generation ID,
   a unique candidate-zone name, and a rebuild lease.
4. Create the candidate zone and its root.
5. Backfill, seal, validate, and publish it using the same path as every later rebuild.
6. There is no implicit fixed `LorvexZone` creation before the control record exists.

An existing but undecodable control record is an error, not equivalent to absence.

### Ready ordinary operation

1. Read and validate `ready` descriptor `D` from the default-zone control record.
2. Verify the expected generation root when entering a descriptor not previously verified in this
   process. A missing or mismatched root is a recovery condition, never permission to create it from
   an ordinary cycle.
3. Load the checkpoint for `(account, D.zoneName, localDatabaseInstanceID, D.generationID)`.
4. Push with the exact-descriptor fence described below.
5. Pull from `D.zoneName` with the same exact-descriptor fence.
6. Save only a checkpoint that carries `D.generationID` and `D.readyWitness`.

Every lifecycle trigger and every notification re-reads the control record. A notification is a
wake-up hint, not an instruction to fetch a particular zone.

### Claim rebuild

The current `ready` control record is change-tag-CASed to:

```text
rebuilding
  previous active descriptor remains named
  new epoch
  new generation ID
  new unique candidate zone
  new lease ID and owner
  phase = claimed
```

From the successful CAS onward, ordinary push and pull across the fleet stop. User edits may remain
available locally and enqueue durable outbox work, but only the exact rebuild lease may write the
candidate.

If the previous active zone still exists, the claimant seals and drains it after publishing the
barrier. A confirmed ordinary write that completed before the `rebuilding` CAS is therefore included
in the rebuild source. An ordinary write that lands after the barrier cannot be confirmed and remains
pending on its source device for the new active zone.

If the old zone is missing or unreadable because the encrypted key was reset, the candidate is built
from recoverable local state. Other devices replay still-pending and policy-permitted local state
after cutover. No protocol can recover the only copy of data from an unavailable old zone and a lost
device; the state machine must not pretend otherwise.

### Build and validate candidate

1. Re-read and validate the exact rebuilding lease immediately before every external mutation.
2. Create the candidate zone.
3. Create and read back the matching generation root.
4. Enqueue a full local backfill for the candidate. A new or replacement lease always re-enqueues a
   complete baseline; it does not trust rows confirmed into an abandoned candidate.
5. Drain outbox chunks under the rebuild descriptor's pre/post fence.
6. When unresolved outbound work reaches zero, capture a canonical local manifest and local change
   sequence.
7. Write the generation seal.
8. Traverse the candidate from a nil token, require the root and seal, reject unknown/corrupt
   Lorvex records, and compare the independently computed manifest.
9. Re-read the local change sequence. If it changed before the seal frontier, repeat the backfill and
   seal. A later edit may remain pending for normal post-cutover sync.
10. Re-read and validate the exact remote lease before attempting publication.

`unresolvedOutboundCount == 0` alone is not a completeness proof. It proves only that the local
queue currently has no unresolved row; it cannot prove that the queue originally enumerated every
syncable entity or that every successful result targeted this candidate.

### Publish ready

Use the fetched control record's change tag to CAS exactly:

```text
rebuilding(exact lease, exact candidate)
  -> ready(active = candidate descriptor,
           activeReadyWitness = candidate seal,
           retiredZoneNames += previous active zone)
```

Publishing is the only operation that makes candidate content authoritative. A remote-success/local-
failure retry recognizes the exact ready witness and completes local enrollment without allocating
another generation.

The previous active zone is appended to the bounded retirement list in the same singleton-record
CAS. There is no crash window in which authority changes but the cleanup obligation was never
recorded.

After the CAS, write a notification beacon in the new active custom zone as a liveness fallback. The
default-zone query subscription is the primary metadata wake-up; the existing database subscription
continues to cover all current and future custom zones. Notification coalescing means normal
lifecycle/background triggers remain necessary.

### Takeover

Lease age is a liveness hint. It never authorizes a new owner to reuse the old candidate.

After the takeover threshold:

1. Fetch the current `rebuilding` control record.
2. Choose a new epoch, random generation ID, unique candidate zone, lease ID, and owner.
3. CAS the singleton to the new rebuilding descriptor and append the old candidate to the retirement
   list.
4. Build the new candidate from scratch.

The old owner can resume only against its old zone. Its pre/post descriptor checks fail, it cannot
publish ready, and an already-issued zone deletion still names only the old zone.

### Retirement

1. Fetch the control record and choose one listed retired zone.
2. Refuse cleanup if the name equals the current active or candidate zone.
3. Delete exactly that custom zone. Deletion is idempotent; `zoneNotFound` is success.
4. Refetch the control record and CAS-remove the name only if it remains retired and still is neither
   active nor candidate.
5. Delete that zone's local checkpoint and zone-qualified system-field cache entries.

If the zone delete succeeds but the CAS removal fails, the next cleanup repeats an idempotent delete
and then retries the CAS. If the process crashes before deletion, the name remains durable.

Prefix enumeration is a repair tool for development cleanup and leaked orphan detection, not a
replacement for the retirement list. An orphan zone is deletable only when it has a Lorvex root,
matches the exact Lorvex prefix, is absent from active/candidate state, and passes a conservative age
or explicit reset policy.

### User cloud-data deletion

The durable user-deletion pause is written before any zone deletion, as today. Under the new model:

1. CAS the control record to `cloudDataDeleted` with an advanced deletion generation and no active or
   candidate authority.
2. Include the former active and candidate zones in the durable retirement list in that same record.
3. Enumerate all custom zones and select only zones that both use the exact Lorvex prefix and contain
   a matching Lorvex generation root.
4. Delete every selected generation zone, including durable retirees and verified orphans.
5. Keep the non-content `cloudDataDeleted` control record so stale devices cannot bootstrap and
   republish without explicit consent.
6. Re-enable performs a new bootstrap generation after the user confirms it.

Never delete unrelated custom zones in the user's private database. Never delete the control record
as the final step: absence would be ambiguous with first use and could allow silent recreation.

## Exact-descriptor request and confirmation fence

Account fencing alone is insufficient. Every CloudKit request that reads or mutates generation data
is bound to the full generation descriptor.

### Ordinary outbound push

For descriptor `D`:

1. Build every `CKRecord.ID` in `D.zoneName`.
2. Immediately before each `modifyRecords` request, read the control record and require exact
   `ready(D)`.
3. Submit the request.
4. Immediately after the result returns, read the control record again and require exact `ready(D)`.
5. Only then may the coordinator:
   - apply a server-wins envelope;
   - defer a forward-compatible server record;
   - cache returned system fields;
   - mark an outbox row synced; or
   - spend a per-row retry budget based on a generation-specific result.
6. If the post-check fails, classify the result as a generation-boundary ambiguity. Do not confirm,
   fail, apply, or cache it. Leave the outbox row pending for the new active descriptor.

The same check surrounds every `limitExceeded` subdivision request and every local-wins conflict
re-save. A local-wins payload from generation A must never be restamped onto a server record in
generation B.

A push that both saves and passes its post-check before the rebuild claim is a valid old-generation
write. The claimant's post-claim old-zone seal captures it. A push that completes after the claim
cannot pass the post-check and remains pending for replay.

### Rebuild outbound push

Replace `ready(D)` with exact
`rebuilding(leaseID, ownerID, generationID, candidateZone)`. A successful candidate save may be
locally confirmed only while that exact lease remains current. If the lease is later replaced before
publication, the replacement claim resets local rebuild progress and re-enqueues a complete baseline;
confirmed rows in the abandoned candidate are not treated as globally durable.

### Inbound fetch

1. Fetch only from the zone in the captured descriptor.
2. After the page returns and before staging/applying any record, require the same exact remote state.
3. Validate `batch.zoneName`, checkpoint generation, root, and any snapshot witness.
4. Apply/stage records.
5. Apply the page effects and successor token in one managed-SQLite transaction after the exact
   account/generation validation. There is no external cursor file or second commit point.
6. On mismatch, discard the page and token. Start from the new active descriptor; never combine pages
   from two generations.

## Local transport-state changes

### Traversal cursors

The managed SQLite database is the sole cursor authority. Traversal progress, the account/zone/
generation/ready-witness boundary, witness identity, page index and continuation token are stored
with the database they describe. Applying a page and advancing its token is one transaction. The
transport reconstructs a short-lived `CloudSyncChangeCursor` immediately before a CloudKit request;
it is never written to a sidecar file.

A new generation begins from a nil token. Invalid/expired cursors reset only the exact active
traversal in SQLite, preserving the same witness identity for a crash-safe nil-token retry. Because
the cursor cannot outlive or be restored independently of the database, no external clear-generation
CAS or cross-container backup ordering is required.

### CKRecord system fields

The current cache is keyed only by `recordName`. The same Lorvex entity record name appears in every
generation, so this becomes unsafe with multiple zones. Key and persist the cache by at least:

```text
accountIdentifier | zoneName | recordName
```

When hydrating an archived `CKRecord`, verify its decoded `recordID.zoneID` equals the outgoing
record's zone before restamping. A mismatch is a cache miss and the bad entry is removed. Cache writes
occur only after the post-request exact-descriptor check.

### Zone-ensured state

A boolean `zone ensured` marker cannot describe dynamic zones. Either remove the marker and fetch or
idempotently save the exact candidate/active zone as required, or key the marker by account and zone
name. A marker for one generation must never suppress creation/validation of another.

### Outbox

Domain outbox rows should remain zone-agnostic so pending local work naturally targets the current
active zone at push time. Transport confirmation, however, is generation-bound. Do not permanently
stamp a domain mutation with the zone that happened to be active when the local edit occurred.

Rebuild progress is different: it must persist the exact lease, generation, candidate zone, phase,
and whether a complete baseline must be re-enqueued.

## Authoritative snapshot and durable traversal handoff

The current target must guarantee more than “the last page said `moreComing == false`.”

### Session binding

Persist these fields in the SQLite authoritative-snapshot session before clearing a checkpoint or
writing a witness:

```text
sessionToken
accountIdentifier
localDatabaseInstanceID
generationID
zoneName
readyWitness
rootRecordName
traversalWitnessRecordName
phase
terminalServerChangeTokenData
```

At start and after every fetched page, refetch the control record and require the same exact ready
descriptor. A generation change restarts the session from preparation against the new active zone; it
never finalizes the old staged inventory while enrolling the new epoch.

### Phases

Use an explicit durable handoff:

```text
preparing -> ready -> pulling -> complete
```

- `preparing`: quarantine pre-session outbound work and durably mint the snapshot/witness identity.
- `ready`: the exact traversal witness has been published; recovery republishes it idempotently.
- `pulling`: every staged page and continuation is bound to the session and generation in SQLite.
- `complete`: the terminal inventory reconciliation, terminal token/baseline witness and release of
  snapshot-local state commit in one SQLite transaction.

There is no `localFinalizedCheckpointPending` phase because there is no external checkpoint. A crash
before the terminal transaction repeats the exact session; a crash after it observes the completed
baseline. The harmless remote traversal witness is deleted before the next traversal starts, so a
fallible cleanup can never erase an already-committed inbound report.

### Absence semantics

Remote absence at terminal token `T` is authoritative for this over-window device. Reconcile a local
row absent at `T` locally, but do not mint and enqueue a fresh, dominating CloudKit delete merely from
that absence. A peer may create or update that record after `T`; a synthetic high-HLC delete would
turn a local snapshot decision into a later fleet-wide overwrite.

Use a dedicated authoritative local-prune path that preserves relational invariants without creating
an outbound tombstone. Later remote changes after `T` can then apply normally. Generation policy,
not a synthetic delete from each adopting device, governs stale-device re-entry.

If typed replay legitimately creates repair/convergence outbox work, keep it fenced until the terminal
checkpoint is durable and run an inbound-first catch-up from that token before ordinary push order
resumes.

### Why the witness is necessary but not snapshot isolation

Observing the exact per-session witness proves:

- the traversal used the intended custom zone;
- it began early enough to observe a server event created for this session;
- the staged inventory and terminal token belong to one durable session;
- a delete/recreate or zone switch cannot silently masquerade as continuation.

It does not prevent a peer from writing after the terminal token. Those later writes belong to the
next incremental pull. The no-synthetic-absence-delete rule and inbound-first handoff prevent the
snapshot from overwriting them.

## API refactor

Introduce an explicit context rather than reconstructing a fixed zone in factories and actors:

```swift
struct CloudSyncGenerationDescriptor: Sendable, Equatable {
  let accountIdentifier: String
  let epoch: Int
  let generationID: String
  let zoneID: CKRecordZone.ID
  let rootRecordName: String
  let readyWitness: String
}

enum CloudSyncZoneControlState: Sendable, Equatable {
  case ready(CloudSyncGenerationDescriptor, retiredZones: [String])
  case rebuilding(CloudSyncRebuildDescriptor, retiredZones: [String])
  case cloudDataDeleted(CloudSyncDeletionDescriptor, retiredZones: [String])
}
```

Recommended transport seams:

```text
ZoneControlAuthority
  readState(accountBoundary)
  bootstrapClaim(...)
  claimRebuild(expectedReady,...)
  takeover(expectedRebuilding,...)
  publishReady(expectedLease,validatedSeal,...)
  removeRetiredZone(expectedState,zoneName)
  markCloudDataDeleted(...)

RecordPusher
  ensureZone(context, exactStateGuard)
  saveRoot(context, exactLeaseGuard)
  push(records, context, exactStateGuard)
  deleteRetiredZone(zoneID, controlGuard)
  clearSystemFields(account,zone)

RemoteChangeFetcher
  fetchChanges(after, context)

Coordinator
  captures one immutable context per operation
  owns pre/post guards and confirm/apply ordering
```

`CloudKitRecordPusher`, `CloudKitRemoteChangeFetcher`, and
`CloudSyncEngineCoordinator` currently retain one fixed `zoneID`. They should accept a descriptor or
zone ID per operation. `CloudSyncFactory` and macOS `AppCoreFactory` should build account/container
transport dependencies, not decide the active generation at construction time.

Keep the control authority separate from entity record push logic. Default-zone CAS rules, active
pointer transitions, and retirement are one concern; HLC entity conflict resolution is another.

## Crash and race proof sketch

| Interruption or race | Durable state | Safe recovery |
| --- | --- | --- |
| Crash before rebuild claim CAS | Old `ready` remains | No rebuild exists; retry claim |
| Crash after claim, before candidate create | `rebuilding` names candidate | Exact owner or takeover creates a candidate; ordinary traffic remains paused |
| Two simultaneous claims | One control-record change tag wins | Loser refetches and observes rebuilding |
| Old owner resumes after takeover | Requests still name old candidate | It cannot touch new candidate/active; exact-state post-check fails |
| Old owner resumes an issued zone delete | Delete names old unique zone | Current active zone has a different ID and survives |
| Crash during candidate push | Lease + local obligation survive | Retry idempotently; unconfirmed rows remain or full baseline is re-enqueued |
| Lease changes during candidate request | Result belongs to old candidate | Post-check prevents confirm/cache/apply; replacement lease runs full backfill |
| Crash after candidate validation, before ready CAS | Control remains rebuilding | Revalidate seal and retry exact CAS |
| Ready CAS succeeds, local enrollment fails | Control has exact ready witness | Retry recognizes witness and completes locally without another generation |
| Crash after ready CAS, before old-zone delete | Old zone is in same control record's retired list | Any device resumes cleanup |
| Old-zone delete succeeds, CAS cleanup fails | Name remains retired | Repeat idempotent delete, then remove name |
| Ordinary push begins before rebuild claim and returns after it | Request targets old zone | Post-check fails; row remains pending for new active zone |
| Ordinary push completes and confirms before claim | Old zone contains the valid write | Claimant's post-claim old-zone seal/traversal captures it |
| Generation changes between snapshot pages | Session descriptor differs | Discard response/staging and restart nil traversal in new zone |
| Generation changes after terminal fetch but before finalize | Terminal descriptor check differs | Do not finalize; restart against new active zone |
| Crash after snapshot local finalize, before token file save | SQLite phase is checkpoint-pending and push fence remains | Save stored terminal token first, then release |
| Server write occurs after snapshot terminal token | It is after the adopted frontier | Next incremental pull applies it; no synthetic absence delete overwrites it |
| Default-zone ready notification is missed | State is still durable | Lifecycle/background polling rereads control; custom-zone wake beacon is a liveness fallback |
| User deletes cloud data while a cycle is in flight | `cloudDataDeleted` is the new control authority | Pre/post descriptor fence prevents confirmation; stale requests target retired zones only |

## Required automated test matrix

### Control-record state and CAS

- Bootstrap from a genuinely absent control record creates exactly one candidate generation.
- An existing undecodable control record fails closed and is never treated as first use.
- Two bootstrap or rebuild claims produce one winner.
- Epoch never regresses and overflow fails closed.
- A ready-to-rebuilding CAS preserves the old active descriptor.
- A stale lease cannot publish ready.
- A remote ready success followed by local failure resumes through the exact ready witness.
- Takeover always allocates a new generation and candidate zone.
- Takeover appends the abandoned candidate to the bounded retirement list.
- Retirement-list cap blocks a new transition rather than dropping cleanup state.
- `cloudDataDeleted` cannot be overwritten by automatic bootstrap or rebuild.

### Ordinary outbound fences

- State changes before a request: no CloudKit mutation occurs.
- State changes while a request is in flight: returned successes do not confirm outbox rows.
- State changes between a subdivided batch's head and tail: the tail is not sent and the head is not
  falsely confirmed across the boundary.
- State changes before a local-wins re-save: no restamp/save occurs in the successor generation.
- A server-wins result from an old zone is neither applied nor cached after cutover.
- Generation-boundary ambiguity does not spend retry budget.
- A row left pending by the old-zone post-check is later sent to and confirmed in the new active zone.

### Inbound and checkpoint fences

- A fetched old-zone page is discarded when active state changes before apply.
- A state change after apply but before checkpoint save prevents the old token from becoming active.
- A new generation always starts with a nil token even when an old-zone checkpoint exists.
- Checkpoints with the right zone but wrong generation/witness/database instance are rejected.
- In-flight old-zone checkpoint saves cannot overwrite the new-zone file.
- Token-expired and invalid-archive recovery restarts the exact snapshot session and witness.

### System-fields cache

- Identical record names in two zones use distinct cache entries.
- An archived record whose decoded zone differs from the outgoing zone is rejected and removed.
- A post-request generation mismatch prevents cache insertion.
- Retirement deletes only the retired zone's cache namespace.

### Rebuild and candidate completeness

- Candidate root is required and must match control lease/generation.
- Ordinary cycles hard-stop while rebuilding; the exact rebuild transport still works.
- Post-claim old-active traversal includes a write confirmed immediately before the claim.
- A write landing after the claim cannot be confirmed in the old generation and replays later.
- `unresolvedOutboundCount == 0` with a deliberately omitted entity fails manifest validation.
- Missing, corrupt, wrong-generation, or physically deleted root/seal fails publication.
- Unknown or corrupt Lorvex entity records fail candidate validation.
- Manifest count/digest mismatch fails publication.
- A local change-sequence move during sealing repeats baseline validation.
- Lease takeover during each push chunk, seal write, traversal page, and ready CAS is safe.
- A replacement lease re-enqueues the complete baseline even if the old candidate locally confirmed
  every row.

### Stale-owner zone isolation

- Owner A claims candidate A; owner B takes over with candidate B and publishes; owner A then resumes
  every operation, including zone delete. Active B remains byte-for-byte unchanged.
- A stale retirement worker refuses to delete a zone that has become active or candidate.
- A stale entity save can affect only the zone ID captured in its request.
- Fixed record names reused across generations do not collide because their zone IDs differ.

### Authoritative traversal witness

- Session persists exact account, DB instance, generation, zone, ready witness, root, and traversal
  witness.
- The initial fetch is nil-token even when an unrelated prior checkpoint exists.
- A terminal page without the per-session witness cannot finalize.
- A witness from another session/generation cannot satisfy the session.
- A physical witness deletion during traversal prevents false completion.
- Generation switches between pages and after the terminal response restart the traversal.
- Unknown/corrupt records leave session and outbox fence durable.
- Terminal token and staged inventory survive relaunch.
- Injected failure at every handoff step proves ordinary push remains blocked until the terminal
  checkpoint is durable.
- A server upsert after terminal token `T` is applied later and is not overwritten by a synthetic
  snapshot-absence tombstone.
- Legitimate replay repairs run only after inbound-first catch-up from `T`.

### Subscription and liveness

- Registration installs the existing custom-zone database subscription and the default-zone control
  query subscription with stable IDs.
- Per-subscription result failures do not latch false success.
- A control-record state change triggers the coordinator in a development CloudKit integration test.
- A custom-zone notification causes a control reread rather than blindly fetching the notifying zone.
- A ready transition followed by a missed notification is recovered on next foreground/background
  lifecycle trigger.

### Retirement and user deletion

- Ready publication and old-zone retirement obligation are one control-record CAS.
- Cleanup is idempotent across delete success/CAS failure and relaunch.
- Cleanup never deletes unrelated custom zones or the active/candidate zone.
- Verified prefix orphans are handled conservatively and a malformed lookalike is preserved.
- User deletion records the durable deletion state before remote deletion.
- User deletion covers active, candidate, listed retirees, and verified Lorvex orphans.
- A stale device cannot bootstrap after deletion without explicit re-enable.
- Re-enable creates an entirely new generation and unique zone.
- Account switching during enumeration, delete, CAS, or re-enable fails closed.

### Real CloudKit release probes

Unit fakes cannot prove CloudKit ordering, subscription delivery, encrypted-key-reset behavior, or
server token invalidation. Before production promotion, run a development-container matrix with at
least two physical devices or one device plus a separately installed Mac build:

- concurrent ordinary edits followed by rebuild;
- suspension of the old owner during candidate creation, takeover, publication, then old-owner
  resume;
- delete/recreate and encrypted-data-key-reset recovery;
- default-zone metadata notification and custom-zone wake behavior;
- multi-page nil traversal with concurrent writes;
- user cloud-data deletion while another device is offline, then its return;
- account switch during push, pull, candidate build, retirement, and deletion;
- repeated rebuilds proving retired-zone count remains bounded.

Save control records, zone listings, logs, and final cross-device entity manifests as release
evidence. A green unit suite alone is not a production CloudKit proof.

## Pre-implementation hazards closed by this design

These statements describe the shared working tree observed while the design was written. They are
retained as historical rationale; all items below are closed in the implemented protocol and are not
current findings. Line numbers have intentionally not been refreshed.

- `CloudSyncEngineCoordinator+ZoneEpoch.swift`: a locally persisted rebuild claim is returned without
  first proving that the same lease is still current remotely. A resumed owner can therefore continue
  destructive work after takeover.
- `CloudSyncEngineCoordinator+ZoneEpoch.swift`: `.recreateZone` calls fixed-zone deletion before a
  same-operation remote lease fence can exist.
- `CloudSyncRecordPushing.swift`: `deleteZone` names one fixed zone and has only an account guard;
  CloudKit exposes no generation-conditioned zone delete.
- `CloudSyncEngineCoordinator.swift`: the fleet rebuilding state is read once before outbound work;
  successful results are later confirmed without an exact generation post-check.
- `CloudSyncEngineCoordinator+Outbound.swift`: `markOutboundSynced` is based on push results without a
  generation descriptor revalidation.
- `CloudSyncRecordPushing.swift`: conflict re-save restamps a local payload onto the fetched server
  record without a generation-first rejection.
- `AuthoritativeSnapshot.swift`: the durable session currently binds account and zone name but not an
  exact generation/root/ready witness.
- `CloudSyncEngineCoordinator.swift`: terminal snapshot finalization reads the live epoch only at the
  end, so a traversal of generation A can otherwise enroll generation B.
- `AuthoritativeSnapshot.swift`: local rows absent remotely currently receive fresh dominating delete
  envelopes and outbound rows; this can overwrite a server write created after the terminal snapshot
  token.
- `CloudSyncEngineCoordinator.swift`: local snapshot finalization clears the session before the
  external checkpoint file is saved, leaving a crash window in which reconciliation writes can push
  without the terminal cursor.
- `CloudSyncRecordSystemFieldsStore.swift`: the cache is keyed only by record name.
- `CloudSyncFactory.swift`, `CloudSyncRecordPushing.swift`, `CloudSyncRemoteChangeFetcher.swift`, and
  `CloudSyncEngineCoordinator.swift`: the transport objects capture a fixed zone at initialization.
- `CloudSyncSubscriptionManager.swift`: only a database subscription exists, while Apple documents
  that database subscriptions exclude the private default zone that carries generation state.
- `CloudSyncEngineCoordinator+CloudDataDeletion.swift`: deletion currently targets one fixed zone;
  dynamic generations require durable all-generation deletion and orphan-safe enumeration.

## Implementation order

1. Freeze the state model and CloudKit schema fields; add pure codec/state-transition tests.
2. Add the default-zone control query subscription and prove it against the development container.
3. Introduce generation descriptor/context APIs without changing behavior.
4. Make checkpoint, zone-ensured state, and system-fields cache generation-aware.
5. Implement unique-zone bootstrap, candidate root, and bounded retirement.
6. Add ordinary outbound/inbound exact-descriptor pre/post fences before enabling takeover.
7. Implement candidate seal, manifest validation, and new-candidate takeover.
8. Implement authoritative traversal witness and crash-durable terminal checkpoint handoff.
9. Replace synthetic snapshot-absence outbound deletes with authoritative local prune semantics.
10. Expand user cloud-data deletion to all verified Lorvex zones.
11. Run the complete unit/integration matrix and the real multi-device CloudKit release probes.
12. Only after the evidence is saved, promote the CloudKit schema and treat this protocol as frozen.

Do not ship an intermediate state that combines dynamic zones with a record-name-only system-fields
cache, or fixed-zone destructive takeover with a time lease. Those are not harmless partial steps;
they preserve the exact cross-generation hazards this design is intended to remove.
