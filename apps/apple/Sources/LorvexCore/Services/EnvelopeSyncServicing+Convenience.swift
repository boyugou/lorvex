import Foundation
import LorvexDomain
import LorvexSync

/// Defaults for lightweight backends such as test doubles. The SQLite service
/// overrides every one of these at the query or transaction boundary.
extension EnvelopeSyncServicing {
  public func pendingOutbound(afterOutboxId: Int64?) throws -> [PendingOutboundEnvelope] {
    let pending = try pendingOutbound()
    guard let afterOutboxId else { return pending }
    return pending.filter { $0.outboxId > afterOutboxId }
  }

  /// A lightweight backend filters no raw rows, so its decoded high-water is
  /// also the raw high-water.
  public func pendingOutboundPage(
    afterOutboxId: Int64?, now _: String
  ) throws -> PendingOutboundPage {
    let pending = try pendingOutbound(afterOutboxId: afterOutboxId)
    return PendingOutboundPage(
      envelopes: pending,
      lastScannedOutboxId: pending.last?.outboxId)
  }

  /// Non-transactional composition of the individual calls. A collision needs
  /// the transactional store's semantic join, so it is rejected here.
  public func reconcileOutbound(
    _ request: OutboundReconciliationRequest
  ) throws -> OutboundReconciliationReport {
    guard request.collisions.isEmpty else {
      throw OutboundReconciliationFallbackError.collisionRequiresTransactionalStore
    }
    let report = try applyInbound(request.serverWinnerEnvelopes, undecodable: 0)
    try deferUnknownTypeRecords(request.deferredUnknownTypeRecords)
    for failure in request.failures {
      try recordOutboundFailure(
        outboxId: failure.outboxId, error: failure.error, kind: failure.kind)
    }
    try markOutboundSynced(outboxIds: request.confirmedOutboxIds)
    var enriched = report
    enriched.deferredUnknownType += request.deferredUnknownTypeRecords.count
    return OutboundReconciliationReport(inbound: enriched)
  }

  public func runLocalRetentionMaintenance(includeActiveOutboxCap: Bool) throws {}

  public func isReseedRequired() throws -> Bool { false }
}

enum OutboundReconciliationFallbackError: Error {
  case collisionRequiresTransactionalStore
}
