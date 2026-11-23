import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// The MCP schema lets a client describe an experimental capability as any JSON
/// object, and Codex Desktop declares `"codex/auth-change": {}`. The Swift SDK
/// decodes `capabilities.experimental` as a map of strings, so on its own it
/// answers such a client's `initialize` with error -32603 and no tool can run.
/// The host's transport removes the field, which Lorvex never reads.
@Suite("MCP initialize with unfamiliar client capabilities", .timeLimit(.minutes(1)))
struct MCPInitializeCapabilityTests {
  /// An `initialize` request shaped like Codex Desktop's, with its
  /// experimental capability and a second, unfamiliar one holding nested
  /// objects and arrays.
  static let initialize = #"""
    {"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"elicitation":{},"roots":{"listChanged":true},"experimental":{"codex/auth-change":{},"example.org/nested":{"version":2,"options":{"mode":"full","flags":["a","b"]}}}},"clientInfo":{"name":"codex-mcp-client","title":"Codex","version":"0.64.0"}}}
    """#

  private func json(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  // MARK: The filter

  @Test("initialize loses only its experimental capabilities")
  func removesOnlyExperimental() throws {
    let filtered = try json(InitializeCapabilityFilter.filtered(Data(Self.initialize.utf8)))
    let original = try json(Data(Self.initialize.utf8))
    let params = try #require(filtered["params"] as? [String: Any])
    let capabilities = try #require(params["capabilities"] as? [String: Any])
    #expect(capabilities["experimental"] == nil)
    #expect(capabilities["elicitation"] != nil)
    #expect((capabilities["roots"] as? [String: Any])?["listChanged"] as? Bool == true)
    #expect(params["protocolVersion"] as? String == "2025-06-18")
    #expect((params["clientInfo"] as? [String: Any])?["name"] as? String == "codex-mcp-client")
    #expect(filtered["id"] as? Int == 0)
    #expect(filtered["method"] as? String == "initialize")
    #expect(Set(filtered.keys) == Set(original.keys))
  }

  @Test("every other message passes through byte for byte", arguments: [
    // initialize without experimental capabilities
    #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}"#,
    // a tool call whose argument names the method
    #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"\"initialize\" the repo","experimental":{}}}}"#,
    // another method whose params hold the same shape
    #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"initialize","capabilities":{"experimental":{"x":{}}}}}"#,
    // a batch
    #"[{"jsonrpc":"2.0","id":3,"method":"initialize","params":{"capabilities":{"experimental":{"x":{}}}}}]"#,
    // malformed
    #"{"method":"initialize","params":{"capabilities":{"experimental":{"#,
  ])
  func passesOthersThrough(message: String) {
    let data = Data(message.utf8)
    #expect(InitializeCapabilityFilter.filtered(data) == data)
  }

  // MARK: The host's server, end to end

  /// Runs the host's server over an in-memory connection, through the host's
  /// transport when `tolerant`, and returns the client side.
  private func connect(tolerant: Bool) async throws -> (Server, InMemoryTransport) {
    let (client, serverSide) = await InMemoryTransport.createConnectedPair()
    let core = try await makeSeededInMemoryCore()
    let registry = ToolRegistry(
      coreBridge: CoreBridgeClient(databasePath: "/tmp/lorvex-test.sqlite", service: core))
    let server = await LorvexMCPHost.makeServer(
      registry: registry, activity: AssistantActivityRecorder(service: core))
    let transport: any Transport =
      tolerant
      ? ClientCapabilityTolerantTransport(wrapping: serverSide, logger: serverSide.logger)
      : serverSide
    try await server.start(transport: transport)
    try await client.connect()
    return (server, client)
  }

  /// Sends `message` and returns the response carrying `id`.
  private func exchange(
    _ client: InMemoryTransport,
    _ responses: inout AsyncThrowingStream<Data, Error>.AsyncIterator,
    _ message: String, id: Int
  ) async throws -> [String: Any] {
    try await client.send(Data(message.utf8))
    while let data = try await responses.next() {
      let response = try json(data)
      if response["id"] as? Int == id { return response }
    }
    Issue.record("the connection ended before response \(id)")
    return [:]
  }

  @Test("a client declaring object-valued experimental capabilities lists and calls tools")
  func codexHandshakeSucceeds() async throws {
    let (server, client) = try await connect(tolerant: true)
    var responses = await client.receive().makeAsyncIterator()

    let initialized = try await exchange(client, &responses, Self.initialize, id: 0)
    #expect(initialized["error"] == nil, "\(initialized)")
    let result = try #require(initialized["result"] as? [String: Any])
    #expect((result["serverInfo"] as? [String: Any])?["name"] != nil)
    try await client.send(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))

    let listed = try await exchange(
      client, &responses, #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#, id: 1)
    let tools = try #require((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])
    #expect(tools.contains { $0["name"] as? String == "get_overview" })

    let called = try await exchange(
      client, &responses,
      #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_overview","arguments":{}}}"#,
      id: 2)
    let overview = try #require(called["result"] as? [String: Any], "\(called)")
    #expect(overview["isError"] as? Bool != true)
    #expect(overview["structuredContent"] is [String: Any])
    await server.stop()
  }

  @Test("the host's connection ends when the client disconnects")
  func connectionEndsWithTheClient() async throws {
    let (server, client) = try await connect(tolerant: true)
    var responses = await client.receive().makeAsyncIterator()
    _ = try await exchange(client, &responses, Self.initialize, id: 0)
    await client.disconnect()
    // The host exits when this returns; a transport that never ends its stream
    // would leave the helper running after the assistant quits.
    await server.waitUntilCompleted()
  }

  /// Fails once the SDK decodes object-valued experimental capabilities
  /// itself; then the host's transport filter can go.
  @Test("the SDK alone still refuses that handshake")
  func sdkAloneRefusesIt() async throws {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        Client.Capabilities.self, from: Data(#"{"experimental":{"a":{}}}"#.utf8))
    }
    let (server, client) = try await connect(tolerant: false)
    var responses = await client.receive().makeAsyncIterator()
    let initialized = try await exchange(client, &responses, Self.initialize, id: 0)
    #expect(initialized["error"] != nil, "\(initialized)")
    await server.stop()
  }
}
