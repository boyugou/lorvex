import MCP

extension ToolRegistry {
  func createTaskPayload(arguments: [String: Value], title: String) async throws -> Value {
    try await coreBridge.createTask(arguments: arguments, title: title)
  }

  /// The bridge reads the remaining optional fields (notes, dates, estimate,
  /// raw input) straight from `arguments`, preserving their omitted-vs-null
  /// semantics; only the values needing handler-side validation or alias
  /// resolution are passed parsed.
  func updateTaskPayload(
    id: String,
    title: String?,
    priority: Int?,
    tags: [String]?,
    dependsOn: [String]?,
    arguments: [String: Value]
  ) async throws -> Value {
    try await coreBridge.updateTask(
      id: id,
      title: title,
      priority: priority,
      tags: tags,
      dependsOn: dependsOn,
      arguments: arguments
    )
  }

  func completeTaskPayload(id: String) async throws -> Value {
    try await coreBridge.completeTask(id: id)
  }

  func deferTaskPayload(
    id: String, untilDate: String, structuredReason: String?, reason: String?
  ) async throws -> Value {
    try await coreBridge.deferTask(
      id: id, untilDate: untilDate, structuredReason: structuredReason, reason: reason)
  }

  func setTaskStatusPayload(id: String, operation: TaskStatusOperation) async throws -> Value {
    try await coreBridge.setTaskStatus(id: id, operation: operation.toolOperation)
  }

  func setTaskSomedayPayload(id: String) async throws -> Value {
    try await coreBridge.setTaskSomeday(id: id)
  }

  func moveTaskToListPayload(id: String, listID: String) async throws -> Value {
    try await coreBridge.moveTaskToList(id: id, listID: listID)
  }
}

struct TaskMutationToolStoreError: ToolStoreError {
  let message: String
}
