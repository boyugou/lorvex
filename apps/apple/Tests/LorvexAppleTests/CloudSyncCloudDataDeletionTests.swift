import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexSync
import Testing

private struct StubRetentionAcknowledgementError: Error {}

private final class RecordingZoneDeletionSync: @unchecked Sendable, EnvelopeSyncServicing {
  private let lock = NSLock()
  private var failuresBeforeSuccess: Int
  private var callCountStorage = 0
  private let order: OrderRecorderBox?

  init(failuresBeforeSuccess: Int = 0, order: OrderRecorderBox? = nil) {
    self.failuresBeforeSuccess = failuresBeforeSuccess
    self.order = order
  }

  func acknowledgeAuditRetentionZoneDeletion(
    forAccountIdentifier _: String, zoneName _: String
  ) throws {
    order?.record("ackRetention")
    lock.lock()
    defer { lock.unlock() }
    callCountStorage += 1
    if failuresBeforeSuccess > 0 {
      failuresBeforeSuccess -= 1
      throw StubRetentionAcknowledgementError()
    }
  }

  var callCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return callCountStorage
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

struct CloudSyncCloudDataDeletionTests {
  private func coordinator(
    pusher: RecordingRecordPusher,
    pause: RecordingCloudSyncPauseStore,
    currentAccount: String = "account-A",
    storedAccount: String = "account-A"
  ) -> CloudSyncEngineCoordinator {
    CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: currentAccount),
      accountIdentityStore: RecordingAccountIdentityStore(initial: storedAccount),
      accountPauseStore: pause)
  }

  @Test
  func deletePublishesPersistentBarrierBeforeRemovingGenerationZones() async throws {
    let pusher = RecordingRecordPusher()
    let pause = RecordingCloudSyncPauseStore()
    let sync = try makeInMemoryCore()
    try await coordinator(pusher: pusher, pause: pause)
      .deleteAllCloudData(sync: sync)

    #expect(await pause.reason == .userDeletedZone)
    guard case .deleted(let generation, let retired, _)? =
      try await pusher.currentZoneGenerationState()
    else {
      Issue.record("expected persistent deleted barrier")
      return
    }
    #expect(generation == 2)
    #expect(retired.isEmpty, "successful physical deletion CAS-prunes the ledger")
    #expect(await pusher.deleteZoneCallCount == 1)
    #expect(await pusher.retiredLedgerFinalizeCallCount == 1)
  }

  @Test
  func physicalCleanupFailureNeverRollsBackDeletedBarrier() async throws {
    let pusher = RecordingRecordPusher(
      deleteZoneError: RecordingRecordPusher.StubZoneDeleteError())
    let pause = RecordingCloudSyncPauseStore()
    let coordinator = coordinator(pusher: pusher, pause: pause)
    let sync = try makeInMemoryCore()

    await #expect(throws: CloudSyncCloudDataDeletionError.self) {
      try await coordinator.deleteAllCloudData(sync: sync)
    }
    #expect(await pause.reason == .userDeletedZone)
    guard case .deleted(_, let retired, _)? =
      try await pusher.currentZoneGenerationState()
    else {
      Issue.record("deleted barrier must survive cleanup failure")
      return
    }
    #expect(retired == [RecordingRecordPusher.readyDescriptor.zoneName])
  }

  @Test
  func unavailableAccountCannotPublishADeletionBarrier() async throws {
    let pusher = RecordingRecordPusher()
    let pause = RecordingCloudSyncPauseStore()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(availability: .noAccount),
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
      accountPauseStore: pause)
    let sync = try makeInMemoryCore()

    await #expect(throws: CloudSyncCloudDataDeletionError.self) {
      try await coordinator.deleteAllCloudData(sync: sync)
    }
    #expect(await pause.reason == nil)
    guard case .ready? = try await pusher.currentZoneGenerationState() else {
      Issue.record("generation must remain ready")
      return
    }
  }

  @Test
  func crashAfterRemoteDeleteBeforeLocalRetentionAckKeepsLedgerForRetry() async throws {
    let order = OrderRecorderBox()
    let pusher = RecordingRecordPusher(orderRecorder: order)
    let pause = RecordingCloudSyncPauseStore()
    let sync = RecordingZoneDeletionSync(failuresBeforeSuccess: 1, order: order)
    let coordinator = coordinator(pusher: pusher, pause: pause)

    await #expect(throws: CloudSyncCloudDataDeletionError.self) {
      try await coordinator.deleteAllCloudData(sync: sync)
    }
    guard case .deleted(_, let retained, _)? =
      try await pusher.currentZoneGenerationState()
    else {
      Issue.record("deleted ledger must survive an interrupted local acknowledgement")
      return
    }
    #expect(retained == [RecordingRecordPusher.readyDescriptor.zoneName])
    #expect(await pusher.retiredLedgerFinalizeCallCount == 0)

    try await coordinator.deleteAllCloudData(sync: sync)
    #expect(sync.callCount == 2)
    #expect(await pusher.deleteZoneCallCount == 2)
    #expect(await pusher.retiredLedgerFinalizeCallCount == 1)
    #expect(
      order.snapshot == [
        "deleteZone", "ackRetention",
        "deleteZone", "ackRetention", "finalizeRetiredZone",
      ])
  }

  @Test
  func crashAfterCacheCleanupBeforeLedgerCASKeepsLedgerForRetry() async throws {
    let order = OrderRecorderBox()
    let pusher = RecordingRecordPusher(
      orderRecorder: order,
      retiredLedgerFinalizeFailuresBeforeSuccess: 1)
    let pause = RecordingCloudSyncPauseStore()
    let sync = RecordingZoneDeletionSync(order: order)
    let coordinator = coordinator(pusher: pusher, pause: pause)

    await #expect(throws: CloudSyncCloudDataDeletionError.self) {
      try await coordinator.deleteAllCloudData(sync: sync)
    }
    guard case .deleted(_, let retained, _)? =
      try await pusher.currentZoneGenerationState()
    else {
      Issue.record("deleted ledger must survive an interrupted final CAS")
      return
    }
    #expect(retained == [RecordingRecordPusher.readyDescriptor.zoneName])
    #expect(await pusher.clearRecordSystemFieldsCacheCallCount == 1)
    #expect(await pusher.retiredLedgerFinalizeCallCount == 1)

    try await coordinator.deleteAllCloudData(sync: sync)
    #expect(sync.callCount == 2)
    #expect(await pusher.clearRecordSystemFieldsCacheCallCount == 3)
    #expect(await pusher.retiredLedgerFinalizeCallCount == 2)
  }

  @Test
  func interruptedEnumerationAutomaticallyResumesFromDeletedBarrier() async throws {
    let active = RecordingRecordPusher.readyDescriptor.zoneName
    let orphan = "LorvexData-e0-orphaned-generation"
    let pusher = RecordingRecordPusher(
      allRecordZonesFailuresBeforeSuccess: 1,
      recordZoneNames: [active, orphan])
    let pause = RecordingCloudSyncPauseStore()
    let sync = try makeInMemoryCore()
    let coordinator = coordinator(pusher: pusher, pause: pause)

    await #expect(throws: CloudSyncCloudDataDeletionError.self) {
      try await coordinator.deleteAllCloudData(sync: sync)
    }
    #expect(await pause.reason == .userDeletedZone)
    #expect(await pusher.deleteZoneCallCount == 1)

    let resumed = try await coordinator.retryPendingCloudDataDeletionCleanup(sync: sync)
    #expect(resumed)
    #expect(await pusher.deleteZoneCallCount == 2)
    #expect(await pusher.allRecordZonesCallCount == 4)
  }

  @Test
  func deletionMaintenanceNeverCrossesTheDurableAccountBoundary() async throws {
    let residual = "LorvexData-e1-residual-generation"
    let pusher = RecordingRecordPusher(recordZoneNames: [residual])
    await pusher.setGenerationState(.deleted(
      deletionGeneration: 2, retiredZoneNames: [residual], modifiedAt: nil))
    let pause = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    let sync = try makeInMemoryCore()
    let coordinator = coordinator(
      pusher: pusher, pause: pause,
      currentAccount: "account-B", storedAccount: "account-A")

    let observedPause = try await coordinator.retryPendingCloudDataDeletionCleanup(sync: sync)
    #expect(observedPause)
    #expect(await pusher.allRecordZonesCallCount == 0)
    #expect(await pusher.deleteZoneCallCount == 0)
  }

  @Test
  func deletionMaintenanceDoesNotTouchAPeerReenabledGeneration() async throws {
    let active = RecordingRecordPusher.readyDescriptor.zoneName
    let pusher = RecordingRecordPusher(recordZoneNames: [active])
    let pause = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    let sync = try makeInMemoryCore()

    let observedPause = try await coordinator(pusher: pusher, pause: pause)
      .retryPendingCloudDataDeletionCleanup(sync: sync)
    #expect(observedPause)
    #expect(await pusher.allRecordZonesCallCount == 0)
    #expect(await pusher.deleteZoneCallCount == 0)
    guard case .ready? = try await pusher.currentZoneGenerationState() else {
      Issue.record("maintenance must leave the peer-reenabled generation ready")
      return
    }
  }
}
