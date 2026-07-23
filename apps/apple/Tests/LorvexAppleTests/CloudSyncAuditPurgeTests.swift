import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import LorvexSync
import Testing
@preconcurrency import CloudKit

@testable import LorvexCloudSync

private actor AuditPurgeRecordPusher: CloudSyncRecordPushing {
  let errorCode: CKError.Code?

  init(errorCode: CKError.Code?) {
    self.errorCode = errorCode
  }

  func physicallyDelete(
    _ recordIDs: [CKRecord.ID], context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> [CKRecord.ID: Result<Void, any Error>] {
    Dictionary(
      uniqueKeysWithValues: recordIDs.map { recordID in
        if let errorCode {
          return (recordID, .failure(CKError(errorCode)))
        }
        return (recordID, .success(()))
      })
  }
}

private final class RecordingAuditPurgeSync: @unchecked Sendable, EnvelopeSyncServicing {
  private let lock = NSLock()
  private var pendingStorage: [AuditRetentionPurgeItem]
  private var acknowledgedStorage: [String] = []
  private var failuresStorage: [String] = []

  init(zoneName: String, itemCount: Int = 1) {
    self.pendingStorage = (0..<itemCount).map { index in
      AuditRetentionPurgeItem(
        accountIdentifier: "account-A", zoneName: zoneName,
        entityId: "audit-entry-\(index + 1)", retentionEpoch: 1,
        reason: .localRetention, attemptCount: 0, nextAttemptAt: nil,
        lastError: nil, createdAt: "2026-07-14T12:00:00.000Z")
    }
  }

  func pendingAuditRetentionPurges(
    forAccountIdentifier _: String, zoneName: String, limit: Int
  ) throws -> [AuditRetentionPurgeItem] {
    lock.lock()
    defer { lock.unlock() }
    return Array(pendingStorage.lazy.filter { $0.zoneName == zoneName }.prefix(limit))
  }

  func acknowledgeAuditRetentionPurges(
    forAccountIdentifier _: String, zoneName _: String, entityIds: [String]
  ) throws {
    lock.lock()
    acknowledgedStorage.append(contentsOf: entityIds)
    let acknowledged = Set(entityIds)
    pendingStorage.removeAll { acknowledged.contains($0.entityId) }
    lock.unlock()
  }

  func recordAuditRetentionPurgeFailure(
    forAccountIdentifier _: String, zoneName _: String,
    entityId: String, error _: String
  ) throws {
    lock.lock()
    failuresStorage.append(entityId)
    pendingStorage.removeAll { $0.entityId == entityId }
    lock.unlock()
  }

  var acknowledged: [String] {
    lock.lock()
    defer { lock.unlock() }
    return acknowledgedStorage
  }

  var failures: [String] {
    lock.lock()
    defer { lock.unlock() }
    return failuresStorage
  }

  func pendingOutbound() throws -> [PendingOutboundEnvelope] { [] }
  func markOutboundSynced(outboxIds _: [Int64]) throws {}
  func recordOutboundFailure(
    outboxId _: Int64, error _: String, kind _: OutboundFailureKind
  ) throws {}
  func applyInbound(
    _ envelopes: [SyncEnvelope], undecodable: Int
  ) throws -> InboundApplyReport {
    InboundApplyReport(undecodable: undecodable)
  }
  func deferUnknownTypeRecords(_ raws: [RawEnvelopeFields]) throws {}
  func enqueueFullResyncBackfill() throws -> FullResyncBackfillReport {
    FullResyncBackfillReport()
  }
  func enrolledZoneEpoch(forAccountIdentifier _: String) throws -> Int? { nil }
}

struct CloudSyncAuditPurgeTests {
  private func coordinator(errorCode: CKError.Code?) -> CloudSyncEngineCoordinator {
    CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: AuditPurgeRecordPusher(errorCode: errorCode),
      fetcher: StubRemoteChangeFetcher(records: []))
  }

  @Test
  func alreadyAbsentCloudKitOutcomesAcknowledgeThePurge() async throws {
    for errorCode in [CKError.Code.unknownItem, .zoneNotFound, .userDeletedZone] {
      let context = CloudSyncGenerationContext(
        accountIdentifier: "account-A", descriptor: cloudSyncTestDescriptor)
      let sync = RecordingAuditPurgeSync(zoneName: context.zoneName)

      _ = try await coordinator(errorCode: errorCode).processCurrentZoneAuditPurges(
        sync: sync, context: context, expectation: .ready(cloudSyncTestDescriptor),
        boundaryGuard: { true })

      #expect(sync.acknowledged == ["audit-entry-1"])
      #expect(sync.failures.isEmpty)
    }
  }

  @Test
  func transientCloudKitFailureRemainsDurableRetryWork() async throws {
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: cloudSyncTestDescriptor)
    let sync = RecordingAuditPurgeSync(zoneName: context.zoneName)

    _ = try await coordinator(errorCode: .networkFailure).processCurrentZoneAuditPurges(
      sync: sync, context: context, expectation: .ready(cloudSyncTestDescriptor),
      boundaryGuard: { true })

    #expect(sync.acknowledged.isEmpty)
    #expect(sync.failures == ["audit-entry-1"])
  }

  @Test
  func oneTriggerDrainsMoreThanTwoCloudKitDeletePages() async throws {
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: cloudSyncTestDescriptor)
    let sync = RecordingAuditPurgeSync(zoneName: context.zoneName, itemCount: 401)

    let hasMore = try await coordinator(errorCode: nil).processCurrentZoneAuditPurges(
      sync: sync, context: context, expectation: .ready(cloudSyncTestDescriptor),
      boundaryGuard: { true })

    #expect(!hasMore)
    #expect(sync.acknowledged.count == 401)
    #expect(Set(sync.acknowledged).count == 401)
    #expect(sync.failures.isEmpty)
  }
}
