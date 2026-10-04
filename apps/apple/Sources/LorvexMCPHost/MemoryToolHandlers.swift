import Foundation
import MCP

extension ToolRegistry {
  func memoryResult(arguments: [String: Value] = [:]) async throws -> CallTool.Result {
    let entries = try await memoryPayloads()
    let requestedKeys = try memoryRequestedKeys(arguments: arguments)
    let limit = try PagingArguments.limit(arguments, default: 20, maximum: 100)
    let offset = try PagingArguments.offset(arguments)
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

  /// Trim `raw` and insert it when non-empty.
  private func insertMemoryKey(_ raw: String?, into keys: inout Set<String>) {
    guard let raw else { return }
    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if !key.isEmpty { keys.insert(key) }
  }

  func writeMemoryResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let key = (try StrictScalarArguments.optionalString(arguments["key"], field: "key") ?? "")
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
    let oldKey = (try StrictScalarArguments.optionalString(arguments["old_key"], field: "old_key") ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let newKey = (try StrictScalarArguments.optionalString(arguments["new_key"], field: "new_key") ?? "")
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
