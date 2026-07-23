import Foundation
import MCP

extension ToolRegistry {
  func memoryResult(arguments: [String: Value] = [:]) async throws -> CallTool.Result {
    let entries = try await memoryPayloads()
    let requestedKeys = try memoryRequestedKeys(arguments: arguments)
    let limit = max(
      1, min(try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 20), 100))
    let offset = max(
      0, try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0))
    let filtered = entries.filter { entry in
      guard !requestedKeys.isEmpty else { return true }
      guard let key = entry.objectValue?["key"]?.stringValue else { return false }
      return requestedKeys.contains(key)
    }
    // The full entry list is in memory, so the total is exact; page it rather
    // than silently clipping anything past the limit.
    let page = Array(filtered.dropFirst(offset).prefix(limit))
    let truncated = filtered.count > offset + page.count
    let payload = MCPPagination.object(
      domain: ["entries": .array(page.map(SecurityFencing.fenceMemoryKey))],
      totalMatching: filtered.count, returned: page.count, limit: limit,
      offset: offset, nextOffset: truncated ? offset + page.count : nil, truncated: truncated)
    return CallTool.Result(
      content: [
        .text(
          text: "Loaded \(page.count) memory entr\(page.count == 1 ? "y" : "ies").",
          annotations: nil, _meta: nil)
      ],
      // `fenceMemoryKey` above fences the AI-supplied memory keys (which the
      // central walker deliberately skips); the dispatch layer fences the value
      // fields, so no generic `fenceValue` is needed here.
      structuredContent: Optional.some(payload),
      isError: false
    )
  }

  private func memoryRequestedKeys(arguments: [String: Value]) throws -> Set<String> {
    var keys = Set<String>()
    insertMemoryKey(
      try StrictScalarArguments.optionalString(arguments["key"], field: "key"), into: &keys)
    if let keyList = try StrictArgumentArray.optionalStrings(arguments["keys"], field: "keys") {
      for value in keyList {
        insertMemoryKey(value, into: &keys)
      }
    }
    return keys
  }

  /// Strip any fence sentinels (a client may echo a fenced key verbatim), trim,
  /// and insert when non-empty — so a fenced key resolves back to its stored form.
  private func insertMemoryKey(_ raw: String?, into keys: inout Set<String>) {
    guard let raw else { return }
    let key = SecurityFencing.unfence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    if !key.isEmpty { keys.insert(key) }
  }

  func writeMemoryResult(arguments: [String: Value]) async throws -> CallTool.Result {
    // Strip fence sentinels before validating/storing so a client echoing a
    // fenced key writes the original key, not a doubly-wrapped variant.
    let key = SecurityFencing.unfence(
      try StrictScalarArguments.optionalString(arguments["key"], field: "key") ?? ""
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A non-empty memory key is required.",
        toolName: "write_memory")
    }
    guard let content = arguments["content"]?.stringValue else {
      return Self.errorResult(
        code: "validation", message: "A memory content value is required.",
        toolName: "write_memory")
    }

    let value = try await upsertMemoryPayload(key: key, content: content)
    return successResult(text: "Wrote memory: \(key)", value: SecurityFencing.fenceMemoryKey(value))
  }

  func renameMemoryResult(arguments: [String: Value]) async throws -> CallTool.Result {
    // Strip fence sentinels before validating/storing so a client echoing fenced
    // keys renames the original keys, not doubly-wrapped variants.
    let oldKey = SecurityFencing.unfence(
      try StrictScalarArguments.optionalString(arguments["old_key"], field: "old_key") ?? ""
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    let newKey = SecurityFencing.unfence(
      try StrictScalarArguments.optionalString(arguments["new_key"], field: "new_key") ?? ""
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !oldKey.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A non-empty old_key is required.", toolName: "rename_memory")
    }
    guard !newKey.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A non-empty new_key is required.", toolName: "rename_memory")
    }
    let content = try StrictScalarArguments.optionalString(arguments["content"], field: "content")
    let value = try await renameMemoryPayload(oldKey: oldKey, newKey: newKey, content: content)
    return successResult(
      text: "Renamed memory: \(oldKey) → \(newKey)",
      value: SecurityFencing.fenceMemoryKey(value))
  }
}
