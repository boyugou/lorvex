import Foundation
import MCP
import Synchronization

/// Who an MCP client says it is, from `initialize` or from a 2026-07-28
/// request's `_meta`.
struct MCPClientIdentity: Sendable, Equatable {
  let name: String
  let title: String?
  let version: String?
}

/// Lorvex's MCP server: JSON-RPC dispatch for tools, over any line channel.
///
/// One process serves both eras of the protocol, chosen per request:
///
/// - `initialize` starts the handshake-based protocol (2025-11-25 and
///   earlier), negotiating the client's version when known and 2025-11-25
///   otherwise. A request without 2026-07-28 metadata is served under that
///   protocol, with or without a prior `initialize`.
/// - A request whose `params._meta` names `io.modelcontextprotocol/
///   protocolVersion` is a 2026-07-28 request. The version must be
///   ``modernProtocolVersion`` (otherwise error -32022 listing it) and
///   `io.modelcontextprotocol/clientCapabilities` must be an object
///   (otherwise -32602). `server/discover` is answered only in this protocol.
///   Its results add `resultType: "complete"` and the server's identity under
///   `_meta`; `tools/list` and `server/discover` add a five-minute `ttlMs` and
///   `cacheScope: "private"`.
///
/// Older-protocol results are the SDK types' own encoding. Each request runs
/// in its own task; `notifications/cancelled` cancels one, and a cancelled
/// request gets no response. ``serve(_:send:)`` returns when its input ends
/// and every running request has answered.
final class MCPServer: Sendable {
  /// What `initialize` and `server/discover` report about Lorvex.
  struct ServerInfo: Sendable {
    let name: String
    let title: String
    let version: String
    let instructions: String
  }

  static let modernProtocolVersion = "2026-07-28"
  static let cacheTTLMilliseconds = 300_000
  static let protocolVersionKey = "io.modelcontextprotocol/protocolVersion"
  static let clientCapabilitiesKey = "io.modelcontextprotocol/clientCapabilities"
  static let clientInfoKey = "io.modelcontextprotocol/clientInfo"
  static let serverInfoKey = "io.modelcontextprotocol/serverInfo"

  private static let capabilities = Server.Capabilities(tools: .init(listChanged: false))

  private enum Era: Hashable, Sendable {
    case handshake
    case modern
  }

  private struct State {
    var initialized = false
    var client: MCPClientIdentity?
    var toolLists: [Era: Data] = [:]
    var running: [UUID: Task<Void, Never>] = [:]
    var tokens: [JSONRPCID: UUID] = [:]
    var cancelled: Set<UUID> = []
  }

  private let info: ServerInfo
  private let listTools: @Sendable () -> [Tool]
  private let callTool: @Sendable (CallTool.Parameters) async throws -> CallTool.Result
  private let clientIdentified: @Sendable (MCPClientIdentity) -> Void
  private let toolCalled: @Sendable () -> Void
  private let state = Mutex(State())

  /// - Parameters:
  ///   - listTools: The catalog, read once per protocol era.
  ///   - callTool: Runs one tool call. A `CancellationError` means the
  ///     request was cancelled; any other error becomes error -32603.
  ///   - clientIdentified: Called when a client first names itself, and
  ///     again if a later request names a different client.
  ///   - toolCalled: Called as each tool call starts.
  init(
    info: ServerInfo,
    listTools: @escaping @Sendable () -> [Tool],
    callTool: @escaping @Sendable (CallTool.Parameters) async throws -> CallTool.Result,
    clientIdentified: @escaping @Sendable (MCPClientIdentity) -> Void = { _ in },
    toolCalled: @escaping @Sendable () -> Void = {}
  ) {
    self.info = info
    self.listTools = listTools
    self.callTool = callTool
    self.clientIdentified = clientIdentified
    self.toolCalled = toolCalled
  }

  /// Answers each line of `lines` through `send` until `lines` ends, then
  /// returns once every request already running has answered.
  func serve(_ lines: AsyncStream<Data>, send: @escaping @Sendable (Data) -> Void) async {
    for await line in lines {
      receive(line, send: send)
    }
    while let task = state.withLock({ $0.running.values.first }) {
      await task.value
    }
  }

  /// Handles one line: answers a parse error or an invalid message at once,
  /// starts a task for a request or a batch, and applies a notification.
  func receive(_ line: Data, send: @escaping @Sendable (Data) -> Void) {
    let value: Value
    do {
      value = try LiteralValue.decode(line)
    } catch {
      send(MCPWire.errorFrame(id: nil, .parseError("the message is not valid JSON")))
      return
    }
    if case .array(let items) = value {
      guard !items.isEmpty else {
        send(MCPWire.errorFrame(id: nil, .invalidRequest("a batch must not be empty")))
        return
      }
      start(id: nil) { _ in
        var frames: [Data] = []
        for item in items {
          if let frame = await self.reply(to: MCPIncomingMessage(item)) { frames.append(frame) }
        }
        if !frames.isEmpty { send(MCPWire.batchFrame(frames)) }
      }
      return
    }
    switch MCPIncomingMessage(value) {
    case .request(let id, let method, let params):
      start(id: id) { token in
        let frame = await self.respond(id: id, method: method, params: params)
        if self.finish(id: id, token: token), let frame { send(frame) }
      }
    case .notification(let method, let params):
      notify(method: method, params: params)
    case .response:
      return
    case .invalid(let id, let error):
      send(MCPWire.errorFrame(id: id, error))
    }
  }

  // MARK: Requests

  /// Runs `body` in a task tracked until it ends; with an `id`, the task can
  /// be cancelled by `notifications/cancelled`.
  private func start(id: JSONRPCID?, _ body: @escaping @Sendable (UUID) async -> Void) {
    let token = UUID()
    state.withLock { state in
      if let id { state.tokens[id] = token }
      state.running[token] = Task {
        await body(token)
        self.state.withLock { _ = $0.running.removeValue(forKey: token) }
      }
    }
  }

  /// Forgets request `id`'s cancellation entry; false when it was cancelled,
  /// so its response must not be sent.
  private func finish(id: JSONRPCID, token: UUID) -> Bool {
    state.withLock { state in
      if state.tokens[id] == token { state.tokens[id] = nil }
      return state.cancelled.remove(token) == nil
    }
  }

  /// The reply to one element of a batch, or nil when it gets none.
  private func reply(to message: MCPIncomingMessage) async -> Data? {
    switch message {
    case .request(let id, let method, let params):
      return await respond(id: id, method: method, params: params)
    case .notification(let method, let params):
      notify(method: method, params: params)
      return nil
    case .response:
      return nil
    case .invalid(let id, let error):
      return MCPWire.errorFrame(id: id, error)
    }
  }

  /// The response frame to a request, or nil when it was cancelled.
  private func respond(id: JSONRPCID, method: String, params: [String: Value]?) async -> Data? {
    do {
      return MCPWire.resultFrame(id: id, result: try await result(of: method, params: params))
    } catch let error as MCPWireError {
      return MCPWire.errorFrame(id: id, error)
    } catch is CancellationError {
      return nil
    } catch {
      return MCPWire.errorFrame(id: id, .internalError(String(describing: error)))
    }
  }

  private func result(of method: String, params: [String: Value]?) async throws -> Data {
    if method == "initialize" { return try initialize(params) }
    let era = try era(of: method, params: params)
    switch method {
    case "server/discover":
      let discovered = DiscoverResult(
        supportedVersions: [Self.modernProtocolVersion], capabilities: Self.capabilities,
        instructions: info.instructions)
      return try encode(discovered, era: era, cacheable: true)
    case "ping":
      return try encode(EmptyResult(), era: era)
    case "tools/list":
      if let cached = state.withLock({ $0.toolLists[era] }) { return cached }
      let listed = try encode(ListTools.Result(tools: listTools()), era: era, cacheable: true)
      state.withLock { $0.toolLists[era] = listed }
      return listed
    case "tools/call":
      var called = try await self.called(params)
      let meta = called._meta?.fields ?? [:]
      called._meta = nil
      return try encode(called, era: era, meta: meta)
    default:
      throw MCPWireError.methodNotFound(method)
    }
  }

  private func initialize(_ params: [String: Value]?) throws -> Data {
    let wasInitialized = state.withLock { state in
      defer { state.initialized = true }
      return state.initialized
    }
    guard !wasInitialized else { throw MCPWireError.invalidRequest("already initialized") }
    let requested = params?["protocolVersion"]?.stringValue ?? Version.latest
    let client = params?["clientInfo"]?.objectValue
    note(
      MCPClientIdentity(
        name: client?["name"]?.stringValue ?? "unknown", title: client?["title"]?.stringValue,
        version: client == nil ? "0.0.0" : client?["version"]?.stringValue))
    let result = Initialize.Result(
      protocolVersion: Version.supported.contains(requested) ? requested : Version.latest,
      capabilities: Self.capabilities,
      serverInfo: Server.Info(name: info.name, version: info.version, title: info.title),
      instructions: info.instructions)
    return try MCPWire.encoder().encode(result)
  }

  /// The protocol era `params` select, after checking 2026-07-28 metadata.
  /// Any of the three per-request keys marks a 2026-07-28 request, which then
  /// needs the version and capabilities; other `io.modelcontextprotocol/`
  /// keys also occur in handshake-era requests and do not count.
  private func era(of method: String, params: [String: Value]?) throws -> Era {
    let meta = params?["_meta"]?.objectValue ?? [:]
    let perRequestKeys = [Self.protocolVersionKey, Self.clientCapabilitiesKey, Self.clientInfoKey]
    guard perRequestKeys.contains(where: { meta[$0] != nil }) else {
      guard method != "server/discover" else {
        throw MCPWireError.invalidParams(
          "_meta needs \(Self.protocolVersionKey) and \(Self.clientCapabilitiesKey)")
      }
      return .handshake
    }
    guard case .string(let requested)? = meta[Self.protocolVersionKey] else {
      throw MCPWireError.invalidParams("_meta needs \(Self.protocolVersionKey), a string")
    }
    guard requested == Self.modernProtocolVersion else {
      throw MCPWireError.unsupportedProtocolVersion(
        requested: requested, supported: [Self.modernProtocolVersion])
    }
    guard case .object? = meta[Self.clientCapabilitiesKey] else {
      throw MCPWireError.invalidParams("_meta needs \(Self.clientCapabilitiesKey), an object")
    }
    if case .object(let client)? = meta[Self.clientInfoKey], let name = client["name"]?.stringValue
    {
      note(
        MCPClientIdentity(
          name: name, title: client["title"]?.stringValue, version: client["version"]?.stringValue))
    }
    return .modern
  }

  private func called(_ params: [String: Value]?) async throws -> CallTool.Result {
    guard let name = params?["name"]?.stringValue else {
      throw MCPWireError.invalidParams("tools/call needs a string name")
    }
    let arguments: [String: Value]?
    switch params?["arguments"] {
    case nil, .null?: arguments = nil
    case .object(let fields)?: arguments = fields
    default: throw MCPWireError.invalidParams("arguments must be an object")
    }
    toolCalled()
    return try await callTool(
      CallTool.Parameters(
        name: name, arguments: arguments,
        meta: params?["_meta"]?.objectValue.map { Metadata(additionalFields: $0) }))
  }

  private func note(_ client: MCPClientIdentity) {
    let isNew = state.withLock { state in
      defer { state.client = client }
      return state.client != client
    }
    if isNew { clientIdentified(client) }
  }

  // MARK: Notifications

  private func notify(method: String, params: [String: Value]?) {
    guard method == "notifications/cancelled",
      let id = params?["requestId"].flatMap(JSONRPCID.init)
    else { return }
    let task = state.withLock { state -> Task<Void, Never>? in
      guard let token = state.tokens.removeValue(forKey: id) else { return nil }
      state.cancelled.insert(token)
      return state.running[token]
    }
    task?.cancel()
  }

  // MARK: Encoding

  /// `result` encoded for `era`: as is for the handshake protocol; with
  /// `resultType`, the server's identity merged into `meta`, and, when
  /// `cacheable`, the cache hints for 2026-07-28. `result` must not encode
  /// `_meta` itself; pass it as `meta`.
  private func encode<Result: Encodable>(
    _ result: Result, era: Era, meta: [String: Value] = [:], cacheable: Bool = false
  ) throws -> Data {
    switch era {
    case .handshake:
      return try MCPWire.encoder().encode(
        MetaMergedResult(inner: result, meta: meta, modern: nil))
    case .modern:
      var merged = meta
      merged[Self.serverInfoKey] = .object([
        "name": .string(info.name), "title": .string(info.title),
        "version": .string(info.version),
      ])
      return try MCPWire.encoder().encode(
        MetaMergedResult(inner: result, meta: merged, modern: .init(cacheable: cacheable)))
    }
  }
}

/// MCP 2026-07-28's `DiscoverResult`, before the fields every result shares.
private struct DiscoverResult: Encodable {
  let supportedVersions: [String]
  let capabilities: Server.Capabilities
  let instructions: String
}

/// A result with no fields of its own (`ping`).
private struct EmptyResult: Encodable {
  private enum CodingKeys: CodingKey {}

  func encode(to encoder: Encoder) throws {
    _ = encoder.container(keyedBy: CodingKeys.self)
  }
}

/// `inner`'s fields plus `_meta` (when not empty) and, for 2026-07-28, the
/// fields every result of that protocol carries, in one JSON object.
private struct MetaMergedResult<Inner: Encodable>: Encodable {
  struct Modern {
    let cacheable: Bool
  }

  let inner: Inner
  let meta: [String: Value]
  let modern: Modern?

  private enum CodingKeys: String, CodingKey {
    case _meta, resultType, ttlMs, cacheScope
  }

  func encode(to encoder: Encoder) throws {
    try inner.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    if !meta.isEmpty { try container.encode(meta, forKey: ._meta) }
    guard let modern else { return }
    try container.encode("complete", forKey: .resultType)
    if modern.cacheable {
      try container.encode(MCPServer.cacheTTLMilliseconds, forKey: .ttlMs)
      try container.encode("private", forKey: .cacheScope)
    }
  }
}
