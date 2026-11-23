import Foundation
import Logging
import MCP

/// The host's transport: the SDK's stdio transport, with the `initialize`
/// request's client capabilities made decodable before the SDK reads them.
///
/// The MCP schema lets a client describe each experimental capability as a
/// JSON object (Codex Desktop sends `"codex/auth-change": {}`), but the Swift
/// SDK decodes `capabilities.experimental` as a map of strings and answers
/// such a request with an internal error (-32603). Lorvex reads no client
/// experimental capability, so the transport removes that field from the
/// `initialize` request (``InitializeCapabilityFilter``). Every other message,
/// and an `initialize` request without the field, passes through byte for byte.
actor ClientCapabilityTolerantTransport: Transport {
  private let inner: any Transport
  nonisolated let logger: Logger

  /// Wraps `inner` (the stdio transport in the host, an in-memory one in
  /// tests) and exposes `logger`, normally `inner`'s own, which the SDK's
  /// server logs through.
  init(wrapping inner: any Transport, logger: Logger) {
    self.inner = inner
    self.logger = logger
  }

  func connect() async throws { try await inner.connect() }

  func disconnect() async { await inner.disconnect() }

  func send(_ data: Data) async throws { try await inner.send(data) }

  func receive() -> AsyncThrowingStream<Data, Swift.Error> {
    let inner = self.inner
    return AsyncThrowingStream { continuation in
      let forwarding = Task {
        do {
          for try await message in await inner.receive() {
            continuation.yield(InitializeCapabilityFilter.filtered(message))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in forwarding.cancel() }
    }
  }
}

/// Makes an MCP `initialize` request's client capabilities decodable by the
/// Swift SDK by removing `params.capabilities.experimental`, which the SDK can
/// read only as a map of strings and Lorvex never reads.
enum InitializeCapabilityFilter {
  /// `message` without `params.capabilities.experimental` when it is a single
  /// JSON-RPC `initialize` request that carries the field; otherwise `message`
  /// unchanged, byte for byte, including a batch, a malformed message, and
  /// every request other than `initialize`.
  static func filtered(_ message: Data) -> Data {
    // Most messages never name the method; skip parsing them.
    guard message.range(of: Data(#""initialize""#.utf8)) != nil,
      var request = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any],
      request["method"] as? String == "initialize",
      var params = request["params"] as? [String: Any],
      var capabilities = params["capabilities"] as? [String: Any],
      capabilities["experimental"] != nil
    else { return message }
    capabilities.removeValue(forKey: "experimental")
    params["capabilities"] = capabilities
    request["params"] = params
    guard
      let rewritten = try? JSONSerialization.data(
        withJSONObject: request, options: [.withoutEscapingSlashes])
    else { return message }
    return rewritten
  }
}
