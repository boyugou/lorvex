import MCP

extension ToolRegistry {
  func sessionContextResult() async throws -> CallTool.Result {
    let structured = try await coreBridge.loadSessionContext()
    return fencedReadResult(text: "Loaded Lorvex session context.", value: structured)
  }
}
