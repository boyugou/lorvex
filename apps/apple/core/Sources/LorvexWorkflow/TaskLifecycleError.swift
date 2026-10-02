import Foundation
import LorvexDomain

/// A task status change the task's current status or dependencies refuse.
///
/// ``description`` is the English sentence the MCP boundary returns under the
/// `validation` code (naming the blocking task ids where there are any, so an
/// assistant can act on them); the app recognizes each case and words it in
/// the interface language.
public enum TaskLifecycleError: Error, Equatable, Sendable, CustomStringConvertible,
  LocalizedError
{
  /// Starting `taskId` was refused because the tasks in `blockerIds`, sorted by
  /// id, are still active (`open`, `in_progress`, or `someday`) and not
  /// archived.
  case startBlockedByDependencies(taskId: String, blockerIds: [String])
  /// A finished task was asked to finish the other way: `completed` to
  /// `cancelled`, or `cancelled` to `completed`. A finished task changes only by
  /// reopening it first.
  case finishedTaskTransition(taskId: String, from: TaskStatus, to: TaskStatus)
  /// Starting a task whose status is not `open` (it is `completed`,
  /// `cancelled`, or `someday`); reopening it first makes it startable.
  case startRequiresOpenTask(status: TaskStatus)
  /// Pausing a task whose status is not `in_progress`; only a started task can
  /// be paused.
  case pauseRequiresStartedTask(status: TaskStatus)

  public var description: String {
    switch self {
    case let .startBlockedByDependencies(taskId, blockerIds):
      return "Cannot start task \(taskId): blocked by unfinished dependencies "
        + "[\(blockerIds.joined(separator: ", "))]. Complete or cancel them first."
    case let .finishedTaskTransition(taskId, from, to):
      return "Cannot transition task \(taskId) from \(from) to \(to); reopen it first"
    case let .startRequiresOpenTask(status):
      return "Cannot start a \(status.asString) task; reopen it to open first."
    case let .pauseRequiresStartedTask(status):
      return "Cannot pause a \(status.asString) task; only an in-progress task can be paused."
    }
  }

  public var errorDescription: String? { description }
}
