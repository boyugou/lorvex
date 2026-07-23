import Foundation
import MCP

extension ToolRegistry {
  func addTaskReminderResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id value is required.", toolName: "add_task_reminder")
    }
    guard let reminderAt = arguments["reminder_at"]?.stringValue, !reminderAt.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A reminder_at value is required.", toolName: "add_task_reminder")
    }

    let value = try await addTaskReminderPayload(taskID: taskID, reminderAt: reminderAt)
    return successResult(text: "Added reminder.", value: value)
  }

  func removeTaskReminderResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id value is required.", toolName: "remove_task_reminder")
    }
    guard let reminderID = arguments["reminder_id"]?.stringValue, !reminderID.isEmpty else {
      return Self.errorResult(
        code: "validation",
        message: "A reminder_id value is required.",
        toolName: "remove_task_reminder"
      )
    }

    let value = try await removeTaskReminderPayload(taskID: taskID, reminderID: reminderID)
    return successResult(text: "Removed reminder.", value: value)
  }
}
