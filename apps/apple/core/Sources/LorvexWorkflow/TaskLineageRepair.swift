import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Repairs tasks that name a predecessor without belonging to a series.
///
/// A generated occurrence names the occurrence it came from in `spawned_from`.
/// The link is valid only inside that predecessor's series, so the task must
/// carry the series' `recurrence_group_id`. A task that kept the link after
/// losing its series is one no other device accepts: its record is refused as
/// invalid, so the task never converges.
public enum TaskLineageRepair {
  /// One task the pass could not repair; the others are still repaired.
  public struct Failure: Sendable {
    public let taskId: String
    public let error: any Error
  }

  public struct Outcome: Sendable {
    /// The tasks that lost their link, in id order.
    public var repairedTaskIds: [String] = []
    public var failures: [Failure] = []
  }

  /// Matches a task that names a predecessor without a series.
  private static let seriesLessLink = "spawned_from IS NOT NULL AND recurrence_group_id IS NULL"

  /// Turn every task that names a predecessor without a series into an
  /// ordinary one-off, in the caller's transaction.
  ///
  /// Each task loses its link under a fresh schedule stamp and is otherwise
  /// left as it is: its status and any task generated from it do not change.
  /// A predecessor that still records the task stops recording it, which ends
  /// that authorization. The pass is idempotent, because a repaired task no
  /// longer matches.
  ///
  /// `enqueue` receives the rows one task's repair changed and queues them for
  /// the other devices. It runs in the same savepoint as that task's writes,
  /// so a task that cannot be written or queued is rolled back alone, reported
  /// in the outcome, and does not hold back the others. `excluding` leaves out
  /// tasks a caller already knows to fail.
  ///
  /// A task stamped ahead of this device's clock is reported with
  /// `StoreError.staleVersion`. A caller on the write surface rethrows such a
  /// failure, which replays the whole pass on a later stamp. An error that
  /// ends the transaction, or a savepoint that cannot be rolled back, is
  /// thrown: the caller's transaction must not commit.
  public static func clearSeriesLessPredecessorLinks(
    _ db: Database, hlc: HlcSession, now: String, excluding: Set<String> = [],
    enqueue: (Database, RecurrenceDisableEffects) throws -> Void
  ) throws -> Outcome {
    var outcome = Outcome()
    let rows = try Row.fetchAll(
      db, sql: "SELECT id, spawned_from FROM tasks WHERE \(seriesLessLink) ORDER BY id")
    for row in rows {
      let taskId: String = row[0]
      let predecessorId: String = row[1]
      guard !excluding.contains(taskId) else { continue }
      do {
        try StoreTransactions.withSavepoint(db, "task_lineage_repair") { db in
          let version = hlc.nextVersionString()
          var effects = RecurrenceDisableEffects()
          if try RecurrenceDisableReconciliation.severPredecessor(
            db, predecessorId: predecessorId, successorId: taskId, version: version, now: now)
          {
            effects.taskUpsertIds.append(predecessorId)
            effects.severedPredecessorIds.append(predecessorId)
          }
          try db.execute(
            sql:
              "UPDATE tasks SET spawned_from = NULL, spawned_from_version = NULL, "
              + "schedule_version = ?1, version = MAX(version, ?1), updated_at = ?2 "
              + "WHERE id = ?3 AND ?1 > schedule_version",
            arguments: [version, now, taskId])
          guard db.changesCount == 1 else {
            throw StoreError.staleVersion(entity: EntityName.task, id: taskId)
          }
          effects.taskUpsertIds.append(taskId)
          effects.rerootedSuccessorIds.append(taskId)
          effects.normalize()
          try enqueue(db, effects)
        }
        outcome.repairedTaskIds.append(taskId)
      } catch {
        // Neither leaves a transaction to continue in: one ended it, the
        // other could not undo this task's writes.
        guard db.isInsideTransaction, !(error is StoreTransactionError) else { throw error }
        outcome.failures.append(Failure(taskId: taskId, error: error))
      }
    }
    return outcome
  }

  /// Whether any task outside `excluding` needs
  /// ``clearSeriesLessPredecessorLinks(_:hlc:now:excluding:enqueue:)``. A
  /// read, so a caller can skip the write transaction on the ordinary pass
  /// where nothing matches.
  public static func hasSeriesLessPredecessorLink(
    _ db: Database, excluding: Set<String> = []
  ) throws -> Bool {
    let ids = try String.fetchAll(db, sql: "SELECT id FROM tasks WHERE \(seriesLessLink)")
    return ids.contains { !excluding.contains($0) }
  }
}
