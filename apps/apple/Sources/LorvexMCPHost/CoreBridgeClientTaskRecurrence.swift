import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func setTaskRecurrence(taskID: String, rule: TaskRecurrenceRule) async throws -> Value {
    taskValue(try await service.setTaskRecurrence(taskID: taskID, rule: rule))
  }

  func removeTaskRecurrence(taskID: String) async throws -> Value {
    taskValue(try await service.removeTaskRecurrence(taskID: taskID))
  }

  func addTaskRecurrenceException(taskID: String, exceptionDate: String) async throws -> Value {
    taskValue(
      try await service.addTaskRecurrenceException(taskID: taskID, exceptionDate: exceptionDate))
  }

  func removeTaskRecurrenceException(taskID: String, exceptionDate: String) async throws -> Value {
    taskValue(
      try await service.removeTaskRecurrenceException(taskID: taskID, exceptionDate: exceptionDate))
  }

  func appendToTaskBody(taskID: String, text: String) async throws -> Value {
    taskValue(try await service.appendToTaskBody(taskID: taskID, additionalNotes: text))
  }

  func setTaskReminders(taskID: String, reminders: [String]) async throws -> Value {
    taskValue(try await service.setTaskReminders(taskID: taskID, reminderAts: reminders))
  }
}
