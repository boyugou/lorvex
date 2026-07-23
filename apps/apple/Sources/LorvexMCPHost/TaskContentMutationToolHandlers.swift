import Foundation
import MCP

extension ToolRegistry {
  func appendToTaskBodyResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.", toolName: "append_to_task_body")
    }
    guard let text = arguments["text"]?.stringValue, !text.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A text value is required.", toolName: "append_to_task_body")
    }
    let value = try await appendToTaskBodyPayload(taskID: taskID, text: text)
    return successResult(text: "Appended to body.", value: value)
  }

  func setTaskRemindersResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.", toolName: "set_task_reminders")
    }
    guard let reminderValues = arguments["reminders"]?.arrayValue else {
      return Self.errorResult(
        code: "validation",
        message: "A reminders array is required. Pass [] explicitly to clear reminders.",
        toolName: "set_task_reminders")
    }
    var reminders: [String] = []
    reminders.reserveCapacity(reminderValues.count)
    for value in reminderValues {
      guard let reminder = value.stringValue, !reminder.isEmpty else {
        return Self.errorResult(
          code: "validation",
          message: "Each reminders entry must be a non-empty RFC 3339 UTC timestamp string.",
          toolName: "set_task_reminders")
      }
      reminders.append(reminder)
    }
    let value = try await setTaskRemindersPayload(taskID: taskID, reminders: reminders)
    return successResult(text: "Reminders set.", value: value)
  }
}
