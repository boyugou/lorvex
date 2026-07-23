import Foundation
import MCP

extension ToolRegistry {
  func setTaskRecurrenceResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.", toolName: "set_task_recurrence")
    }
    guard let rule = arguments["recurrence"]?.objectValue else {
      return Self.errorResult(
        code: "validation", message: "A recurrence object is required.",
        toolName: "set_task_recurrence")
    }
    let ruleAny: [String: Any]
    do {
      ruleAny = try recurrenceRulePayload(from: rule)
    } catch let error as RecurrenceRuleWireError {
      return Self.errorResult(
        code: "validation", message: error.message, toolName: "set_task_recurrence")
    }
    guard ruleAny["freq"] != nil else {
      return Self.errorResult(
        code: "validation", message: "recurrence.freq is required.",
        toolName: "set_task_recurrence")
    }
    do {
      let task = try await setTaskRecurrencePayload(taskID: taskID, rule: ruleAny)
      return successResult(text: "Recurrence set.", value: task)
    } catch let error as TaskRecurrenceToolStoreError {
      return notFoundResult(error, toolName: "set_task_recurrence")
    }
  }

  func addTaskRecurrenceExceptionResult(arguments: [String: Value]) async throws -> CallTool.Result {
    try await recurrenceExceptionResult(arguments: arguments, operation: .add)
  }

  func removeTaskRecurrenceResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.", toolName: "remove_task_recurrence")
    }
    do {
      let task = try await removeTaskRecurrencePayload(taskID: taskID)
      return successResult(text: "Recurrence removed.", value: task)
    } catch let error as TaskRecurrenceToolStoreError {
      return notFoundResult(error, toolName: "remove_task_recurrence")
    }
  }

  func removeTaskRecurrenceExceptionResult(arguments: [String: Value]) async throws -> CallTool.Result {
    try await recurrenceExceptionResult(arguments: arguments, operation: .remove)
  }

  private func recurrenceExceptionResult(
    arguments: [String: Value],
    operation: TaskRecurrenceExceptionOperation
  ) async throws -> CallTool.Result {
    let toolName: String
    switch operation {
    case .add: toolName = "add_task_recurrence_exception"
    case .remove: toolName = "remove_task_recurrence_exception"
    }
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.", toolName: toolName)
    }
    guard let occurrenceDate = arguments["occurrence_date"]?.stringValue, !occurrenceDate.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "An occurrence_date (YYYY-MM-DD) is required.",
        toolName: toolName)
    }
    do {
      let task = try await taskRecurrenceExceptionPayload(
        taskID: taskID,
        exceptionDate: occurrenceDate,
        operation: operation
      )
      return successResult(text: "Recurrence exception updated.", value: task)
    } catch let error as TaskRecurrenceToolStoreError {
      return notFoundResult(error, toolName: toolName)
    }
  }
}
