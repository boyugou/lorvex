import Foundation
import LorvexCore
import LorvexDomain
import MCP

extension CoreBridgeClient {
  func completeTask(id: String) async throws -> Value {
    // The enriched task is captured inside the completion transaction; the
    // previous post-commit `loadTask` re-read could throw `taskNotFound` — and
    // surface as a tool error — if a concurrent process deleted the row after
    // the completion had already succeeded.
    Self.taskValue(from: try await service.completeTaskReturningTask(id: id))
  }

  func setTaskStatus(id: String, operation: String) async throws -> Value {
    let task: LorvexTask
    switch operation {
    case "task.start": task = try await service.startTaskReturningTask(id: id)
    case "task.pause": task = try await service.pauseTaskReturningTask(id: id)
    case "task.cancel": task = try await service.cancelTaskReturningTask(id: id)
    default: task = try await service.reopenTaskReturningTask(id: id)
    }
    return Self.taskValue(from: task)
  }

  func setTaskSomeday(id: String) async throws -> Value {
    Self.taskValue(from: try await service.markTaskSomeday(id: id))
  }

  func deferTask(
    id: String, untilDate: String, structuredReason: String?, reason: String?
  ) async throws -> Value {
    let date = try Self.requirePlannedDate(untilDate)
    let structured = try Self.normalizedDeferReason(structuredReason)
    // The structured reason is written to the `last_defer_reason` column (the
    // canonical, queryable, syncable home). The optional free-text reason is
    // persisted onto this defer's `ai_changelog` row (via `note:`), where the
    // read-only `get_task` `defer_history` surfaces it — not into `ai_notes`,
    // which is a current-context summary rather than an append-only action log.
    // It is also echoed back on this response as a transient `defer_note`.
    let task = try await service.deferTaskReturningTask(
      id: id, until: date, reason: structured, note: reason)
    var object = Self.taskValue(from: task).objectValue ?? [:]
    object["defer_note"] = Self.deferDetailNote(reason: reason).map(Value.string) ?? .null
    return .object(object)
  }

  /// Validate an optional structured defer reason against the canonical
  /// allowlist. Returns the trimmed reason, nil when absent/empty, or throws
  /// for an unrecognized category.
  static func normalizedDeferReason(_ raw: String?) throws -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    guard DeferReason.parse(trimmed) != nil else {
      throw LorvexCoreError.unsupportedOperation(
        "Unknown structured_reason '\(trimmed)'. Expected one of: "
          + DeferReasonName.allDeferReasons.joined(separator: ", ") + ".")
    }
    return trimmed
  }

  /// Build the transient `defer_note` echoed on the defer response for a defer's
  /// optional free-text detail. The structured category lives in the
  /// `last_defer_reason` column; the free-text detail is persisted onto the
  /// defer's append-only `ai_changelog` row (surfaced read-only via
  /// `get_task`'s `defer_history`), never into `ai_notes` — that field is a
  /// current assistant-context summary, not an action log.
  static func deferDetailNote(reason: String?) -> String? {
    guard let detail = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty
    else { return nil }
    return "Deferred: \(detail)"
  }
}
