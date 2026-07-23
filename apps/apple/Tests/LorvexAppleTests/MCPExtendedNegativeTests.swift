import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

// MARK: - Helpers (file-private to avoid collision with MCPToolRegistryTests)

private func xcall(
  _ registry: ToolRegistry,
  tool name: String,
  arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}

private func xtext(_ result: CallTool.Result) -> String {
  result.content.compactMap {
    if case .text(let t, _, _) = $0 { return t }
    return nil
  }.joined()
}

// MARK: - Negative / Error Contract

@Suite("MCP Extended — negative cases")
struct ExtendedNegativeCases {

  @Test("unknown tool returns isError true with Unknown tool message")
  func unknownToolIsError() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(registry, tool: "nonexistent_extended_tool_abc123")
    #expect(result.isError == true)
    #expect(xtext(result).contains("Unknown tool"))
  }

  @Test("missing required arg errors are structured across multiple tools")
  func missingArgErrorsAreStructured() async throws {
    let registry = try mcpInMemoryRegistry()
    let toolsWithRequiredArgs: [(String, [String: Value])] = [
      ("delete_calendar_event", [:]),
      ("link_task_to_provider_event", [:]),
      ("set_task_recurrence", [:]),
      ("remove_task_recurrence", [:]),
      ("add_task_recurrence_exception", [:]),
    ]
    for (toolName, args) in toolsWithRequiredArgs {
      let result = try await xcall(registry, tool: toolName, arguments: args)
      #expect(
        result.isError == true,
        "Tool '\(toolName)' should return isError true for missing args"
      )
    }
  }
}
