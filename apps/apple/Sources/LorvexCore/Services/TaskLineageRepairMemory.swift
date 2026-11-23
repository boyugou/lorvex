import Foundation

/// What the lineage repair has learned since the process started: which
/// tasks it could not repair, and whether it has reported a pass that failed
/// as a whole.
///
/// The repair runs after every in-app change, so without this a task that
/// keeps failing would open a write transaction and add a diagnostics entry
/// on every pass. The repair leaves out the tasks recorded here and reports a
/// failing pass once. Nothing here outlives the process: each launch tries
/// every task again.
final class TaskLineageRepairMemory: @unchecked Sendable {
  private let lock = NSLock()
  private var failedTaskIds: Set<String> = []
  private var passFailureLogged = false

  /// The tasks the repair could not repair and has logged.
  var failedTasks: Set<String> {
    lock.withLock { failedTaskIds }
  }

  /// Record tasks whose failure has been written to the diagnostics log.
  func recordFailedTasks(_ taskIds: some Sequence<String>) {
    lock.withLock { failedTaskIds.formUnion(taskIds) }
  }

  /// Whether a pass that failed as a whole has been logged.
  var hasLoggedPassFailure: Bool {
    lock.withLock { passFailureLogged }
  }

  func recordPassFailureLogged() {
    lock.withLock { passFailureLogged = true }
  }
}
