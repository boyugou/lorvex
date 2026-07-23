import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  /// Cap on the `defer_history` entries embedded in a `get_task` response — a
  /// bounded recent window over the task's changelog-derived defer trail.
  static let deferHistoryLimit = 20

  func loadTask(id: String) async throws -> Value {
    let task = try await service.loadTask(id: id)
    let history = try await service.deferHistory(taskID: id, limit: Self.deferHistoryLimit)
    var object = taskValue(task).objectValue ?? [:]
    object["defer_history"] = Self.deferHistoryValue(history)
    return .object(object)
  }

  /// Map the task's defer trail to the read-only `defer_history` array, newest
  /// first. `deferred_at` / `structured_reason` / `initiated_by` are
  /// system-controlled and stay verbatim; the free-text `note` is user content
  /// carried under the `note` key, which the central response fence wraps in
  /// ⟦user⟧…⟦/user⟧ sentinels (Core Design Rule 6).
  static func deferHistoryValue(_ history: [TaskDeferHistoryEntry]) -> Value {
    .array(
      history.map { entry in
        .object([
          "deferred_at": .string(entry.deferredAt),
          "structured_reason": entry.structuredReason.map(Value.string) ?? .null,
          "note": entry.note.map(Value.string) ?? .null,
          "initiated_by": entry.initiatedBy.map(Value.string) ?? .null,
        ])
      })
  }
}
