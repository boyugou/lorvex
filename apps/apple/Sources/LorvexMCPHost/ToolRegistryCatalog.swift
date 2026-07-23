import MCP

extension ToolRegistry {
  /// The complete tool catalog, derived from the same typed definitions used
  /// for dispatch and cross-cutting policy enforcement.
  static func listTools() -> [Tool] {
    ToolDefinitionRegistry.all.map(\.tool)
  }
}
