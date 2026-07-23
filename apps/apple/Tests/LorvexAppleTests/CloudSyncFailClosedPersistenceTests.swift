import Foundation
import LorvexCloudSync
import LorvexStore
import Testing

@testable import LorvexCore

struct CloudSyncFailClosedPersistenceTests {
  private func coordinator(
    pusher: RecordingRecordPusher,
    pause: RecordingCloudSyncPauseStore = RecordingCloudSyncPauseStore(),
    fetcher: any CloudSyncRemoteChangeFetching = StubRemoteChangeFetcher(records: [])
  ) -> CloudSyncEngineCoordinator {
    CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: pusher,
      fetcher: fetcher,
      accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
      accountPauseStore: pause)
  }

  @Test
  func localAccountClaimBeforeFirstRemoteControlCanResumeBootstrapAfterCrash() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    #expect(
      try core.observedCloudGenerationAuthorityFloor(
        forAccountIdentifier: "account-A") == nil)
    let subject = coordinator(
      pusher: pusher,
      fetcher: RecordingPusherRemoteChangeFetcher(pusher: pusher))

    _ = try #require(try await subject.runCycle(sync: core))

    let state = try #require(try await pusher.currentZoneGenerationState())
    guard case .ready(let descriptor, _, _) = state else {
      Issue.record("interrupted first bootstrap should publish a ready generation")
      return
    }
    #expect(
      try core.observedCloudGenerationAuthorityFloor(
        forAccountIdentifier: "account-A") == descriptor.epoch)
  }

  @Test
  func missingControlRecordAfterLocalEnrollmentIsNotTreatedAsBootstrap() async throws {
    let pusher = RecordingRecordPusher()
    let coordinator = coordinator(pusher: pusher)
    let core = try makeInMemoryCore()

    _ = try #require(try await coordinator.runCycle(sync: core))
    await pusher.setGenerationState(nil)

    await #expect(throws: CloudSyncZoneEpochError.zoneEpochRecordUndecodable) {
      try await coordinator.runCycle(sync: core)
    }
  }

  @Test
  func restoredDatabaseRetainsGenerationFloorAndCannotBootstrapOverMissingControl() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    _ = try core.recordObservedCloudGenerationAuthority(
      forAccountIdentifier: "account-A", generation: 7)
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: "restored-database-instance")
    }
    _ = try core.rebindCloudTraversalAfterDatabaseInstanceRotation(
      expectedAccountIdentifier: "account-A")
    #expect(
      try core.observedCloudGenerationAuthorityFloor(
        forAccountIdentifier: "account-A") == 7)

    await #expect(throws: CloudSyncZoneEpochError.zoneEpochRecordUndecodable) {
      try await coordinator(pusher: pusher).runCycle(sync: core)
    }
    #expect(await pusher.ensureZoneCallCount == 0)
    #expect(await pusher.pushBatchSizes.isEmpty)
  }

  @Test
  func deletedControlStateDurablyPausesOrdinaryCycles() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(
      .deleted(
        deletionGeneration: 7,
        retiredZoneNames: [RecordingRecordPusher.readyDescriptor.zoneName],
        modifiedAt: nil))
    let pause = RecordingCloudSyncPauseStore()
    let coordinator = coordinator(pusher: pusher, pause: pause)

    #expect(try await coordinator.runCycle(sync: makeInMemoryCore()) == nil)
    #expect(await pause.reason == .userDeletedZone)
    #expect(await pusher.ensureZoneCallCount == 0)
  }

  @Test
  func generationAuthorityReadFailureLeavesSyncStateUntouched() async throws {
    let pusher = RecordingRecordPusher(
      currentZoneEpochError: RecordingRecordPusher.StubEpochFetchError())
    let coordinator = coordinator(pusher: pusher)

    await #expect(throws: RecordingRecordPusher.StubEpochFetchError.self) {
      try await coordinator.runCycle(sync: makeInMemoryCore())
    }
    #expect(await pusher.ensureZoneCallCount == 0)
    #expect(await pusher.pushBatchSizes.isEmpty)
  }

  @Test
  func filePauseCompareAndSetIsExactAndDurableAcrossStoreInstances() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-pause-cas-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = FileCloudSyncPauseStateStore(directory: directory)
    #expect(
      try await first.compareAndSetPauseReason(
        expected: nil, replacement: .accountChanged))
    let firstAccountChanged = try #require(try await first.loadPauseSnapshot())
    #expect(
      try await first.compareAndSetPauseReason(
        expected: nil, replacement: .adoptionInProgress) == false)
    #expect(try await first.loadPauseReason() == .accountChanged)
    #expect(
      try await first.compareAndSetPauseReason(
        expected: .accountChanged, replacement: .adoptionInProgress))

    let relaunched = FileCloudSyncPauseStateStore(directory: directory)
    #expect(try await relaunched.loadPauseReason() == .adoptionInProgress)
    #expect(
      try await relaunched.compareAndSetPauseReason(
        expected: .adoptionInProgress, replacement: .backfillFailed))
    #expect(
      try await relaunched.compareAndSetPauseReason(
        expected: .backfillFailed, replacement: nil))
    #expect(try await FileCloudSyncPauseStateStore(directory: directory).loadPauseReason() == nil)

    // Clearing the active reason retains a durable revision watermark. A
    // relaunch followed by the same reason must not recreate the first event's
    // identity and accidentally authorize an old confirmation.
    let afterClearRelaunch = FileCloudSyncPauseStateStore(directory: directory)
    try await afterClearRelaunch.savePauseReason(.accountChanged)
    let secondAccountChanged = try #require(
      try await afterClearRelaunch.loadPauseSnapshot())
    #expect(secondAccountChanged.revision > firstAccountChanged.revision)
    #expect(
      try await afterClearRelaunch.compareAndSetPauseSnapshot(
        expected: firstAccountChanged, replacement: .adoptionInProgress)
        == .rejected)
  }
}
