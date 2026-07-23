import MCP

extension ToolRegistry {
  func guideResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let structured = try await coreBridge.loadGuide(
      topic: try StrictScalarArguments.optionalString(arguments["topic"], field: "topic"))
    return fencedReadResult(text: "Loaded Lorvex guide.", value: structured)
  }
}
