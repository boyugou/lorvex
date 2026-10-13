import MCP

extension ToolRegistry {
  func aiChangelogResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let structured = try await coreBridge.loadAIChangelog(
      limit: try StrictScalarArguments.optionalInt(arguments["limit"], field: "limit"),
      offset: try StrictScalarArguments.optionalInt(arguments["offset"], field: "offset"),
      entityType: try StrictScalarArguments.optionalString(
        arguments["entity_type"], field: "entity_type"),
      operation: try StrictScalarArguments.optionalString(
        arguments["operation"], field: "operation"),
      entityID: try StrictScalarArguments.optionalString(
        arguments["entity_id"], field: "entity_id"),
      since: try StrictScalarArguments.optionalString(arguments["since"], field: "since")
    )
    return fencedReadResult(text: "Loaded Lorvex AI changelog.", value: structured)
  }

  func undoAIChangeResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let changelogID = arguments["changelog_id"]?.stringValue, !changelogID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A changelog_id is required.", toolName: "undo_ai_change")
    }
    let value = try await coreBridge.undoAIChange(changelogID: changelogID)
    let reverted = value.objectValue?["reverted"]?.arrayValue?.compactMap(\.stringValue) ?? []
    let subject = value.objectValue?["entity_type"]?.stringValue == "calendar_event" ? "event" : "task"
    let text =
      reverted.isEmpty
      ? "Nothing to undo: the \(subject) already differs from that change everywhere."
      : "Undid the change: restored \(reverted.joined(separator: ", "))."
    return successResult(text: text, value: value)
  }

  func recentLogsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let structured = try await coreBridge.loadRecentLogs(
      limit: try StrictScalarArguments.optionalInt(arguments["limit"], field: "limit"),
      offset: try StrictScalarArguments.optionalInt(arguments["offset"], field: "offset"),
      since: try StrictScalarArguments.optionalString(arguments["since"], field: "since"),
      level: try StrictScalarArguments.optionalString(arguments["level"], field: "level"),
      levels: try StrictArgumentArray.optionalStrings(arguments["levels"], field: "levels"),
      source: try StrictScalarArguments.optionalString(arguments["source"], field: "source"),
      sources: try StrictArgumentArray.optionalStrings(arguments["sources"], field: "sources"),
      includeDetails: try StrictScalarArguments.optionalBool(
        arguments["include_details"], field: "include_details"),
      redact: try StrictScalarArguments.optionalBool(arguments["redact"], field: "redact")
    )
    return fencedReadResult(text: "Loaded Lorvex recent logs.", value: structured)
  }
}
