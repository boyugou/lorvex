import Foundation
import LorvexStore

extension SwiftLorvexCoreService: LorvexMcpIdempotencyServicing {
  public func lookupMcpIdempotency(
    toolName: String,
    key: String,
    checksum: String
  ) async throws -> McpIdempotencyOutcome {
    try read { db in
      switch try McpIdempotency.lookupChecked(
        db, toolName: toolName, key: key, suppliedChecksum: checksum)
      {
      case .miss:
        return .miss
      case .hit(let payload):
        return .hit(responsePayload: payload)
      case .checksumMismatch(_, let stored, let supplied):
        return .checksumMismatch(storedChecksum: stored, suppliedChecksum: supplied)
      }
    }
  }

  /// Test seam only — seeds a durable replay row directly, outside the
  /// claim/finalize funnel. Production writes never call this: the funnel's
  /// underlying `recordAt` overwrites a same-checksum row's payload without
  /// ownership proof, so a live caller could clobber another transaction's
  /// claim sentinel. Deliberately not part of ``LorvexMcpIdempotencyServicing``.
  public func recordMcpIdempotency(
    toolName: String,
    key: String,
    checksum: String,
    payload: String
  ) async throws {
    try withLocalMaintenanceWrite { db in
      try McpIdempotency.record(
        db, key: key, toolName: toolName, requestChecksum: checksum, responsePayload: payload)
    }
  }

  public func finalizeMcpIdempotency(
    toolName: String,
    key: String,
    checksum: String,
    claimToken: String,
    payload: String
  ) async throws {
    try withLocalMaintenanceWrite { db in
      try McpIdempotency.finalizeMutation(
        db,
        key: key,
        toolName: toolName,
        requestChecksum: checksum,
        claimPayload: McpIdempotencyDurablePayload.transactionClaim(token: claimToken),
        responsePayload: payload)
    }
  }

  public func sweepMcpIdempotency() async throws {
    _ = try withLocalMaintenanceWrite { db in
      try McpIdempotency.sweepExpired(db)
    }
  }
}
