import Foundation
import MCP
import Synchronization
import Testing

@testable import LorvexMCPHost

/// The host's JSON-RPC layer over a stub tool: both protocol eras, the
/// JSON-RPC error cases, batches, cancellation and shutdown.
@Suite("MCP server protocol", .timeLimit(.minutes(1)))
struct MCPServerProtocolTests {
  typealias Harness = MCPServerHarness

  private func result(_ frame: [String: Any]?) throws -> [String: Any] {
    let frame = try #require(frame)
    return try #require(frame["result"] as? [String: Any], "\(frame)")
  }

  private func error(_ frame: [String: Any]?) throws -> [String: Any] {
    let frame = try #require(frame)
    return try #require(frame["error"] as? [String: Any], "\(frame)")
  }

  // MARK: Handshake protocol

  @Test("initialize negotiates the client's version and names the server")
  func initializeNegotiates() async throws {
    let sent = await Harness.run(
      Harness.server(),
      [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"experimental":{"codex/auth-change":{}}},"clientInfo":{"name":"codex","version":"0.1"}}}"#
      ])
    let initialized = try result(sent.response(id: 1))
    #expect(initialized["protocolVersion"] as? String == "2025-06-18")
    let serverInfo = try #require(initialized["serverInfo"] as? [String: Any])
    #expect(serverInfo["name"] as? String == "lorvex-test")
    #expect(serverInfo["title"] as? String == "Lorvex Test")
    #expect(serverInfo["version"] as? String == "9.9.9")
    #expect(initialized["instructions"] as? String == "Use the tools.")
    let tools = try #require((initialized["capabilities"] as? [String: Any])?["tools"] as? [String: Any])
    #expect(tools["listChanged"] as? Bool == false)
    #expect(initialized["resultType"] == nil)
  }

  @Test("an unknown requested version negotiates the newest handshake version")
  func initializeFallsBack() async throws {
    let sent = await Harness.run(
      Harness.server(),
      [#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}"#])
    #expect(try result(sent.response(id: 1))["protocolVersion"] as? String == Version.latest)
  }

  @Test("a second initialize is refused")
  func secondInitializeRefused() async throws {
    let initialize = #"{"jsonrpc":"2.0","id":ID,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}"#
    let server = Harness.server()
    let first = await Harness.run(server, [initialize.replacingOccurrences(of: "ID", with: "1")])
    _ = try result(first.response(id: 1))
    let second = await Harness.run(server, [initialize.replacingOccurrences(of: "ID", with: "2")])
    #expect(try error(second.response(id: 2))["code"] as? Int == -32600)
  }

  @Test("handshake results carry no 2026-07-28 fields, with or without initialize")
  func handshakeResultsArePlain() async throws {
    let sent = await Harness.run(
      Harness.server(),
      [
        #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo","arguments":{"a":1}}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#,
      ])
    let listed = try result(sent.response(id: 1))
    #expect((listed["tools"] as? [[String: Any]])?.first?["name"] as? String == "echo")
    for id in [1, 2, 3] {
      let body = try result(sent.response(id: id))
      #expect(body["resultType"] == nil && body["ttlMs"] == nil && body["_meta"] == nil, "\(body)")
    }
    #expect(try result(sent.response(id: 3)).isEmpty)
  }

  @Test("a string that looks like a data URL reaches the tool and comes back unchanged")
  func dataURLStringsStayStrings() async throws {
    let received = Mutex<Value?>(nil)
    let server = Harness.server(call: { params in
      received.withLock { $0 = params.arguments?["title"] }
      return CallTool.Result(
        content: [.text(text: "ok", annotations: nil, _meta: nil)],
        structuredContent: .object(["title": params.arguments?["title"] ?? .null]))
    })
    let sent = await Harness.run(
      server,
      [#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"title":"data:,hello"}}}"#])
    #expect(received.withLock { $0 } == .string("data:,hello"))
    let structured = try #require(try result(sent.response(id: 1))["structuredContent"] as? [String: Any])
    #expect(structured["title"] as? String == "data:,hello")
  }

  // MARK: 2026-07-28

  @Test("server/discover advertises 2026-07-28, tools, identity and cache hints")
  func discover() async throws {
    let sent = await Harness.run(
      Harness.server(),
      [#"{"jsonrpc":"2.0","id":"d","method":"server/discover","params":{"_meta":\#(Harness.modernMeta())}}"#])
    let discovered = try result(sent.response(id: "d"))
    #expect(discovered["resultType"] as? String == "complete")
    #expect(discovered["supportedVersions"] as? [String] == ["2026-07-28"])
    #expect((discovered["capabilities"] as? [String: Any])?["tools"] != nil)
    #expect(discovered["instructions"] as? String == "Use the tools.")
    #expect(discovered["ttlMs"] as? Int == MCPServer.cacheTTLMilliseconds)
    #expect(discovered["cacheScope"] as? String == "private")
    let meta = try #require(discovered["_meta"] as? [String: Any])
    let serverInfo = try #require(meta[MCPServer.serverInfoKey] as? [String: Any])
    #expect(serverInfo["name"] as? String == "lorvex-test")
    #expect(serverInfo["version"] as? String == "9.9.9")
  }

  @Test("2026-07-28 results carry resultType and identity; listings carry cache hints")
  func modernResults() async throws {
    let meta = Harness.modernMeta()
    let sent = await Harness.run(
      Harness.server(),
      [
        #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":\#(meta)}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"_meta":\#(meta),"name":"echo","arguments":{"a":1}}}"#,
      ])
    let listed = try result(sent.response(id: 1))
    #expect(listed["resultType"] as? String == "complete")
    #expect(listed["ttlMs"] as? Int == MCPServer.cacheTTLMilliseconds)
    #expect(listed["cacheScope"] as? String == "private")
    #expect((listed["tools"] as? [Any])?.count == 1)
    let called = try result(sent.response(id: 2))
    #expect(called["resultType"] as? String == "complete")
    #expect(called["ttlMs"] == nil)
    #expect((called["structuredContent"] as? [String: Any])?["a"] as? Int == 1)
    #expect((called["_meta"] as? [String: Any])?[MCPServer.serverInfoKey] != nil)
  }

  @Test("a tool result's own _meta keeps its fields beside the server's identity")
  func toolMetaIsMerged() async throws {
    let server = Harness.server(call: { _ in
      CallTool.Result(
        content: [], _meta: Metadata(additionalFields: ["com.example/trace": "t1"]))
    })
    let sent = await Harness.run(
      server,
      [
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"_meta":\#(Harness.modernMeta()),"name":"echo"}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo"}}"#,
      ])
    let modernMeta = try #require(try result(sent.response(id: 1))["_meta"] as? [String: Any])
    #expect(modernMeta["com.example/trace"] as? String == "t1")
    #expect(modernMeta[MCPServer.serverInfoKey] != nil)
    let handshakeMeta = try #require(try result(sent.response(id: 2))["_meta"] as? [String: Any])
    #expect(handshakeMeta.keys.sorted() == ["com.example/trace"])
  }

  @Test("an unsupported version is refused with the supported list")
  func unsupportedVersion() async throws {
    let sent = await Harness.run(
      Harness.server(),
      [
        #"{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":\#(Harness.modernMeta(version: "2099-01-01"))}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":\#(Harness.modernMeta(version: "2025-11-25"))}}"#,
      ])
    for (id, requested) in [(1, "2099-01-01"), (2, "2025-11-25")] {
      let refused = try error(sent.response(id: id))
      #expect(refused["code"] as? Int == -32022)
      let data = try #require(refused["data"] as? [String: Any])
      #expect(data["supported"] as? [String] == ["2026-07-28"])
      #expect(data["requested"] as? String == requested)
    }
  }

  @Test("malformed 2026-07-28 metadata is invalid params", arguments: [
    // server/discover without metadata
    #"{"jsonrpc":"2.0","id":1,"method":"server/discover"}"#,
    // a version without client capabilities
    #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}"#,
    // client capabilities that are not an object
    #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":[]}}}"#,
    // client capabilities without a version
    #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/clientCapabilities":{}}}}"#,
    // client information alone
    #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/clientInfo":{"name":"c","version":"1"}}}}"#,
    // a version that is not a string
    #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":20260728,"io.modelcontextprotocol/clientCapabilities":{}}}}"#,
    // tools/call without a name
    #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"arguments":{}}}"#,
    // tools/call arguments that are not an object
    #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":[1]}}"#,
    // params that are not an object
    #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":[1]}"#,
  ])
  func invalidParams(line: String) async throws {
    let sent = await Harness.run(Harness.server(), [line])
    #expect(try error(sent.response(id: 1))["code"] as? Int == -32602)
  }

  @Test("a client named in 2026-07-28 metadata is reported once")
  func modernClientIdentified() async throws {
    let clients = Mutex<[MCPClientIdentity]>([])
    let server = Harness.server(clientIdentified: { client in clients.withLock { $0.append(client) } })
    _ = await Harness.run(
      server,
      [
        #"{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":\#(Harness.modernMeta(clientName: "claude-code"))}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":\#(Harness.modernMeta(clientName: "claude-code"))}}"#,
      ])
    #expect(clients.withLock { $0 } == [MCPClientIdentity(name: "claude-code", title: nil, version: "1.0")])
  }

  @Test("a client whose server/discover probe is refused can still fall back to initialize")
  func probeThenInitialize() async throws {
    let sent = await Harness.run(
      Harness.server(),
      [
        #"{"jsonrpc":"2.0","id":0,"method":"server/discover","params":{"_meta":\#(Harness.modernMeta(version: "2027-01-01"))}}"#,
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
      ])
    #expect(try error(sent.response(id: 0))["code"] as? Int == -32022)
    #expect(try result(sent.response(id: 1))["protocolVersion"] as? String == "2025-06-18")
    #expect(try result(sent.response(id: 2))["resultType"] == nil)
  }

  // MARK: JSON-RPC

  @Test("JSON-RPC errors carry the request's id, or no id when it is unreadable")
  func jsonRPCErrors() async throws {
    let sent = await Harness.run(
      Harness.server(),
      [
        #"{"jsonrpc":"2.0","id":"x","method":"resources/list"}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"logging/setLevel","params":{"level":"debug"}}"#,
        #"{"id":3,"method":"tools/list"}"#,
        #"{"jsonrpc":"2.0","id":4}"#,
        #"{"jsonrpc":"2.0","id":null,"method":"tools/list"}"#,
        #"{"jsonrpc":"2.0","id":1.5,"method":"tools/list"}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"#,
      ])
    #expect(try error(sent.response(id: "x"))["code"] as? Int == -32601)
    #expect(try error(sent.response(id: 2))["code"] as? Int == -32601)
    #expect(try error(sent.response(id: 3))["code"] as? Int == -32600)
    #expect(try error(sent.response(id: 4))["code"] as? Int == -32600)
    let unidentified = sent.parsed.compactMap { $0 as? [String: Any] }.filter { $0["id"] == nil }
    #expect(unidentified.compactMap { ($0["error"] as? [String: Any])?["code"] as? Int }.sorted()
      == [-32700, -32600, -32600])
  }

  @Test("notifications and client responses get no reply")
  func notificationsAreSilent() async {
    let sent = await Harness.run(
      Harness.server(),
      [
        #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
        #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":99}}"#,
        #"{"jsonrpc":"2.0","method":"tools/list","params":[1]}"#,
        #"{"jsonrpc":"2.0","id":7,"result":{}}"#,
      ])
    #expect(sent.raw.isEmpty)
  }

  @Test("a batch is answered with one array, notifications left out")
  func batch() async throws {
    let sent = await Harness.run(
      Harness.server(),
      [
        #"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":2,"method":"nope"}]"#,
        "[]",
      ])
    let arrays = sent.parsed.compactMap { $0 as? [[String: Any]] }
    #expect(arrays.count == 1)
    let answered = try #require(arrays.first)
    #expect(answered.compactMap { $0["id"] as? Int }.sorted() == [1, 2])
    #expect(answered.first { $0["id"] as? Int == 2 }?["error"] != nil)
    let empty = sent.parsed.compactMap { $0 as? [String: Any] }
    #expect(empty.count == 1 && (empty.first?["error"] as? [String: Any])?["code"] as? Int == -32600)
  }

  @Test("each frame is one line of compact JSON with unescaped slashes")
  func framesAreSingleLines() async throws {
    let server = Harness.server(call: { _ in
      CallTool.Result(content: [.text(text: "a/b\nc", annotations: nil, _meta: nil)])
    })
    let sent = await Harness.run(
      server, [#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo"}}"#])
    let frame = try #require(sent.raw.first)
    #expect(!frame.contains(0x0A))
    let text = String(decoding: frame, as: UTF8.self)
    #expect(text.hasPrefix(#"{"id":1,"jsonrpc":"2.0","result":"#))
    #expect(text.contains(#"a/b\nc"#))
  }

  // MARK: Cancellation and shutdown

  @Test("a cancelled call is cancelled and gets no response, and later requests still do")
  func cancellation() async throws {
    let (started, callStarted) = AsyncStream.makeStream(of: Void.self)
    let sawCancellation = Mutex(false)
    let server = Harness.server(call: { _ in
      callStarted.yield()
      do {
        try await Task.sleep(for: .seconds(30))
      } catch is CancellationError {
        sawCancellation.withLock { $0 = true }
        throw CancellationError()
      }
      return CallTool.Result(content: [])
    })
    let recorder = MCPFrameRecorder()
    let (lines, input) = AsyncStream.makeStream(of: Data.self)
    let serving = Task { await server.serve(lines, send: recorder.send) }
    input.yield(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo"}}"#.utf8))
    for await _ in started { break }
    input.yield(Data(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#.utf8))
    input.yield(Data(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#.utf8))
    input.finish()
    await serving.value
    #expect(sawCancellation.withLock { $0 })
    #expect(recorder.response(id: 1) == nil)
    #expect(recorder.response(id: 2) != nil)
  }

  @Test("an id reused after a cancellation is answered, and a late cancellation changes nothing")
  func cancelledIDReused() async throws {
    let (started, callStarted) = AsyncStream.makeStream(of: Void.self)
    let server = Harness.server(call: { _ in
      callStarted.yield()
      try await Task.sleep(for: .seconds(30))
      return CallTool.Result(content: [])
    })
    let recorder = MCPFrameRecorder()
    let (written, frameWritten) = AsyncStream.makeStream(of: Void.self)
    let (lines, input) = AsyncStream.makeStream(of: Data.self)
    let serving = Task {
      await server.serve(lines, send: { frame in
        recorder.send(frame)
        frameWritten.yield()
      })
    }
    input.yield(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo"}}"#.utf8))
    for await _ in started { break }
    input.yield(Data(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#.utf8))
    input.yield(Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8))
    var frames = written.makeAsyncIterator()
    _ = await frames.next()
    input.yield(Data(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#.utf8))
    input.yield(Data(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#.utf8))
    input.finish()
    await serving.value
    #expect(recorder.raw.count == 2)
    _ = try result(recorder.response(id: 1))
    _ = try result(recorder.response(id: 2))
  }

  @Test("serve returns only after a request running at end of input has answered")
  func shutdownWaitsForRunningRequests() async throws {
    let server = Harness.server(call: { _ in
      try await Task.sleep(for: .milliseconds(200))
      return CallTool.Result(content: [.text(text: "done", annotations: nil, _meta: nil)])
    })
    let sent = await Harness.run(
      server, [#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo"}}"#])
    #expect(try result(sent.response(id: 1))["content"] != nil)
  }

  @Test("a tool that throws becomes an internal error for that request only")
  func toolFailure() async throws {
    struct Boom: Error {}
    let sent = await Harness.run(
      Harness.server(call: { _ in throw Boom() }),
      [
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo"}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#,
      ])
    #expect(try error(sent.response(id: 1))["code"] as? Int == -32603)
    _ = try result(sent.response(id: 2))
  }
}
