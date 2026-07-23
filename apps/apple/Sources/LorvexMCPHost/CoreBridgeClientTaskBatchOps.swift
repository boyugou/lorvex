import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  /// Build the `skipped: [{id, reason}]` array shared by every batch tool.
  /// The batch services report only the skipped ids; the reason is the uniform
  /// class for a lifecycle skip (missing id or already-terminal state).
  static func skippedObjects(_ ids: [String], reason: String) -> Value {
    .array(ids.map { .object(["id": .string($0), "reason": .string(reason)]) })
  }

  func batchCompleteTasks(taskIDs: [String]) async throws -> Value {
    // `changedTasks` is enriched inside the write transaction, so the result can
    // never drop a task the batch completed (a post-commit re-read could, if a
    // concurrent process deleted the row in the gap).
    let result = try await service.batchCompleteTasks(ids: taskIDs)
    return .object([
      "results": Self.taskValues(from: result.changedTasks),
      "count": .int(result.changedTasks.count),
      "skipped": Self.skippedObjects(
        result.skipped, reason: "not found or already completed"),
    ])
  }

  func batchReopenTasks(taskIDs: [String]) async throws -> Value {
    let result = try await service.batchReopenTasks(ids: taskIDs)
    return .object([
      "results": Self.taskValues(from: result.changedTasks),
      "count": .int(result.changedTasks.count),
      "skipped": Self.skippedObjects(result.skipped, reason: "not found or already open"),
    ])
  }

  func batchMoveTasks(taskIDs: [String], listID: String) async throws -> Value {
    let result = try await service.batchMoveTasks(ids: taskIDs, toListID: listID)
    return .object([
      "results": Self.taskValues(from: result.moved),
      "count": .int(result.moved.count),
      "list_id": .string(listID),
      "skipped": Self.skippedObjects(result.skipped, reason: "not found"),
    ])
  }

  func batchCancelTasks(taskIDs: [String], cancelSeries: Bool) async throws -> Value {
    let result = try await service.batchCancelTasks(ids: taskIDs, cancelSeries: cancelSeries)
    return .object([
      "results": Self.taskValues(from: result.cancelled),
      "count": .int(result.cancelled.count),
      "skipped": Self.skippedObjects(
        result.skipped, reason: "not found or already completed/cancelled"),
    ])
  }

  func batchCancelTasksInList(
    listID: String, statuses: [String]?, cancelSeries: Bool
  ) async throws -> Value {
    // The cancelled tasks are enriched inside the cancel transaction, so a
    // concurrent delete cannot drop one from `results`.
    let cancelled = try await service.batchCancelTasksInList(
      listID: listID, statuses: statuses, cancelSeries: cancelSeries)
    return .object([
      "results": Self.taskValues(from: cancelled),
      "count": .int(cancelled.count),
      "list_id": .string(listID),
      "skipped": .array([]),
    ])
  }
}

extension CoreBridgeClient {
  func permanentDeleteTask(taskID: String) async throws -> Value {
    let receipt = try await mcpMutations.deleteTaskForMcp(id: taskID)
    return .object([
      "id": .string(taskID),
      "deleted": .bool(receipt.deleted),
      "previous": receipt.previous.map { Self.taskValue(from: $0) } ?? .null,
    ])
  }

  func archiveTask(id: String) async throws -> Value {
    let task = try await service.archiveTask(id: id)
    return Self.archivedTaskValue(from: task, archived: true)
  }

  func unarchiveTask(id: String) async throws -> Value {
    let task = try await service.unarchiveTask(id: id)
    return Self.archivedTaskValue(from: task, archived: false)
  }

  /// The task value with an explicit `archived` flag. `LorvexTask` carries no
  /// archived field, so the flag is the only signal that the archive/restore
  /// took effect.
  private static func archivedTaskValue(from task: LorvexTask, archived: Bool) -> Value {
    var object = Self.taskValue(from: task).objectValue ?? [:]
    object["archived"] = .bool(archived)
    return .object(object)
  }
}
