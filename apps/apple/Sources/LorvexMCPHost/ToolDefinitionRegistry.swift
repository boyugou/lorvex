import MCP

enum ToolDefinitionRegistry {
  /// Domain files own the definitions; sorting retains the pre-refactor
  /// `tools/list` order as part of the frozen wire contract.
  static let all: [ToolDefinition] = (
    TaskToolDefinitions.all
      + ContentToolDefinitions.all
      + FocusToolDefinitions.all
      + HabitToolDefinitions.all
      + SystemToolDefinitions.all
  ).sorted { $0.listingOrder < $1.listingOrder }

  static let byName: [String: ToolDefinition] = {
    var definitions: [String: ToolDefinition] = [:]
    definitions.reserveCapacity(all.count)
    for definition in all {
      precondition(
        definitions.updateValue(definition, forKey: definition.tool.name) == nil,
        "Duplicate MCP tool definition: \(definition.tool.name)"
      )
    }
    return definitions
  }()

  static let idempotentWriteToolNames = Set(
    all.lazy
      .filter(\.participatesInIdempotency)
      .map { $0.tool.name }
  )
}
