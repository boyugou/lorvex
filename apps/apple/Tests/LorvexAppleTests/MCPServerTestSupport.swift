import Foundation
import MCP
import Synchronization

@testable import LorvexMCPHost

/// Frames an `MCPServer` sent, parsed once its `serve` returned.
final class MCPFrameRecorder: Sendable {
  private let frames = Mutex<[Data]>([])

  func send(_ frame: Data) {
    frames.withLock { $0.append(frame) }
  }

  var raw: [Data] { frames.withLock { $0 } }

  /// Every frame parsed as JSON; a frame that is not JSON is a test failure
  /// the caller sees as a missing response.
  var parsed: [Any] {
    raw.compactMap { try? JSONSerialization.jsonObject(with: $0) }
  }

  /// The response object answering request `id` (an `Int` or `String`).
  func response(id: AnyHashable) -> [String: Any]? {
    parsed.compactMap { $0 as? [String: Any] }.first { frame in
      if let number = frame["id"] as? Int, let wanted = id as? Int { return number == wanted }
      if let string = frame["id"] as? String, let wanted = id as? String { return string == wanted }
      return false
    }
  }
}

enum MCPServerHarness {
  static let info = MCPServer.ServerInfo(
    name: "lorvex-test", title: "Lorvex Test", version: "9.9.9", instructions: "Use the tools.")

  /// A server whose one tool, `echo`, returns its arguments as structured
  /// content, unless `call` replaces it.
  static func server(
    call: (@Sendable (CallTool.Parameters) async throws -> CallTool.Result)? = nil,
    clientIdentified: @escaping @Sendable (MCPClientIdentity) -> Void = { _ in }
  ) -> MCPServer {
    MCPServer(
      info: info,
      listTools: {
        [Tool(name: "echo", description: "Echoes its arguments", inputSchema: ["type": "object"])]
      },
      callTool: call ?? { params in
        CallTool.Result(
          content: [.text(text: params.name, annotations: nil, _meta: nil)],
          structuredContent: .object(params.arguments ?? [:]))
      },
      clientIdentified: clientIdentified)
  }

  /// Feeds `lines` to `server`, ends the input, and returns what it sent once
  /// `serve` returned.
  static func run(_ server: MCPServer, _ lines: [String]) async -> MCPFrameRecorder {
    let recorder = MCPFrameRecorder()
    let (stream, input) = AsyncStream.makeStream(of: Data.self)
    for line in lines { input.yield(Data(line.utf8)) }
    input.finish()
    await server.serve(stream, send: recorder.send)
    return recorder
  }

  /// `_meta` for a 2026-07-28 request, as a JSON fragment.
  static func modernMeta(
    version: String = MCPServer.modernProtocolVersion, clientName: String = "test-client"
  ) -> String {
    #"{"io.modelcontextprotocol/protocolVersion":"\#(version)","io.modelcontextprotocol/clientCapabilities":{},"io.modelcontextprotocol/clientInfo":{"name":"\#(clientName)","version":"1.0"}}"#
  }
}
