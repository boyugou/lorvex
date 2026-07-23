import LorvexCore
import MCP

enum TaskRecurrenceExceptionOperation {
  case add
  case remove
}

extension ToolRegistry {
  func setTaskRecurrencePayload(taskID: String, rule: [String: Any]) async throws -> Value {
    guard let parsed = TaskRecurrenceRule.bridgeRule(from: rule) else {
      throw TaskRecurrenceToolStoreError(message: "Invalid recurrence rule.")
    }
    return try await coreBridge.setTaskRecurrence(taskID: taskID, rule: parsed)
  }

  func removeTaskRecurrencePayload(taskID: String) async throws -> Value {
    try await coreBridge.removeTaskRecurrence(taskID: taskID)
  }

  func taskRecurrenceExceptionPayload(
    taskID: String,
    exceptionDate: String,
    operation: TaskRecurrenceExceptionOperation
  ) async throws -> Value {
    switch operation {
    case .add:
      return try await coreBridge.addTaskRecurrenceException(
        taskID: taskID,
        exceptionDate: exceptionDate
      )
    case .remove:
      return try await coreBridge.removeTaskRecurrenceException(
        taskID: taskID,
        exceptionDate: exceptionDate
      )
    }
  }
}

struct TaskRecurrenceToolStoreError: ToolStoreError {
  let message: String
}
