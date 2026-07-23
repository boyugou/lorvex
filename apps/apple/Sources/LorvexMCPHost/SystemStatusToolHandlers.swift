import MCP

extension ToolRegistry {
  func syncStatusResult() async throws -> CallTool.Result {
    let structured = try await coreBridge.loadSyncStatus()
    return fencedReadResult(text: "Loaded Lorvex sync status.", value: structured)
  }

  func setupStatusResult() async throws -> CallTool.Result {
    let structured = try await coreBridge.loadSetupStatus()
    return fencedReadResult(text: "Loaded Lorvex setup status.", value: structured)
  }
}
