import Foundation
import Synchronization

/// Result of a DB-backed idempotency lookup.
public enum McpIdempotencyOutcome: Sendable, Equatable {
  case miss
  case hit(responsePayload: String)
  case checksumMismatch(storedChecksum: String, suppliedChecksum: String)
}

public struct McpIdempotencyContext: Sendable, Equatable {
  public var toolName: String
  public var key: String
  public var checksum: String
  public var claimToken: String
  public var attemptState: McpIdempotencyAttemptState

  public init(
    toolName: String,
    key: String,
    checksum: String,
    claimToken: String = UUID().uuidString.lowercased(),
    attemptState: McpIdempotencyAttemptState = McpIdempotencyAttemptState()
  ) {
    self.toolName = toolName
    self.key = key
    self.checksum = checksum
    self.claimToken = claimToken
    self.attemptState = attemptState
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.toolName == rhs.toolName && lhs.key == rhs.key
      && lhs.checksum == rhs.checksum && lhs.claimToken == rhs.claimToken
  }
}

public enum McpIdempotencyDurablePayload {
  public enum Kind: Sendable, Equatable {
    case response
    case appliedWithoutResponse
    case transactionClaim(token: String)
  }

  private struct Sentinel: Decodable {
    let marker: String
    let token: String?

    enum CodingKeys: String, CodingKey {
      case marker = "__lorvex_mcp_idempotency"
      case token
    }
  }

  public static let appliedWithoutResponse =
    #"{"__lorvex_mcp_idempotency":"applied_without_response"}"#

  public static func transactionClaim(token: String) -> String {
    #"{"__lorvex_mcp_idempotency":"transaction_claim","token":"\#(token)"}"#
  }

  public static func isAppliedWithoutResponse(_ payload: String) -> Bool {
    switch kind(of: payload) {
    case .appliedWithoutResponse, .transactionClaim: return true
    case .response: return false
    }
  }

  public static func kind(of payload: String) -> Kind {
    guard let data = payload.data(using: .utf8),
      let sentinel = try? JSONDecoder().decode(Sentinel.self, from: data)
    else { return .response }
    switch sentinel.marker {
    case "applied_without_response": return .appliedWithoutResponse
    case "transaction_claim":
      guard let token = sentinel.token, !token.isEmpty else { return .response }
      return .transactionClaim(token: token)
    default: return .response
    }
  }
}

/// A competing durable MCP idempotency row discovered inside the same
/// `BEGIN IMMEDIATE` transaction that would otherwise perform the mutation.
/// The MCP dispatch boundary converts this typed gate into a replay or conflict
/// response; the domain body never runs.
public enum McpIdempotencyTransactionError: Error, Sendable, Equatable {
  case replay(responsePayload: String)
  case checksumMismatch(storedChecksum: String, suppliedChecksum: String)
}

/// Carries an in-transaction gate back to MCP dispatch even if a domain-specific
/// handler catches the thrown error to build a partial-success response. The
/// first gate wins; no later handler work may turn a rejected idempotency claim
/// into a successful tool response.
public final class McpIdempotencyAttemptState: Sendable {
  private let storedGate = Mutex<McpIdempotencyTransactionError?>(nil)

  public init() {}

  public func record(_ gate: McpIdempotencyTransactionError) {
    storedGate.withLock { stored in
      if stored == nil { stored = gate }
    }
  }

  public var gate: McpIdempotencyTransactionError? {
    storedGate.withLock { $0 }
  }
}

/// Durable MCP idempotency store backed by the `mcp_idempotency` DB table.
///
/// `SwiftLorvexCoreService` conforms to this protocol so the MCP host can
/// cast `service as? any LorvexMcpIdempotencyServicing` without making
/// idempotency concerns part of the general `LorvexCoreServicing` contract.
public protocol LorvexMcpIdempotencyServicing: Sendable {
  func lookupMcpIdempotency(
    toolName: String, key: String, checksum: String
  ) async throws -> McpIdempotencyOutcome

  func finalizeMcpIdempotency(
    toolName: String,
    key: String,
    checksum: String,
    claimToken: String,
    payload: String
  ) async throws

  func sweepMcpIdempotency() async throws
}
