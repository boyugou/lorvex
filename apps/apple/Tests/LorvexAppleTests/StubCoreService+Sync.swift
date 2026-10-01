import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync

/// Sync-state forwarding for `StubCoreService`.
///
/// The main stub records the transport-facing outbox calls; retention
/// maintenance and the reseed marker live in the real in-memory core.
extension StubCoreService {
  func runLocalRetentionMaintenance(includeActiveOutboxCap: Bool) throws {
    try preview.runLocalRetentionMaintenance(includeActiveOutboxCap: includeActiveOutboxCap)
  }

  func isReseedRequired() throws -> Bool {
    try preview.isReseedRequired()
  }
}
