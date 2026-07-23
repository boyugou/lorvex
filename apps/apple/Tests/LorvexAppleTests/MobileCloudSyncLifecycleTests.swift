import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync
import Testing
import LorvexCloudSync

@testable import LorvexMobile

// MARK: - Helpers
//
// `StubFocusCoreService` (in MobileStoreFocusCoreStub.swift) is the core double:
// it conforms to both `LorvexCoreServicing` and `EnvelopeSyncServicing`, so the
// coordinator's `runDrainingCycle(core:)` cast succeeds and exercises the real
// outbound/inbound orchestration against its recorded transport seam and real
// in-memory generation/traversal state.

private let mobileSyncZoneID = CKRecordZone.ID(
  zoneName: CloudSyncZoneConstants.zoneName, ownerName: CKCurrentUserDefaultName)

private func mobileEnvelope(_ id: String, _ n: Int) -> SyncEnvelope {
  SyncEnvelope(
    entityType: .task,
    entityId: id,
    operation: .upsert,
    version: try! Hlc.parse("171123456789\(n)_0000_a1b2c3d4a1b2c3d4"),
    payloadSchemaVersion: 1,
    payload: #"{"title":"t\#(n)"}"#,
    deviceId: "device-001")
}

actor BlockingRecordPusher: CloudSyncRecordPushing {
  private var pushStartedContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private(set) var pushCallCount = 0

  func ensureZone() async throws {}
  func invalidateZoneCache() async {}

  func push(
    _ records: [CKRecord], context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    pushCallCount += 1
    pushStartedContinuation?.resume()
    pushStartedContinuation = nil
    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
    return records.map { record in
      CloudSyncPushResult(recordName: record.recordID.recordName, succeeded: true)
    }
  }

  func waitForPushToStart() async {
    if pushCallCount > 0 { return }
    await withCheckedContinuation { continuation in
      pushStartedContinuation = continuation
    }
  }

  func releasePush() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

actor BlockingCloudSyncSubscriber: CloudSyncSubscribing {
  private var registrationStartedContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private(set) var callCount = 0

  func registerSubscription() async throws {
    callCount += 1
    registrationStartedContinuation?.resume()
    registrationStartedContinuation = nil
    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
  }

  func waitForRegistrationToStart() async {
    if callCount > 0 { return }
    await withCheckedContinuation { continuation in
      registrationStartedContinuation = continuation
    }
  }

  func releaseRegistration() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

@MainActor
private func makeLiveStore(
  core: any LorvexCoreServicing,
  pusher: any CloudSyncRecordPushing = RecordingRecordPusher(),
  fetcher: any CloudSyncRemoteChangeFetching = StubRemoteChangeFetcher(records: []),
  account: CloudKitAccountAvailability = .available
) -> MobileStore {
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: account),
    pusher: pusher,
    fetcher: fetcher,
    // The fail-closed start gate needs a confirmed identity for cycles to run.
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  return MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator)
}

// MARK: - Subscription registration

@MainActor
@Test
func mobileStoreRegistersSubscriptionOnFirstRefreshOnly() async throws {
  let subscriber = RecordingCloudSyncSubscriber()
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    cloudSyncSubscriber: subscriber)

  await store.refresh()
  #expect(store.hasRegisteredSubscription == true)
  #expect(await subscriber.registrationCallCount() == 1)
  #expect(store.lastCloudSyncSubscriptionErrorMessage == nil)

  await store.refresh()
  #expect(await subscriber.registrationCallCount() == 1)
}

@MainActor
@Test
func mobileStoreRetriesSubscriptionAfterFailure() async throws {
  let subscriber = FlakyCloudSyncSubscriber()
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    cloudSyncSubscriber: subscriber)

  await store.refresh()
  #expect(store.hasRegisteredSubscription == false)
  #expect(
    store.lastCloudSyncSubscriptionErrorMessage == store.userFacingErrorCopy.somethingWentWrong)
  let logs = try await core.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  let entry = try #require(
    logs.entries.first { $0.origin == "ios.cloud_sync.subscription" })
  #expect(entry.details?.contains("CKError") == true)

  await store.refresh()
  #expect(store.hasRegisteredSubscription == true)
  #expect(store.lastCloudSyncSubscriptionErrorMessage == nil)
  #expect(await subscriber.registrationCallCount() == 2)
}

// MARK: - Account change

@MainActor
@Test
func mobileSameAccountChangeResetsSubscriptionAndPacing() async throws {
  let subscriber = RecordingCloudSyncSubscriber()
  let fetcher = ScriptedMoreComingFetcher(
    moreComingScript: [false, false], tokenData: Data([0x62]))
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(),
    pusher: RecordingRecordPusher(),
    fetcher: fetcher,
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    cloudSyncMode: .live,
    cloudSyncSubscriber: subscriber,
    cloudSyncCoordinator: coordinator)

  await store.refresh()
  #expect(store.hasRegisteredSubscription == true)
  store.cloudSyncPacing.recordFailure()
  #expect(store.cloudSyncPacing.consecutiveFailures == 1)
  let fetchesBeforeRecovery = await fetcher.callCount

  await store.handleCloudKitAccountChange()

  // The notification itself resumes subscription + sync; waiting for the next
  // scene activation would strand a retry whose unavailable-account wake was
  // already canceled.
  #expect(store.hasRegisteredSubscription == true)
  #expect(store.cloudSyncPacing.consecutiveFailures == 0)
  #expect(await subscriber.registrationCallCount() == 2)
  #expect(await fetcher.callCount > fetchesBeforeRecovery)
}

@MainActor
@Test
func mobileFirstAccountNotificationRecoversPriorUnavailablePauseAndDrains() async throws {
  let subscriber = RecordingCloudSyncSubscriber()
  let accountIdentifier = MutableAccountIdentifier(nil)
  let pauseStore = RecordingCloudSyncPauseStore()
  let fetcher = ScriptedMoreComingFetcher(
    moreComingScript: [false], tokenData: Data([0x64]))
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(),
    pusher: RecordingRecordPusher(),
    fetcher: fetcher,
    accountIdentifier: accountIdentifier,
    accountIdentityStore: RecordingAccountIdentityStore(),
    accountPauseStore: pauseStore)
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    cloudSyncMode: .live,
    cloudSyncSubscriber: subscriber,
    cloudSyncCoordinator: coordinator)

  await store.handleCloudKitAccountChange()
  #expect(await pauseStore.reason == .accountChanged)
  #expect(store.cloudSyncPauseReason == .accountChanged)
  #expect(store.hasRegisteredSubscription == false)
  #expect(await subscriber.registrationCallCount() == 0)
  #expect(await fetcher.callCount == 0)

  await accountIdentifier.set("account-A")
  await store.handleCloudKitAccountChange()

  #expect(await pauseStore.reason == nil)
  #expect(store.cloudSyncPauseReason == nil)
  #expect(store.hasRegisteredSubscription == true)
  #expect(await subscriber.registrationCallCount() == 1)
  #expect(await fetcher.callCount > 0)
}

// MARK: - Remote push handling

@MainActor
@Test
func mobileRemoteChangeRefreshesAndResetsPacing() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" })
  store.cloudSyncPacing.recordFailure()
  store.cloudSyncPacing.recordFailure()
  #expect(store.cloudSyncPacing.consecutiveFailures == 2)

  await store.handleCloudKitRemoteChange()

  #expect(store.cloudSyncPacing.consecutiveFailures == 0)
  #expect(store.snapshot.today.tasks.isEmpty == false)
}

@MainActor
@Test
func mobileRefreshLoadsLocalFirstThenReloadsAfterInboundDrain() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let record = CloudSyncEnvelopeRecord.makeRecord(
    mobileEnvelope("01966a3f-7c8b-7d4e-8f3a-000000000010", 3),
    zoneID: mobileSyncZoneID
  )
  let store = makeLiveStore(
    core: core,
    fetcher: StubRemoteChangeFetcher(records: [record], serverChangeTokenData: Data([0x02]))
  )

  let result = await store.refresh()

  #expect(result == .newData)
  // The refresh loads local surfaces FIRST (before the CloudKit cycle) so the UI
  // shows on-disk data immediately, then reloads once the cycle pulls new data.
  // So the first `loadToday` sees no applied inbound and the last, after the
  // drain, sees the fetched batch — the pulled record lands in the same refresh.
  #expect(core.loadTodayAppliedInboundBatchCounts.count == 2)
  #expect(core.loadTodayAppliedInboundBatchCounts.first == 0)
  #expect(core.loadTodayAppliedInboundBatchCounts.last == 1)
  #expect(store.lastCloudSyncCycleReport?.fetchedRecordCount == 1)
}

@MainActor
@Test
func mobileRefreshPublishesLocalSnapshotBeforeSubscriptionRegistration() async throws {
  // Registering the CloudKit push subscription is a real network request on the
  // first cold-start refresh, so it must happen AFTER the local snapshot is
  // published — otherwise a slow/hung network leaves the UI blank. This blocks
  // registration and asserts the on-disk data is already visible by the time it
  // starts.
  let subscriber = BlockingCloudSyncSubscriber()
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    cloudSyncSubscriber: subscriber)

  #expect(store.snapshot.today == .empty)
  let refreshTask = Task { await store.refresh() }
  await subscriber.waitForRegistrationToStart()

  // Registration has started and is blocked; the local snapshot must already be
  // populated from the on-disk store — the refresh loaded it before touching the
  // network.
  #expect(store.snapshot.today != .empty)

  await subscriber.releaseRegistration()
  _ = await refreshTask.value
}

@MainActor
@Test
func mobileDatabaseChangeSignalObserverRefreshesStore() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  store.startLifetimeObserversIfNeeded()
  defer {
    for task in store.lifetimeObserverTasks { task.cancel() }
    store.lifetimeObserverTasks = []
  }

  for _ in 0..<20 where core.loadTodayCallCount == 0 {
    NotificationCenter.default.post(name: DatabaseChangeSignal.didChangeNotification, object: nil)
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(core.loadTodayCallCount > 0)
}

@MainActor
@Test
func mobileDatabaseChangeSignalIdentifiesItsOwnOrigin() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  let otherStore = MobileStore(
    core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  #expect(store.databaseChangeOriginIsSelf(Notification(
    name: DatabaseChangeSignal.didChangeNotification, object: store)))
  #expect(!store.databaseChangeOriginIsSelf(Notification(
    name: DatabaseChangeSignal.didChangeNotification, object: otherStore)))
  #expect(!store.databaseChangeOriginIsSelf(Notification(
    name: DatabaseChangeSignal.didChangeNotification, object: nil)))
}

// MARK: - Sync cycle

@MainActor
@Test
func mobileCycleNoOpsWhenSyncModeIsOff() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" })  // cloudSyncMode defaults to .off

  await store.runCloudSyncCycle()

  #expect(store.lastCloudSyncCycleReport == nil)
  #expect(store.cloudSyncPacing.lastAttemptAt == nil)
}

@MainActor
@Test
func mobileSettingsCloudSyncModePersistsReconfiguresAndRegistersLive() async throws {
  let suiteName = "test.mobile.cloudSyncMode.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  let liveSubscriber = RecordingCloudSyncSubscriber()
  let offSubscriber = RecordingCloudSyncSubscriber()
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncServiceFactory: { mode in
      MobileCloudSyncServices(
        subscriber: mode == .live ? liveSubscriber : offSubscriber,
        coordinator: nil
      )
    }
  )

  await store.setCloudSyncModeFromSettings(.live)

  #expect(store.cloudSyncMode == .live)
  #expect(MobileSetupPreferences(defaults: defaults).cloudSyncMode == .live)
  #expect(store.hasRegisteredSubscription == true)
  #expect(await liveSubscriber.registrationCallCount() == 1)

  await store.setCloudSyncModeFromSettings(.off)
  await store.runCloudSyncCycle()

  #expect(store.cloudSyncMode == .off)
  #expect(MobileSetupPreferences(defaults: defaults).cloudSyncMode == .off)
  #expect(store.lastCloudSyncCycleReport == nil)
  #expect(await offSubscriber.registrationCallCount() == 0)
}

@MainActor
@Test
func mobileCloudSyncModeChangeQueuesUntilDataImportFinishes() async throws {
  let suiteName = "test.mobile.cloudSyncImportMode.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let subscriber = RecordingCloudSyncSubscriber()
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncServiceFactory: { mode in
      MobileCloudSyncServices(
        subscriber: mode == .live ? subscriber : NoOpCloudSyncSubscriber(),
        coordinator: nil)
    })
  store.isDataImportRunning = true

  await store.setCloudSyncModeFromSettings(.live)

  #expect(store.cloudSyncMode == .off)
  #expect(store.pendingCloudSyncMode == .live)
  #expect(store.cloudSyncModeTarget == .live)
  #expect(await subscriber.registrationCallCount() == 0)

  store.isDataImportRunning = false
  await store.applyPendingCloudSyncModeIfNeeded()

  #expect(store.cloudSyncMode == .live)
  #expect(store.pendingCloudSyncMode == nil)
  #expect(MobileSetupPreferences(defaults: defaults).cloudSyncMode == .live)
  #expect(await subscriber.registrationCallCount() == 1)
}

@MainActor
@Test
func mobileCloudSyncStatusReportUsesStoreLiveFields() async throws {
  let successDate = Date(timeIntervalSince1970: 1_779_465_600)
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    cloudSyncMode: .live
  )

  store.cloudKitAccountAvailability = .restricted
  store.lastCloudSyncRemoteChangeSucceededAt = successDate
  store.lastCloudSyncRemoteChangeErrorMessage = "remote failed"
  store.lastCloudSyncSubscriptionErrorMessage = "subscription failed"

  let report = store.mobileCloudSyncStatusReport

  #expect(report.mode == .live)
  #expect(report.accountAvailability == .restricted)
  #expect(report.lastPullAt == successDate)
  #expect(report.lastPullError == "remote failed")
  #expect(report.lastPushError == "subscription failed")
}

@MainActor
@Test
func mobileCloudSyncCycleRecordsUnavailableAccountState() async throws {
  let store = makeLiveStore(core: StubFocusCoreService(preview: try await makeSeededInMemoryCore()), account: .noAccount)

  let result = await store.runCloudSyncCycle()

  #expect(result == .noData)
  #expect(store.cloudKitAccountAvailability == .noAccount)
  #expect(store.lastCloudSyncCycleReport == nil)
}

@MainActor
@Test
func mobileCloudSyncSettingsChangeRefreshesDiagnostics() async throws {
  let suiteName = "test.mobile.cloudSyncMode.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncServiceFactory: { _ in
      MobileCloudSyncServices(subscriber: NoOpCloudSyncSubscriber(), coordinator: nil)
    }
  )

  await store.setCloudSyncModeFromSettings(.live)

  #expect(core.loadRuntimeDiagnosticsCallCount == 1)
}

@MainActor
@Test
func mobileCloudSyncModeChangeMidTransitionQueuesAndAppliesAfter() async throws {
  // An explicit mode request landing while a transition is in flight —
  // especially turning sync OFF — must not be silently dropped. It is queued
  // (latest wins), the picker reflects the queued target, and it applies
  // atomically once the active transition completes.
  let suiteName = "test.mobile.cloudSyncMode.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let subscriber = BlockingCloudSyncSubscriber()
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncServiceFactory: { mode in
      MobileCloudSyncServices(
        subscriber: mode == .live ? subscriber : NoOpCloudSyncSubscriber(),
        coordinator: nil
      )
    }
  )

  let first = Task { await store.setCloudSyncModeFromSettings(.live) }
  await subscriber.waitForRegistrationToStart()

  await store.setCloudSyncModeFromSettings(.off)
  #expect(store.isSettingCloudSyncMode == true)
  #expect(store.pendingCloudSyncMode == .off, "the OFF request is queued, not dropped")
  #expect(store.cloudSyncModeTarget == .off, "the picker reflects the pending target")
  #expect(await subscriber.callCount == 1, "the in-flight transition is not interrupted")

  await subscriber.releaseRegistration()
  await first.value

  #expect(store.cloudSyncMode == .off, "the queued OFF applies once the transition completes")
  #expect(store.pendingCloudSyncMode == nil)
  #expect(store.cloudSyncModeTarget == .off)
  #expect(MobileSetupPreferences(defaults: defaults).cloudSyncMode == .off)
  #expect(store.isSettingCloudSyncMode == false)
  #expect(await subscriber.callCount == 1)
}

@MainActor
@Test
func mobileCloudSyncModeQueueKeepsOnlyLatestRequest() async throws {
  // Two toggles during one transition: only the latest queued target matters.
  // Re-queuing the transition's own target ends as a no-op apply (no second
  // service rebuild).
  let suiteName = "test.mobile.cloudSyncMode.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let subscriber = BlockingCloudSyncSubscriber()
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncServiceFactory: { mode in
      MobileCloudSyncServices(
        subscriber: mode == .live ? subscriber : NoOpCloudSyncSubscriber(),
        coordinator: nil
      )
    }
  )

  let first = Task { await store.setCloudSyncModeFromSettings(.live) }
  await subscriber.waitForRegistrationToStart()

  await store.setCloudSyncModeFromSettings(.off)
  await store.setCloudSyncModeFromSettings(.live)
  #expect(store.pendingCloudSyncMode == .live)
  #expect(store.cloudSyncModeTarget == .live)

  await subscriber.releaseRegistration()
  await first.value

  #expect(store.cloudSyncMode == .live)
  #expect(store.pendingCloudSyncMode == nil)
  #expect(MobileSetupPreferences(defaults: defaults).cloudSyncMode == .live)
  #expect(
    await subscriber.callCount == 1,
    "re-queuing the already-active target must not rebuild services")
}

/// Counts `cloudSyncServiceFactory` invocations, so a test can prove the mode-swap
/// did (or did not) construct a second store actor set.
final class CloudSyncServiceFactoryCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  func increment() { lock.lock(); value += 1; lock.unlock() }
  var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
@Test
func mobileCloudSyncModeSwapDeferredWhileCycleRunningThenAppliedAtCycleEnd() async throws {
  // FND-CC-1: rebuilding the coordinator's file-backed store actor set over the
  // same sync-state directory while a sync cycle's detached task still holds the
  // current set would put two actor sets over one DB dir (server-change-token
  // resurrection + loss of the deletion-pause flag). The swap must not rebuild
  // mid-cycle — but the request is queued rather than dropped, and the cycle's
  // completion applies it without another toggle, so only one store actor set is
  // ever live per directory AND the user's explicit intent survives.
  let suiteName = "test.mobile.cloudSyncMode.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  MobileSetupPreferences(defaults: defaults).setCloudSyncMode(.live)
  let factoryCalls = CloudSyncServiceFactoryCounter()
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [
    PendingOutboundEnvelope(outboxId: 11, envelope: mobileEnvelope(
      "01966a3f-7c8b-7d4e-8f3a-000000000001", 1))
  ]
  let pusher = BlockingRecordPusher()
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: .available),
    pusher: pusher,
    fetcher: StubRemoteChangeFetcher(records: []),
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator,
    cloudSyncServiceFactory: { _ in
      factoryCalls.increment()
      return MobileCloudSyncServices(subscriber: NoOpCloudSyncSubscriber(), coordinator: nil)
    }
  )

  // A real cycle is in flight: its detached task still holds the current
  // per-directory store actor set.
  let cycle = Task { await store.runCloudSyncCycle() }
  await pusher.waitForPushToStart()
  await store.setCloudSyncModeFromSettings(.off)

  #expect(store.cloudSyncMode == .live, "the swap must not rebuild the store mid-cycle")
  #expect(factoryCalls.count == 0, "no second store actor set may be constructed mid-cycle")
  #expect(store.isSettingCloudSyncMode == false)
  #expect(store.pendingCloudSyncMode == .off, "the request is queued, not dropped")
  #expect(store.cloudSyncModeTarget == .off, "the picker reflects the queued target")
  #expect(
    MobileSetupPreferences(defaults: defaults).cloudSyncMode == .live,
    "the mode is persisted only when it is actually applied")

  // The cycle finishes: its completion applies the queued mode by itself and
  // rebuilds exactly one set.
  await pusher.releasePush()
  _ = await cycle.value

  #expect(store.cloudSyncMode == .off)
  #expect(MobileSetupPreferences(defaults: defaults).cloudSyncMode == .off)
  #expect(factoryCalls.count == 1)
  #expect(store.pendingCloudSyncMode == nil)
}

@MainActor
@Test
func mobileCycleNoOpsWhenLiveWithoutCoordinator() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    cloudSyncMode: .live)  // no coordinator

  await store.runCloudSyncCycle()

  #expect(store.lastCloudSyncCycleReport == nil)
}

@MainActor
@Test
func mobileCycleDrainsOutboxAndRecordsSuccess() async throws {
  let id1 = "01966a3f-7c8b-7d4e-8f3a-000000000001"
  let id2 = "01966a3f-7c8b-7d4e-8f3a-000000000002"
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [
    PendingOutboundEnvelope(outboxId: 11, envelope: mobileEnvelope(id1, 1)),
    PendingOutboundEnvelope(outboxId: 22, envelope: mobileEnvelope(id2, 2)),
  ]
  let store = makeLiveStore(core: core)

  await store.runCloudSyncCycle()

  #expect(store.lastCloudSyncCycleReport?.pushedRecordCount == 2)
  #expect(store.lastCloudSyncCycleReport?.failedPushCount == 0)
  #expect(store.lastCloudSyncRemoteChangeSucceededAt != nil)
  #expect(store.lastCloudSyncRemoteChangeErrorMessage == nil)
  #expect(store.cloudSyncPacing.consecutiveFailures == 0)
  #expect(Set(core.markedSyncedIDs) == [11, 22])
}

@MainActor
@Test
func mobileCycleCoalescesOverlappingTriggersAndRetainsProgress() async throws {
  let id1 = "01966a3f-7c8b-7d4e-8f3a-000000000001"
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [
    PendingOutboundEnvelope(outboxId: 11, envelope: mobileEnvelope(id1, 1))
  ]
  let pusher = BlockingRecordPusher()
  let store = makeLiveStore(core: core, pusher: pusher)

  let first = Task { await store.runCloudSyncCycle() }
  await pusher.waitForPushToStart()

  let overlapping = Task { await store.runCloudSyncCycle() }
  for _ in 0..<1_000 where !store.cloudSyncCycleFlight.isPendingRerun {
    await Task.yield()
  }
  #expect(store.cloudSyncCycleFlight.isPendingRerun)
  #expect(await pusher.pushCallCount == 1)

  // The production core removes confirmed outbox rows. This lightweight fake
  // records confirmations separately, so mirror the resulting second-pass view
  // explicitly before releasing the first push.
  core.outboxPending = []
  await pusher.releasePush()
  let firstResult = await first.value
  let overlappingResult = await overlapping.value

  #expect(firstResult == .newData)
  #expect(
    overlappingResult == .newData,
    "the trailing no-op pass must not erase progress made by the first pass")
  #expect(await pusher.pushCallCount == 1)
  #expect(Set(core.markedSyncedIDs) == [11])
  #expect(
    store.lastCloudSyncCycleReport?.pushedRecordCount == 1,
    "the trailing pass must retain the first pass's report for post-cycle fan-out")
}

@MainActor
@Test
func mobileCycleRecordsFailureWhenPushMakesNoProgress() async throws {
  let id1 = "01966a3f-7c8b-7d4e-8f3a-000000000001"
  let failingName = CloudSyncEnvelopeRecord.recordName(entityType: "task", entityId: id1)
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [
    PendingOutboundEnvelope(outboxId: 11, envelope: mobileEnvelope(id1, 1))
  ]
  let store = makeLiveStore(
    core: core, pusher: RecordingRecordPusher(failingRecordNames: [failingName]))

  await store.runCloudSyncCycle()

  #expect(store.lastCloudSyncCycleReport?.pushedRecordCount == 0)
  #expect(store.lastCloudSyncCycleReport?.failedPushCount == 1)
  #expect(store.cloudSyncPacing.consecutiveFailures == 1)
  #expect(store.lastCloudSyncRemoteChangeErrorMessage != nil)
}

@MainActor
@Test
func mobileCycleSkippedWhenCircuitBreakerOpen() async throws {
  let id1 = "01966a3f-7c8b-7d4e-8f3a-000000000001"
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [
    PendingOutboundEnvelope(outboxId: 11, envelope: mobileEnvelope(id1, 1))
  ]
  let store = makeLiveStore(core: core)
  for _ in 0..<CloudSyncPacing.circuitBreakerThreshold {
    store.cloudSyncPacing.recordFailure()
  }
  #expect(store.cloudSyncPacing.isCircuitBreakerOpen == true)

  await store.runCloudSyncCycle()

  // The gate blocked the cycle: no attempt stamped, no push performed.
  #expect(store.cloudSyncPacing.lastAttemptAt == nil)
  #expect(store.lastCloudSyncCycleReport == nil)
  #expect(core.markedSyncedIDs.isEmpty)
}

// MARK: - Shared CloudSync factory wiring

@Test
func cloudSyncFactoryResolvesOffToNoOpServices() {
  let mode = CloudSyncFactory.resolveMode(persistedMode: .off, environment: [:])
  #expect(mode == .off)
  #expect(CloudSyncFactory.makeSubscriber(mode: mode) is NoOpCloudSyncSubscriber)
  #expect(
    CloudSyncFactory.makeCoordinator(
      mode: mode, stateDirectory: FileManager.default.temporaryDirectory) == nil)
}

@Test
func cloudSyncFactoryResolvesRecordPlanToSubscriberButNoCoordinator() {
  let mode = CloudSyncFactory.resolveMode(persistedMode: .recordPlan, environment: [:])
  #expect(mode == .recordPlan)
  #expect(CloudSyncFactory.makeSubscriber(mode: mode) is CloudKitCloudSyncSubscriber)
  #expect(
    CloudSyncFactory.makeCoordinator(
      mode: mode, stateDirectory: FileManager.default.temporaryDirectory) == nil)
}

@Test
func cloudSyncFactoryResolvesLiveToCoordinator() {
  let mode = CloudSyncFactory.resolveMode(persistedMode: .live, environment: [:])
  #expect(mode == .live)
  #expect(CloudSyncFactory.makeSubscriber(mode: mode) is CloudKitCloudSyncSubscriber)
  #expect(
    CloudSyncFactory.makeCoordinator(
      mode: mode, stateDirectory: FileManager.default.temporaryDirectory) != nil)
}

@Test
func cloudSyncFactoryEnvOverrideBeatsPersistedMode() {
  #expect(
    CloudSyncFactory.resolveMode(
      persistedMode: .off, environment: ["LORVEX_CLOUDKIT_EXPORT": "live"]) == .live)
  #expect(
    CloudSyncFactory.resolveMode(
      persistedMode: .live, environment: ["LORVEX_CLOUDKIT_EXPORT": "bogus"]) == .off)
}
