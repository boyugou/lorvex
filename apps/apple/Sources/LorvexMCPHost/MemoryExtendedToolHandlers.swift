import Foundation
import MCP

enum ToolStringValidationResult {
  case value(String)
  case error(CallTool.Result)
}

extension ToolRegistry {
  func requiredTrimmedString(
    _ name: String,
    from arguments: [String: Value],
    message: String,
    toolName: String
  ) -> ToolStringValidationResult {
    guard
      let value = arguments[name]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return .error(Self.errorResult(code: "validation", message: message, toolName: toolName))
    }
    return .value(value)
  }

  /// Resolve a required memory `key` argument, stripping any fence sentinels an
  /// AI client copied from a fenced response so the value round-trips to the
  /// stored key.
  func resolvedMemoryKey(
    from arguments: [String: Value], toolName: String
  ) -> ToolStringValidationResult {
    switch requiredTrimmedString(
      "key", from: arguments, message: "A non-empty memory key is required.", toolName: toolName
    ) {
    case .value(let value): return .value(SecurityFencing.unfence(value))
    case .error(let result): return .error(result)
    }
  }
}

extension ToolRegistry {
  func deleteMemoryResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let key: String
    switch resolvedMemoryKey(from: arguments, toolName: "delete_memory") {
    case .value(let value):
      key = value
    case .error(let result):
      return result
    }

    let outcome = try await deleteMemoryPayload(key: key)
    return deletedMemoryResult(key: key, deleted: outcome.deleted, previous: outcome.previous)
  }

  /// The uniform delete-return shape `{deleted, id, previous}` plus the
  /// domain-natural `key`. A memory's identity is its `key`, so `id` mirrors it;
  /// both are user-controlled free text and are fenced. `previous` carries the
  /// removed entry (content + key fenced) or null on a no-op.
  private func deletedMemoryResult(
    key: String, deleted: Bool, previous: Value?
  ) -> CallTool.Result {
    let fencedKey = SecurityFencing.fence(key)
    let fencedPrevious =
      previous.map { SecurityFencing.fenceMemoryKey(SecurityFencing.fenceValue($0)) } ?? .null
    return CallTool.Result(
      content: [
        .text(
          text: deleted ? "Deleted memory '\(key)'." : "Memory '\(key)' not found.",
          annotations: nil,
          _meta: nil
        )
      ],
      structuredContent: Optional.some(.object([
        "deleted": .bool(deleted),
        "id": .string(fencedKey),
        "previous": fencedPrevious,
        "key": .string(fencedKey),
      ])),
      isError: false
    )
  }
}
