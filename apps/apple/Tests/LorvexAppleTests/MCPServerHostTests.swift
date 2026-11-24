import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

/// The host's server over the real tool registry and an in-memory core: the
/// handshakes real clients send, the catalog as the SDK encodes it, and
/// strings that `MCP.Value`'s own decoder would have turned into binary data.
@Suite("MCP server over the tool registry", .timeLimit(.minutes(1)))
struct MCPServerHostTests {
  /// An `initialize` request shaped like Codex Desktop's, with its
  /// experimental capability and a second, unfamiliar one holding nested
  /// objects and arrays. The SDK's `Client.Capabilities` cannot decode it.
  static let codexInitialize = #"""
    {"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"elicitation":{},"roots":{"listChanged":true},"experimental":{"codex/auth-change":{},"example.org/nested":{"version":2,"options":{"mode":"full","flags":["a","b"]}}}},"clientInfo":{"name":"codex-mcp-client","title":"Codex","version":"0.64.0"}}}
    """#

  private func makeServer() async throws -> MCPServer {
    let core = try await makeSeededInMemoryCore()
    let registry = ToolRegistry(
      coreBridge: CoreBridgeClient(databasePath: "/tmp/lorvex-test.sqlite", service: core))
    return LorvexMCPHost.makeServer(
      registry: registry, activity: AssistantActivityRecorder(service: core))
  }

  private func result(_ frame: [String: Any]?) throws -> [String: Any] {
    let frame = try #require(frame)
    return try #require(frame["result"] as? [String: Any], "\(frame)")
  }

  @Test("a Codex-shaped handshake lists and calls tools")
  func codexHandshake() async throws {
    let sent = await MCPServerHarness.run(
      try await makeServer(),
      [
        Self.codexInitialize,
        #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_overview","arguments":{}}}"#,
      ])
    let initialized = try result(sent.response(id: 0))
    #expect((initialized["serverInfo"] as? [String: Any])?["name"] as? String
      == LorvexProductMetadata.mcpServerName)
    let tools = try #require(try result(sent.response(id: 1))["tools"] as? [[String: Any]])
    #expect(tools.count == ToolRegistry.listTools().count)
    #expect(tools.contains { $0["name"] as? String == "get_overview" })
    let overview = try result(sent.response(id: 2))
    #expect(overview["isError"] as? Bool != true)
    #expect(overview["structuredContent"] is [String: Any])
  }

  @Test("the handshake catalog is the SDK's own encoding of the tool list")
  func catalogMatchesSDKEncoding() async throws {
    let sent = await MCPServerHarness.run(
      try await makeServer(), [#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#])
    let served = try result(sent.response(id: 1))
    let expected = try #require(
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ListTools.Result(tools: ToolRegistry.listTools())))
        as? [String: Any])
    #expect(NSDictionary(dictionary: served).isEqual(to: expected))
  }

  @Test("a 2026-07-28 client lists and calls tools")
  func modernClient() async throws {
    let meta = MCPServerHarness.modernMeta(clientName: "claude-code")
    let sent = await MCPServerHarness.run(
      try await makeServer(),
      [
        #"{"jsonrpc":"2.0","id":0,"method":"server/discover","params":{"_meta":\#(meta)}}"#,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":\#(meta)}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"_meta":\#(meta),"name":"get_overview","arguments":{}}}"#,
      ])
    #expect(try result(sent.response(id: 0))["instructions"] as? String == MCPHostInstructions.text)
    #expect((try result(sent.response(id: 1))["tools"] as? [Any])?.count
      == ToolRegistry.listTools().count)
    let overview = try result(sent.response(id: 2))
    #expect(overview["resultType"] as? String == "complete")
    #expect(overview["structuredContent"] is [String: Any])
  }

  @Test("a task titled like a data URL keeps its title in and out")
  func dataURLTitle() async throws {
    let server = try await makeServer()
    let created = await MCPServerHarness.run(
      server,
      [#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"data:,hello"}}}"#])
    let task = try #require(try result(created.response(id: 1))["structuredContent"] as? [String: Any])
    #expect((task["title"] as? String)?.contains("data:,hello") == true, "\(task)")
    let id = try #require(task["id"] as? String)

    let read = await MCPServerHarness.run(
      server,
      [#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_task","arguments":{"id":"\#(id)"}}}"#])
    let frame = String(decoding: try #require(read.raw.first), as: UTF8.self)
    #expect(frame.contains("data:,hello"), "\(frame)")
    #expect(!frame.contains("base64"), "\(frame)")
  }

  @Test("a replayed idempotent result keeps a string that looks like a data URL")
  func durableReplayKeepsStrings() {
    let structured: Value = .object(["title": .string("data:,hello")])
    let original = IdempotencyCache.CachedResult(textContent: "ok", structuredContent: structured)
    let restored = IdempotencyCache.CachedResult.fromDurablePayload(original.durablePayload())
    #expect(restored.structuredContent as? Value == structured)
  }
}
