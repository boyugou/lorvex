import Foundation

/// Who a task was handed to: the right half of a `task_delegation` edge.
///
/// Every first-party writer uses ``assistant``, the person's own AI assistant.
/// The stored form is a lowercase identifier rather than that one word, so a
/// named agent can follow without a schema change.
public enum TaskDelegationAssignee {
  /// The person's AI assistant.
  public static let assistant = "assistant"

  /// Whether `value` is a storable assignee: 1 to 32 characters, each a
  /// lowercase ASCII letter, a digit, or an underscore. The table's CHECK
  /// constraint states the same rule.
  public static func isValid(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard (1...32).contains(bytes.count) else { return false }
    return bytes.allSatisfy { byte in
      (0x61...0x7A).contains(byte) || (0x30...0x39).contains(byte) || byte == 0x5F
    }
  }
}

/// Where a delegated task stands.
public enum TaskDelegationState: String, Sendable, CaseIterable {
  /// The assignee holds the task and has not handed it back.
  case assistant
  /// The assignee handed the task back with what it did; the person has it.
  case returned
}

/// A task handed to an assignee, as stored: one `task_delegations` row.
public struct TaskDelegationRecord: Equatable, Sendable {
  public var taskId: String
  public var assignee: String
  public var state: TaskDelegationState
  /// What the person asked for, in their words; nil when they said nothing
  /// beyond the task itself.
  public var request: String?
  public var createdAt: String
  public var updatedAt: String

  public init(
    taskId: String, assignee: String, state: TaskDelegationState, request: String?,
    createdAt: String, updatedAt: String
  ) {
    self.taskId = taskId
    self.assignee = assignee
    self.state = state
    self.request = request
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  /// The longest `request` the table stores, in characters.
  public static let maxRequestLength = 2000
}
