import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore
import LorvexSync
import MCP

extension ToolRegistry {
  /// Resolves an optional date selector against the same database snapshot the
  /// core uses for day-scoped workflows. The configured product timezone, not
  /// the MCP host process's device timezone, owns an omitted date.
  func logicalDay(_ value: Value?, field: String = "date") async throws -> String {
    if let explicit = try StrictScalarArguments.optionalString(value, field: field) {
      return explicit
    }
    return try await coreBridge.service.getSessionContext().date
  }

  /// Resolve the target task id for a task-scoped tool. `task_id` is the one
  /// documented schema name; `id` is accepted as a silent parse-time fallback so
  /// a caller that reaches for the task's own field name (as seen on `get_task`
  /// output) still resolves. Returns nil when neither is present as a non-empty
  /// string, so the caller emits its own `task_id` validation error.
  static func taskScopedID(from arguments: [String: Value]) throws -> String? {
    if let taskID = try StrictScalarArguments.optionalString(
      arguments["task_id"], field: "task_id"), !taskID.isEmpty
    { return taskID }
    if let id = try StrictScalarArguments.optionalString(arguments["id"], field: "id"),
      !id.isEmpty
    { return id }
    return nil
  }

  static func priorityNumber(from value: Value?) -> Int? {
    if let number = value?.intValue {
      return (1...3).contains(number) ? number : nil
    }
    guard let text = value?.stringValue?.uppercased() else { return nil }
    switch text {
    case "1", "P1": return 1
    case "2", "P2": return 2
    case "3", "P3": return 3
    default: return nil
    }
  }

  /// Resolve an `update_task` priority argument, distinguishing "omitted or
  /// null" (returns nil — keep the task's existing priority) from "present but
  /// not 1/2/3" (throws the same `ValidationError` `create_task` and the batch
  /// tools raise). Prevents an out-of-range priority from being silently
  /// dropped while the caller believes it took effect.
  static func requiredPriorityNumber(from value: Value?) throws -> Int? {
    guard let value, value != .null else { return nil }
    if let number = priorityNumber(from: value) { return number }
    let shown =
      value.intValue.map(String.init)
      ?? value.stringValue.map { "\"\($0)\"" } ?? "non-integer"
    throw ValidationError.invalidFormat(
      field: "priority", expected: "1 (P1), 2 (P2), or 3 (P3)", actual: shown)
  }

  /// Maps a thrown domain error to a stable, machine-readable error code so AI
  /// clients can branch on the failure class instead of parsing prose. Used by
  /// the dispatch-level catch-all (handlers that recognize a failure still emit
  /// their own richer code). Anything unrecognized falls back to `tool_error`.
  static func errorCode(for error: Error) -> String {
    switch error {
    case let storeError as StoreError:
      switch storeError {
      case .notFound: return "not_found"
      case .staleVersion, .versionSuperseded: return "conflict"
      case .validation: return "validation"
      case .serialization, .invariant: return "tool_error"
      }
    case is ValidationError:
      return "validation"
    case let applyError as ApplyError:
      if case .dependencyCycleRejected = applyError { return "dependency_cycle" }
      return "tool_error"
    case LorvexCoreError.taskNotFound:
      return "not_found"
    case LorvexCoreError.notFound:
      // A typed entity lookup miss (list / habit / calendar event or series)
      // joins `taskNotFound` (above) on the `not_found` code, so every lookup
      // miss carries the same machine-readable class regardless of entity.
      return "not_found"
    case LorvexCoreError.validation:
      return "validation"
    case LorvexCoreError.conflict:
      // A uniqueness collision (rename a tag / memory onto an existing name)
      // shares the `conflict` code with `StoreError.staleVersion`, so a client
      // distinguishes a name collision from a plain validation or generic error.
      return "conflict"
    case LorvexCoreError.emptyTitle:
      return "validation"
    default:
      return "tool_error"
    }
  }

  /// Extracts the user-facing message for a thrown error, preferring a domain
  /// type's own wording. `localizedDescription` alone yields a generic Cocoa
  /// string for plain `Error`/`CustomStringConvertible` types (e.g.
  /// `ValidationError`), so route through `errorDescription` / `description`
  /// first.
  static func errorMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
      return description
    }
    // `String(describing:)` surfaces a `CustomStringConvertible` domain type's
    // own wording (e.g. `ValidationError`) rather than the generic Cocoa string
    // that `localizedDescription` yields for a plain `Error`.
    return String(describing: error)
  }

  static func errorResult(code: String, message: String, toolName: String? = nil) -> CallTool.Result {
    let fencedMessage = SecurityFencing.fence(message)
    var payload: [String: Value] = [
      "code": .string(code),
      "message": .string(fencedMessage),
    ]
    if let toolName {
      payload["tool"] = .string(toolName)
    }
    return CallTool.Result(
      content: [.text(text: fencedMessage, annotations: nil, _meta: nil)],
      structuredContent: Optional.some(.object(payload)),
      isError: true
    )
  }
}
