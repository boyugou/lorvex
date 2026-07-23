import Foundation
import LorvexCore
import LorvexDomain
@preconcurrency import CloudKit

extension CloudSyncEngineCoordinator {
  /// Execute only physical-delete work for the exact ready generation. Purges
  /// belonging to retired zones stay durable until whole-zone deletion proves
  /// that generation gone.
  func processCurrentZoneAuditPurges(
    sync: any EnvelopeSyncServicing,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: @escaping @Sendable () async -> Bool
  ) async throws -> Bool {
    let pageSize = Self.maxPushBatchSize
    for _ in 0..<Self.maxDrainIterations {
      let pending = try sync.pendingAuditRetentionPurges(
        forAccountIdentifier: context.accountIdentifier,
        zoneName: context.zoneName, limit: pageSize)
      guard !pending.isEmpty else { return false }
      guard await boundaryGuard() else {
        throw CloudSyncGenerationBoundaryCrossed()
      }

      let recordIDs = pending.map {
        CKRecord.ID(
          recordName: CloudSyncEnvelopeRecord.recordName(
            entityType: EntityName.aiChangelog, entityId: $0.entityId),
          zoneID: context.zoneID)
      }
      let results = try await pusher.physicallyDelete(
        recordIDs, context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
      guard await boundaryGuard() else {
        throw CloudSyncGenerationBoundaryCrossed()
      }

      var acknowledged: [String] = []
      for (item, recordID) in zip(pending, recordIDs) {
        guard let result = results[recordID] else {
          try sync.recordAuditRetentionPurgeFailure(
            forAccountIdentifier: context.accountIdentifier,
            zoneName: context.zoneName, entityId: item.entityId,
            error: "CloudKit returned no physical-delete result")
          continue
        }
        switch result {
        case .success:
          acknowledged.append(item.entityId)
        case .failure(let error):
          if auditPurgeDeleteProvesAbsent(error) {
            acknowledged.append(item.entityId)
          } else {
            try sync.recordAuditRetentionPurgeFailure(
              forAccountIdentifier: context.accountIdentifier,
              zoneName: context.zoneName, entityId: item.entityId,
              error: error.localizedDescription)
          }
        }
      }
      if !acknowledged.isEmpty {
        try sync.acknowledgeAuditRetentionPurges(
          forAccountIdentifier: context.accountIdentifier,
          zoneName: context.zoneName, entityIds: acknowledged)
      }
      if pending.count < pageSize { return false }
    }
    return !(try sync.pendingAuditRetentionPurges(
      forAccountIdentifier: context.accountIdentifier,
      zoneName: context.zoneName, limit: 1
    ).isEmpty)
  }
}

/// CloudKit's delete API reports an already-absent record as `unknownItem`.
/// A missing/deleted zone proves the same postcondition for every record in
/// that zone. These are successful idempotent delete outcomes, not retryable
/// purge failures; every other error remains durable retry work.
private func auditPurgeDeleteProvesAbsent(_ error: any Error) -> Bool {
  guard let cloudKitError = error as? CKError else { return false }
  switch cloudKitError.code {
  case .unknownItem, .zoneNotFound, .userDeletedZone:
    return true
  default:
    return false
  }
}
