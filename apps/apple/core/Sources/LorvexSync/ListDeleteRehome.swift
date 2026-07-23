import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Cross-peer propagation for a sync-applied list deletion's task re-home.
///
/// The schema trigger `trg_lists_before_delete` re-homes a deleted non-inbox
/// list's tasks to `inbox` (`UPDATE tasks SET list_id='inbox'`) but bumps
/// neither their `version` column nor enqueues an outbox row. On a bare
/// sync-apply of a peer's list delete that re-home is a silent, unpropagated
/// local mutation: a device holding a task in the deleted list moves it to inbox
/// locally, yet no peer ever learns of the move, so the fleet permanently
/// diverges on that task's `list_id` (SA1).
///
/// This closes the gap. The re-home is turned into a first-class,
/// causally-versioned edit:
///
///   1. ``captureRehomeCandidates(_:envelope:)`` snapshots the task ids a
///      list-delete envelope is ABOUT to re-home — read BEFORE apply, while the
///      rows still carry the doomed `list_id` (the trigger overwrites it).
///   2. The caller applies the delete; the trigger moves the captured tasks to
///      inbox.
///   3. ``reenqueueRehomed(_:taskIds:mintVersion:deviceId:)`` mints a fresh
///      local HLC for each still-present task, stamps its content register, and
///      enqueues an Upsert of the current snapshot (now `list_id='inbox'`), so
///      the move converges across peers.
///
/// The HLC clock and local device identity live one layer up in the driver
/// (`SwiftLorvexCoreService.applyInbound`), where they are in scope; the
/// apply-layer appliers are not. `reenqueueRehomed` therefore takes a
/// `mintVersion` closure and `deviceId` rather than reaching for a clock itself.
///
/// No-resurrection contract: a task concurrently deleted has no live row, so it
/// is neither captured (step 1 reads only live rows) nor re-enqueued (step 3
/// rechecks existence). A delete that lands AFTER the re-home carries a strictly
/// greater HLC — either the same monotone local clock minted it after the
/// re-home version, or the peer authored it at a dominating HLC — so the delete
/// still wins LWW and the task converges to DELETED. The re-home upsert only
/// wins over a delete when that delete is strictly older by HLC, which is the
/// ordinary last-writer-wins outcome for a live task's field edit, never a
/// resurrection of an already-known-deleted row.
public enum ListDeleteRehome {

  /// The task ids a `list` Delete envelope for a NON-inbox list is about to
  /// re-home to inbox, read from the live `tasks.list_id` BEFORE the delete
  /// runs.
  ///
  /// Must be called before the delete applies: the `trg_lists_before_delete`
  /// trigger overwrites `list_id` with `inbox`, so a post-apply query can no
  /// longer recover which tasks belonged to the deleted list.
  ///
  /// Returns `[]` — nothing to propagate — for every envelope that does not
  /// re-home tasks:
  /// - non-`list` entity kinds and non-Delete operations,
  /// - the `inbox` list itself (its tasks are never re-homed; deleting inbox
  ///   while tasks reference it is refused, and a full-reset wipe leaves no
  ///   tasks), and
  /// - an already-deleted list, because no live task can reference a gone list.
  ///   This is what makes a re-applied list-delete re-enqueue nothing
  ///   (idempotent): the tasks already carry `list_id='inbox'`.
  public static func captureRehomeCandidates(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> [String] {
    guard envelope.operation == .delete,
      envelope.entityType == .list,
      envelope.entityId != inboxListId
    else { return [] }
    do {
      return try String.fetchAll(
        db, sql: "SELECT id FROM tasks WHERE list_id = ?", arguments: [envelope.entityId])
    } catch { throw ApplyError.lift(error) }
  }

  /// Re-enqueue the re-homed tasks so their move to inbox propagates to peers.
  ///
  /// Call ONLY after the list-delete actually applied (the caller observed
  /// ``ApplyResult/applied``) and only with ids from
  /// ``captureRehomeCandidates(_:envelope:)`` taken before that apply. For each
  /// task still present, mint a fresh dominating HLC via `mintVersion`, stamp
  /// `content_version` plus the transport high-water, and enqueue an Upsert of
  /// its current snapshot (now `list_id='inbox'`). The task payload owns
  /// `list_id`; a transport-only re-emit would carry no authored task register
  /// and authoritative-snapshot replay could silently lose the re-home.
  ///
  /// The existence recheck is the guard against resurrecting a concurrently
  /// deleted task: an id captured before the apply whose row has since gone
  /// (deleted by an earlier envelope in the same batch, or by an interleaved
  /// local delete) is skipped, never re-created. A task that is still present is
  /// genuinely live and its inbox re-home is a legitimate edit to propagate.
  ///
  /// The fresh HLC can, in a one-round-trip window, overwrite a peer's subsequent
  /// genuine edit that lands between the omitting envelope's version and this
  /// re-emit's version — an accepted low-frequency trade-off with no cheap
  /// mitigation. See `docs/design/SYNC_APPLY_SEMANTICS.md`, "Convergence re-emit".
  public static func reenqueueRehomed(
    _ db: Database,
    taskIds: [String],
    mintVersion: (Hlc?) -> String,
    deviceId: String
  ) throws {
    for taskId in taskIds {
      guard
        let rawFloor = try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [taskId])
      else { continue }
      let floor: Hlc
      do {
        floor = try Hlc.parseCanonical(rawFloor)
        guard floor.description == rawFloor else { throw RehomeError.nonCanonicalFloor }
      } catch {
        throw RehomeError.invalidFloor(taskId: taskId, value: rawFloor)
      }
      let rawVersion = mintVersion(floor)
      let version: Hlc
      do {
        version = try Hlc.parseCanonical(rawVersion)
        guard version.description == rawVersion else { throw RehomeError.nonCanonicalMint }
      } catch {
        throw RehomeError.invalidMint(taskId: taskId, value: rawVersion)
      }
      guard version > floor else {
        throw RehomeError.nonDominatingMint(
          taskId: taskId, floor: rawFloor, value: rawVersion)
      }

      try db.execute(
        sql: """
          UPDATE tasks
          SET content_version = ?, version = ?, updated_at = ?
          WHERE id = ? AND version = ?
          """,
        arguments: [rawVersion, rawVersion, SyncTimestampFormat.syncTimestampNow(), taskId, rawFloor])
      guard db.changesCount == 1 else {
        if try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [taskId]) == nil
        {
          continue
        }
        throw RehomeError.concurrentTaskChange(taskId: taskId)
      }

      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: taskId)
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: EntityName.task, entityId: taskId, payload: payload,
        context: OutboxWriteContext(
          version: rawVersion, deviceId: deviceId,
          registerIntent: .task(.content)))
    }
  }

  private enum RehomeError: Error, Sendable, Equatable {
    case nonCanonicalFloor
    case nonCanonicalMint
    case invalidFloor(taskId: String, value: String)
    case invalidMint(taskId: String, value: String)
    case nonDominatingMint(taskId: String, floor: String, value: String)
    case concurrentTaskChange(taskId: String)
  }
}
