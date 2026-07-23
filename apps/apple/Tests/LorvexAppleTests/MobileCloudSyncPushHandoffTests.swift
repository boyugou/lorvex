import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import LorvexSync
import Testing

@testable import LorvexMobile

// MARK: - Helpers

private let handoffZoneID = CKRecordZone.ID(
  zoneName: CloudSyncZoneConstants.zoneName, ownerName: CKCurrentUserDefaultName)

private func handoffEnvelope() -> SyncEnvelope {
  SyncEnvelope(
    entityType: .task,
    entityId: "01966a3f-7c8b-7d4e-8f3a-000000000042",
    operation: .upsert,
    version: try! Hlc.parse("1711234567894_0000_a1b2c3d4a1b2c3d4"),
    payloadSchemaVersion: 1,
    payload: #"{"title":"pushed"}"#,
    deviceId: "device-001")
}

private func makeSuiteDefaults(_ suiteName: String) throws -> UserDefaults {
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  return defaults
}

/// A live-mode store over the given defaults whose fetcher returns one inbound
/// record, so a triggered drain observably applies data (`.newData`).
@MainActor
private func makeLiveStoreWithInboundRecord(
  core: StubFocusCoreService,
  defaults: UserDefaults
) -> MobileStore {
  let record = CloudSyncEnvelopeRecord.makeRecord(handoffEnvelope(), zoneID: handoffZoneID)
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: .available),
    pusher: RecordingRecordPusher(),
    fetcher: StubRemoteChangeFetcher(records: [record], serverChangeTokenData: Data([0x02])),
    // The fail-closed start gate needs a confirmed identity for cycles to run.
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  return MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator)
}

// MARK: - Handoff persistence

@Test
func mobilePushHandoffAcknowledgesOnlyItsCurrentToken() throws {
  let suiteName = "test.mobile.pushHandoff.\(UUID().uuidString)"
  let defaults = try makeSuiteDefaults(suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let handoff = MobileCloudSyncPushHandoff(defaults: defaults)

  #expect(handoff.hasPendingPush == false)
  let first = handoff.recordPendingPush()
  #expect(handoff.hasPendingPush == true)
  #expect(handoff.pendingToken == first)

  let newer = handoff.recordPendingPush()
  #expect(newer != first)
  #expect(!handoff.acknowledgePendingPush(token: first))
  #expect(handoff.pendingToken == newer, "an older waiter cannot clear newer push debt")

  #expect(handoff.acknowledgePendingPush(token: newer))
  #expect(handoff.hasPendingPush == false)
  #expect(!handoff.acknowledgePendingPush(token: newer), "acknowledgement is one-shot")
}

// MARK: - Consumption on store attachment

@MainActor
@Test
func mobilePendingPushHandoffTriggersDrainOnAttachmentAndClearsFlag() async throws {
  let suiteName = "test.mobile.pushHandoff.\(UUID().uuidString)"
  let defaults = try makeSuiteDefaults(suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  // The push arrived before the store was attached: the delegate persisted the
  // handoff and its in-process notification found no observer.
  MobileCloudSyncPushHandoff(defaults: defaults).recordPendingPush()

  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = makeLiveStoreWithInboundRecord(core: core, defaults: defaults)

  let result = await store.consumePendingCloudSyncPushHandoffIfNeeded()

  #expect(result == .newData, "the deferred drain must run and report the applied data")
  #expect(core.appliedInboundBatchCount() == 1, "the inbound backlog must actually drain")
  #expect(core.loadTodayCallCount > 0, "the drain runs the full refresh fan-out")
  #expect(MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush == false)
}

@MainActor
@Test
func mobileConsumeWithoutPendingPushHandoffDoesNothing() async throws {
  let suiteName = "test.mobile.pushHandoff.\(UUID().uuidString)"
  let defaults = try makeSuiteDefaults(suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = makeLiveStoreWithInboundRecord(core: core, defaults: defaults)

  let result = await store.consumePendingCloudSyncPushHandoffIfNeeded()

  #expect(result == nil, "no handoff means no drain is owed")
  #expect(core.loadTodayCallCount == 0)
  #expect(core.appliedInboundBatchCount() == 0)
}

// MARK: - Any drain pays the debt exactly once

@MainActor
@Test
func mobileRemoteChangeDrainConsumesPendingPushHandoff() async throws {
  let suiteName = "test.mobile.pushHandoff.\(UUID().uuidString)"
  let defaults = try makeSuiteDefaults(suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  MobileCloudSyncPushHandoff(defaults: defaults).recordPendingPush()

  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = makeLiveStoreWithInboundRecord(core: core, defaults: defaults)

  // The posted notification did find a running observer: that drain pays the
  // debt, so the later attachment consume must not run a duplicate drain.
  _ = await store.handleCloudKitRemoteChange()
  #expect(MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush == false)

  let duplicate = await store.consumePendingCloudSyncPushHandoffIfNeeded()
  #expect(duplicate == nil)
}

@MainActor
@Test
func mobileFailedActiveDrainKeepsPendingPushToken() async throws {
  let suiteName = "test.mobile.pushHandoff.failed.\(UUID().uuidString)"
  let defaults = try makeSuiteDefaults(suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let envelope = handoffEnvelope()
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [PendingOutboundEnvelope(outboxId: 11, envelope: envelope)]
  let failingName = CloudSyncEnvelopeRecord.recordName(
    entityType: envelope.entityType.asString, entityId: envelope.entityId)
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: .available),
    pusher: RecordingRecordPusher(failingRecordNames: [failingName]),
    fetcher: StubRemoteChangeFetcher(records: []),
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator)

  let result = await store.handleCloudKitRemoteChange()

  #expect(result == .failed)
  #expect(
    MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush,
    "a failed cycle did not pay the durable push debt and must not acknowledge it")
}

@MainActor
@Test
func mobileForegroundRefreshConsumesPendingPushHandoff() async throws {
  let suiteName = "test.mobile.pushHandoff.\(UUID().uuidString)"
  let defaults = try makeSuiteDefaults(suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  MobileCloudSyncPushHandoff(defaults: defaults).recordPendingPush()

  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = makeLiveStoreWithInboundRecord(core: core, defaults: defaults)

  // Scene-active runs the pacing-resetting full refresh; its sync cycle is the
  // drain the push asked for, so the handoff is consumed by it.
  _ = await store.refreshResettingCloudSyncPacing()

  #expect(MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush == false)
  let duplicate = await store.consumePendingCloudSyncPushHandoffIfNeeded()
  #expect(duplicate == nil)
}

// MARK: - F2: bounded background silent-push drain

/// A live store whose pusher BLOCKS, so a background-push drain cannot finish and
/// its safety deadline must fire.
@MainActor
private func makeLiveStoreWithBlockingPusher(
  core: StubFocusCoreService,
  pusher: BlockingRecordPusher,
  defaults: UserDefaults
) -> MobileStore {
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: .available),
    pusher: pusher,
    fetcher: StubRemoteChangeFetcher(records: []),
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  return MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator)
}

@MainActor
@Test
func mobileBackgroundPushDrainRecordsHandoffDrainsAndSkipsFanOut() async throws {
  let suiteName = "test.mobile.pushHandoff.\(UUID().uuidString)"
  let defaults = try makeSuiteDefaults(suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = makeLiveStoreWithInboundRecord(core: core, defaults: defaults)

  let result = await store.drainCloudSyncForBackgroundPush(deadline: 5)

  #expect(result == .newData, "the bounded drain applies the inbound record")
  #expect(core.appliedInboundBatchCount() == 1, "the inbound backlog actually drains")
  #expect(
    core.loadTodayCallCount == 0,
    "the push handler must NOT run the full refresh fan-out (snapshot/reminder/badge)")
  #expect(
    MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush == true,
    "the pending push is recorded FIRST so a later foreground refresh runs the fan-out")
}

@MainActor
@Test
func mobileActivePushRunsFullFanOutWhileInactivePushLeavesHandoff() async throws {
  let activeSuite = "test.mobile.pushHandoff.active.\(UUID().uuidString)"
  let activeDefaults = try makeSuiteDefaults(activeSuite)
  defer { activeDefaults.removePersistentDomain(forName: activeSuite) }
  let activeCore = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let activeStore = makeLiveStoreWithInboundRecord(core: activeCore, defaults: activeDefaults)

  let activeResult = await activeStore.handleCloudKitPush(applicationIsActive: true)

  #expect(activeResult == .newData)
  #expect(activeCore.loadTodayCallCount > 0, "an active push must refresh visible surfaces")
  #expect(MobileCloudSyncPushHandoff(defaults: activeDefaults).hasPendingPush == false)

  let inactiveSuite = "test.mobile.pushHandoff.inactive.\(UUID().uuidString)"
  let inactiveDefaults = try makeSuiteDefaults(inactiveSuite)
  defer { inactiveDefaults.removePersistentDomain(forName: inactiveSuite) }
  let inactiveCore = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let inactiveStore = makeLiveStoreWithInboundRecord(
    core: inactiveCore, defaults: inactiveDefaults)

  let inactiveResult = await inactiveStore.handleCloudKitPush(
    applicationIsActive: false, backgroundDeadline: 5)

  #expect(inactiveResult == .newData)
  #expect(inactiveCore.loadTodayCallCount == 0, "an inactive push stays sync-only")
  #expect(MobileCloudSyncPushHandoff(defaults: inactiveDefaults).hasPendingPush)
}

@MainActor
@Test
func mobileBackgroundPushDrainReturnsWithinDeadlineWhenDrainBlocks() async throws {
  let suiteName = "test.mobile.pushHandoff.\(UUID().uuidString)"
  let defaults = try makeSuiteDefaults(suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [
    PendingOutboundEnvelope(outboxId: 11, envelope: handoffEnvelope())
  ]
  let pusher = BlockingRecordPusher()
  let store = makeLiveStoreWithBlockingPusher(core: core, pusher: pusher, defaults: defaults)

  // The pusher blocks until `releasePush()` below, which runs only AFTER the
  // call returns. So the call returning at all — with the drain still blocked —
  // is the proof the deadline cut in rather than waiting for the drain. (A broken
  // deadline would hang here forever, not return late.)
  let result = await store.drainCloudSyncForBackgroundPush(deadline: 0.2)

  #expect(result == .noData, "a deadline cutoff reports no confirmed data within budget")
  #expect(
    store.lastCloudSyncCycleReport == nil,
    "the handler returns at the deadline WITHOUT the still-blocked drain completing")
  #expect(
    MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush == true,
    "the pending push is recorded before the drain, so the debt survives the cutoff")
  // Release the blocked drain so its background task completes.
  await pusher.releasePush()
}

@MainActor
@Test
func mobileActivePushReturnsWithinDeadlineAndFinishesFanOutBestEffort() async throws {
  let suiteName = "test.mobile.pushHandoff.activeDeadline.\(UUID().uuidString)"
  let defaults = try makeSuiteDefaults(suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [
    PendingOutboundEnvelope(outboxId: 11, envelope: handoffEnvelope())
  ]
  let pusher = BlockingRecordPusher()
  let store = makeLiveStoreWithBlockingPusher(core: core, pusher: pusher, defaults: defaults)

  let handler = Task {
    await store.handleCloudKitPush(
      applicationIsActive: true, backgroundDeadline: 0.2)
  }
  // Under a loaded full suite the deadline may fire before the refresh reaches
  // the pusher. Wait until the continuation is definitely installed before the
  // later release, otherwise an early release would be lost and test the fake
  // rather than the production deadline path.
  await pusher.waitForPushToStart()
  let result = await handler.value

  #expect(result == .noData, "the delegate deadline wins while the refresh is blocked")
  #expect(store.lastCloudSyncCycleReport == nil)
  #expect(
    MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush,
    "foreground push debt remains durable until the full refresh actually finishes")

  await pusher.releasePush()
  for _ in 0..<200
  where MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush {
    try await Task.sleep(for: .milliseconds(5))
  }

  #expect(store.lastCloudSyncCycleReport?.pushedRecordCount == 1)
  #expect(
    !MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush,
    "the best-effort foreground fan-out clears its durable handoff on completion")
}
