import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

/// Real MCP registry over the real core service on a fresh, empty in-memory
/// GRDB store — the default backend for MCP behavioral tests. Only the
/// schema-seeded sentinel Inbox exists; tests create the fixtures they assert
/// on through the tools themselves.
func mcpInMemoryRegistry() throws -> ToolRegistry {
  try mcpInMemoryRegistryWithService().registry
}

/// ``mcpInMemoryRegistry()`` plus a handle on the backing service, for tests
/// whose fixtures need core surfaces the MCP tools don't expose (e.g. the
/// EventKit provider mirror).
func mcpInMemoryRegistryWithService() throws -> (
  registry: ToolRegistry, service: SwiftLorvexCoreService
) {
  let service = try makeInMemoryCore()
  return (ToolRegistry(coreBridge: CoreBridgeClient(databasePath: nil, service: service)), service)
}

/// Real MCP registry over a real in-memory core pre-populated with the fixed
/// preview dataset (`LorvexPreviewCoreFactory.makeSeeded`); fixture rows are
/// addressed through `LorvexPreviewSeedID`.
func mcpSeededRegistry() async throws -> ToolRegistry {
  ToolRegistry(
    coreBridge: CoreBridgeClient(databasePath: nil, service: try await makeSeededInMemoryCore()))
}

func mcpRegistryCall(
  _ registry: ToolRegistry,
  tool name: String,
  arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}

func mcpTextContent(_ result: CallTool.Result) -> String {
  result.content.compactMap {
    if case .text(let text, _, _) = $0 { return text }
    return nil
  }.joined()
}

func expectMCPStructuredError(
  _ result: CallTool.Result,
  code: String,
  tool: String,
  message: String? = nil
) {
  #expect(result.isError == true)
  let structured = result.structuredContent?.objectValue
  #expect(structured?["code"]?.stringValue == code)
  #expect(structured?["tool"]?.stringValue == tool)
  if let message {
    #expect(structured?["message"]?.stringValue == SecurityFencing.fence(message))
  }
}

func mcpOnDiskRegistry(
  dbPath: String? = nil
) -> (registry: ToolRegistry, dbPath: String, cleanup: () -> Void) {
  let directory: URL?
  let resolvedDBPath: String
  if let dbPath {
    directory = nil
    resolvedDBPath = dbPath
  } else {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-mcp-ondisk-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    directory = tempDirectory
    resolvedDBPath = tempDirectory.appendingPathComponent("db.sqlite").path
  }
  let service = SwiftLorvexCoreService(databasePath: resolvedDBPath)
  let bridge = CoreBridgeClient(databasePath: resolvedDBPath, service: service)
  return (
    ToolRegistry(coreBridge: bridge),
    resolvedDBPath,
    {
      if let directory {
        try? FileManager.default.removeItem(at: directory)
      }
    }
  )
}
