import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

func contentCall(
  _ registry: ToolRegistry,
  tool name: String,
  arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}
