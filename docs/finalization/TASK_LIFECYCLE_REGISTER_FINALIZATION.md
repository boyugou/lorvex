# Task Lifecycle Register Finalization

Status: delivered pre-freeze schema/sync checkpoint. The independent import-
operation drain/gate item remains tracked in `FINDINGS_BACKLOG.md`; it does not
reopen this task lifecycle model.

## Confirmed failure

`tasks.version` currently orders the complete row. A peer that edits ordinary
content from a stale open snapshot can therefore carry `status = open` at a
newer transport HLC, overwrite a completed parent, and leave its already-created
successor actionable. Local completion and successor creation are transactional,
but they are separate CloudKit records and inbound task apply does not run the
local reopen cascade.

The same root cause lets ordinary content restore stale recurrence or Trash
state. A post-freeze compatibility patch would have to preserve those semantics,
so the split belongs in the prelaunch schema.

## Frozen task registers

The task row remains one SQLite row and one CloudKit record. `version` becomes
only the transport/delete high-water mark. Four independently ordered registers
live inside the aggregate:

| Register | Clock | Owned fields |
| --- | --- | --- |
| Content | `content_version` | title, body, raw input, AI notes, list, priority |
| Schedule | `schedule_version` | due/planned/available dates, estimate, deferral metadata, recurrence rule, EXDATE set, recurrence lineage and generated occurrence identity |
| Lifecycle | `lifecycle_version` | status, completed timestamp, rollover state and selected successor identity |
| Archive | `archive_version` | Trash timestamp |

`created_at` is immutable history and joins by the earliest canonical timestamp.
`updated_at` follows the winning transport HLC. Every register clock is a
canonical HLC no greater than `version`. Equal-clock/different-byte collisions
use a deterministic canonical-byte winner and are re-authored at a strict HLC
successor, matching the established calendar grouped-register contract.

An inbound envelope may be older at the transport level and still contain a
winning register. It must reach the task applier. If the merged row differs from
the triggering payload, the host re-emits the canonical joined snapshot.

## Recurrence rollover state

The lifecycle register carries:

- `none`: no successor decision has been made;
- `authorized`: the terminal occurrence authorizes exactly the recorded direct
  successor;
- `revoked`: an explicit reopen revoked the recorded successor; the ID remains
  as a durable negative fact;
- `ended`: the recurrence exhausted or the user stopped the series, with no
  authorized successor.

`authorized` requires a terminal parent and a successor ID. `revoked` retains a
successor ID and permits the parent to be open, in progress, or someday.
`none` and `ended` have no successor ID. Ordinary non-recurring lifecycle writes
use `none`.

The successor stores `spawned_from_version`, equal to the authorizing parent's
`lifecycle_version`. `spawned_from` and `spawned_from_version` are both null or
both present. A direct successor ID is deterministic UUIDv8 over the parent task
ID and recurrence group ID. Concurrent completions therefore address the same
row; the larger lifecycle HLC chooses both the parent decision and the
successor's generated schedule/lifecycle state.

`recurrence_instance_key` is exactly
`recurrence_group_id + ":" + canonical_occurrence_date` whenever present. Both
the inbound trust boundary and SQLite enforce that shape. A distinct task ID
claiming an existing key is invalid input and fails closed without merging rows,
moving children, writing a tombstone, or creating an entity redirect.

Every nonterminal status (`open`, `in_progress`, and `someday`) counts as an
actionable successor for the one-chain invariant.

## Local transitions

- Complete or skip-cancel computes the successor before finalizing the parent.
  If another occurrence exists, it writes `authorized(successor)` and creates or
  revives that deterministic successor with the same lifecycle/schedule HLC. If
  the rule is exhausted, it writes `ended`.
- Reopen is permitted only at a rewindable chain tip. It writes
  `revoked(successor)` and cancels that successor in the same transaction.
  Reopening may not silently fork an already-advanced descendant chain.
- Re-complete reuses the same successor identity, revives a cancelled successor,
  refreshes generated schedule fields, and preserves ordinary user-edited
  content.
- Stop-series writes `ended` and clears recurrence scheduling at the same HLC.
  Recurrence lifecycle transitions advance the schedule register even when its
  values are unchanged, so a concurrent lower-HLC stop/continue decision cannot
  win only half of the aggregate.

## Inbound reconciliation

- A successor whose authorizing generation is ahead of the live parent is held
  in the pending inbox until the parent register arrives.
- A successor whose generation or identity is contradicted by a newer parent
  decision is made nonterminally impossible and re-emitted through the normal
  fresh-HLC convergence funnel.
- A parent may arrive before its authorized successor; that temporary absence
  is legal. Once all records are present there is exactly one nonterminal chain
  tip.
- Future-schema task snapshots are held when a local task already exists because
  an unknown field cannot safely be assigned to a known register.

## Delete and restore

- Archiving never changes recurrence lineage.
- Permanently deleting a historical parent while its successor survives first
  re-roots the successor by clearing `spawned_from` and
  `spawned_from_version`; recurrence group and deterministic identity remain.
- Permanently deleting the currently authorized successor first advances the
  predecessor to `ended`; no live parent may permanently point at a missing
  child.
- Apple-native export/import preserves register clocks, rollover state,
  successor identity, and lineage. Import validates the whole graph inside one
  write transaction before materialization and must not replay live completion
  workflows over already materialized history.
- The portable AI-mediated export may remain intentionally lossy, but it must be
  described as migration data rather than a faithful Apple restore artifact.

## Apple-native clock-preserving import contract

The human backup carries two task representations: portable `tasks` and the
versioned `nativeTaskGraph`. Their task-ID multisets must agree before native
materialization is attempted; a mismatch rejects the task category rather than silently
ignoring one representation.

Lists and tags import first. The concrete Swift core then opens one
`BEGIN IMMEDIATE`, proves that the complete task domain is fresh, and runs the
same `NativeTaskGraphValidator` used by export against the list/tag roots visible
inside that transaction. Freshness includes canonical task/child/edge tables,
task tombstones, outbox/pending/quarantine/payload-shadow state,
and active generation/authoritative snapshot staging. A missing referenced
list/tag root selects the existing portable importer; any other native graph
failure aborts with no task, outbox, or audit rows committed.

A validated graph is inserted directly. Native materialization never calls live
task, completion, cancellation, recurrence, reminder, or dependency workflows:
doing so would mint replacement clocks or reinterpret historical lineage. It
restores task-domain payload shadows, queues a task `.all` register intent and
every live child/edge upsert at the snapshot's original HLC, then recreates
task-domain delete outbox work from the preserved tombstones at their original
HLCs. Original deletion timestamps remain available for retention; CloudKit
confirmation receipts do not cross the backup boundary. Only after those rows
exist does the transaction reserve the local clock strictly beyond the complete
live/tombstone/shadow maximum; restore audit envelopes therefore mint above the
imported history. Audit entity IDs are deterministically chunked at the shared
batch cap so a large backup cannot exceed the sync-envelope size limit; an
artifact-only graph still records one restore audit.

This is deliberately not an authoritative iCloud rollback. Import is a
non-destructive merge: native rows and outbox entries retain the backup's
original HLCs, so a newer CloudKit register or tombstone remains newer when sync
resumes. An explicit “replace cloud state from this backup” product would need a
separate destructive flow and new clocks; it is not part of this contract.

Dependency edges remain valid history when either endpoint is completed.
Cancellation, not completion, is the lifecycle operation that detaches and
prevents recreation of dependency edges.

## Required convergence matrix

1. Complete parent, create successor, and stale parent content edit in all six
   arrival orders.
2. Concurrent schedule- and completion-anchored completions.
3. Complete versus reopen in both orders.
4. Complete, reopen, and re-complete with stable successor identity.
5. Reopen versus an already advanced descendant.
6. `open`, `in_progress`, and `someday` successor reconciliation.
7. Parent/successor delete, full-resync, generation snapshot, and authoritative
   adoption.
8. CloudKit `serverRecordChanged`, outbox coalescing, future-record replay, and
   post-baseline local-intent replay for every task register.
9. Apple-native graph export/import round trip, including completed and revoked
   recurrence chains, in-progress dependencies, original outbox clocks, invalid
   graph rollback, fresh-root ordering, nonfresh/missing-root portable fallback,
   dual-representation mismatch, task-domain tombstones, opaque future-field
   shadows, artifact-only restore eligibility, and bounded large-restore audit
   chunks.

## Verification evidence

- Apple package XCTest: 482 tests, zero failures.
- Apple package Swift Testing: 2,448 tests in 138 suites, zero failures.
- Core package: 2,584 tests, 23 explicitly gated skips, zero failures.
- `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh`: passed, including
  release builds, staged-bundle/Mach-O closure, schema/payload/migration gates,
  localization compilation, and packaged MCP smoke.
- Independent `python3 script/mcp_stdio_smoke.py`: passed; `tools/list` returned
  118 tools and the create/list/error-envelope probes succeeded.

Credential-bound notarization, production entitlements, App Group runtime
acceptance, CloudKit production promotion, and device/install evidence remain
owner release-account work rather than implementation gaps in this model.
