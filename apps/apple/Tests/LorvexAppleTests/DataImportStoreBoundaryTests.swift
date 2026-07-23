import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple
@testable import LorvexMobile

private actor DataImportRefreshGate {
  private var invocationCount = 0
  private var entered = false
  private var released = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func run() async {
    invocationCount += 1
    guard invocationCount == 1 else { return }
    entered = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    guard !released else { return }
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func release() {
    released = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor DataImportAccountGate: CloudKitAccountStatusChecking {
  private var entered = false
  private var released = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func checkAccountStatus() async throws -> CloudKitAccountAvailability {
    guard !entered else { return .available }
    entered = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    guard !released else { return .available }
    await withCheckedContinuation { releaseContinuation = $0 }
    return .available
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func release() {
    released = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private func emptyDataImport() -> (
  plan: LorvexImportPlan,
  decoded: LorvexDataImporter.DecodedImport
) {
  (
    LorvexImportPlan(entries: []),
    LorvexDataImporter.DecodedImport(payload: LorvexDataExportPayload()))
}

@Test
func explicitImportPreflightBypassesLocalBackoffButHonorsServerThrottle() throws {
  let firstAttempt = Date(timeIntervalSince1970: 1_000)
  let retry = firstAttempt.addingTimeInterval(1)
  var locallyBackedOff = CloudSyncPacing()
  locallyBackedOff.recordAttempt(now: firstAttempt)
  locallyBackedOff.recordFailure()
  #expect(!locallyBackedOff.shouldRun(now: retry))

  let startedAt = try CloudSyncDataImportBoundary.beginLivePreflightIfNeeded(
    mode: .live, pacing: &locallyBackedOff, now: retry)
  #expect(startedAt == retry)
  #expect(locallyBackedOff.consecutiveFailures == 0)
  #expect(locallyBackedOff.lastAttemptAt == retry)

  var serverThrottled = CloudSyncPacing()
  serverThrottled.recordServerThrottle(retryAfter: 60, now: firstAttempt)
  #expect(throws: CloudSyncDataImportBoundary.BoundaryError.cloudSyncRetryDeferred) {
    _ = try CloudSyncDataImportBoundary.beginLivePreflightIfNeeded(
      mode: .live, pacing: &serverThrottled, now: retry)
  }
}

@MainActor
@Test
func appStoreDataImportWaitsForACoalescedPostImportRefresh() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let gate = DataImportRefreshGate()
  core.loadTodayGate = { await gate.run() }
  let store = AppStore(core: core, cloudSyncMode: .off)
  let payload = emptyDataImport()

  let existingRefresh = Task { await store.refresh() }
  await gate.waitUntilEntered()
  let importTask = Task {
    try await store.applyDataImport(plan: payload.plan, decoded: payload.decoded)
  }
  for _ in 0..<1_000 where !store.refreshPending { await Task.yield() }

  #expect(store.refreshPending)
  #expect(
    store.isDataImportRunning,
    "the shared fence must stay raised until the coalesced trailing fan-out finishes")

  await gate.release()
  await existingRefresh.value
  _ = try await importTask.value

  #expect(core.loadTodayCallCount == 2)
  #expect(!store.isDataImportRunning)
}

@MainActor
@Test
func mobileStoreDataImportAppliesAModeRequestQueuedDuringItsFinalRefresh() async throws {
  let suiteName = "test.mobile.dataImportBoundary.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let gate = DataImportRefreshGate()
  core.loadTodayGate = { await gate.run() }
  let subscriber = RecordingCloudSyncSubscriber()
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncServiceFactory: { mode in
      MobileCloudSyncServices(
        subscriber: mode == .live ? subscriber : NoOpCloudSyncSubscriber(),
        coordinator: nil)
    })
  let payload = emptyDataImport()

  let importTask = Task {
    try await store.applyDataImport(plan: payload.plan, decoded: payload.decoded)
  }
  await gate.waitUntilEntered()
  #expect(store.isDataImportRunning)

  await store.setCloudSyncModeFromSettings(.live)
  #expect(store.cloudSyncMode == .off)
  #expect(store.pendingCloudSyncMode == .live)

  await gate.release()
  _ = try await importTask.value

  #expect(!store.isDataImportRunning)
  #expect(store.pendingCloudSyncMode == nil)
  #expect(store.cloudSyncMode == .live)
  #expect(MobileSetupPreferences(defaults: defaults).cloudSyncMode == .live)
  #expect(await subscriber.registrationCallCount() == 1)
}

@MainActor
@Test
func mobileStoreQueuedOffCannotBeOvertakenByPostImportUpload() async throws {
  let suiteName = "test.mobile.dataImportQueuedOff.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try makeInMemoryCore()
  let pusher = RecordingRecordPusher()
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(),
    pusher: pusher,
    fetcher: StubRemoteChangeFetcher(
      records: [], serverChangeTokenData: Data([0x8A])),
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  let gate = DataImportRefreshGate()
  let subscriber = RecordingCloudSyncSubscriber()
  let store = MobileStore(
    core: core,
    setBadge: { _ in await gate.run() },
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncMode: .live,
    cloudSyncSubscriber: subscriber,
    cloudSyncCoordinator: coordinator,
    cloudDataMaintenanceCoordinator: coordinator,
    cloudSyncServiceFactory: { mode in
      MobileCloudSyncServices(
        subscriber: mode == .live ? subscriber : NoOpCloudSyncSubscriber(),
        coordinator: mode == .live ? coordinator : nil)
    })
  let listID = "01966a3f-7c8b-7d4e-8f3a-00000000c799"
  let plan = LorvexImportPlan(entries: [
    LorvexImportPlanEntry(category: .lists, recordCount: 1, isSupported: true)
  ])
  let decoded = LorvexDataImporter.DecodedImport(
    payload: LorvexDataExportPayload(
      lists: [ExportList(id: listID, name: "Stay local after Off")]))

  let importTask = Task {
    try await store.applyDataImport(plan: plan, decoded: decoded)
  }
  await gate.waitUntilEntered()
  #expect(store.isDataImportRunning)

  await store.setCloudSyncModeFromSettings(.off)
  #expect(store.pendingCloudSyncMode == .off)
  await gate.release()
  let summary = try await importTask.value

  #expect(summary.totalImported == 1)
  #expect(store.cloudSyncMode == .off)
  #expect(store.pendingCloudSyncMode == nil)
  #expect(await pusher.pushBatchSizes.isEmpty)
  #expect(await subscriber.registrationCallCount() == 0)
  #expect(try await core.getList(id: listID).name == "Stay local after Off")
}

@MainActor
@Test
func mobileStoreImportJoinsACycleThatAlreadyCrossedItsEntryGuard() async throws {
  let suiteName = "test.mobile.dataImportOldCycle.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try makeInMemoryCore()
  let accountGate = DataImportAccountGate()
  let pusher = RecordingRecordPusher()
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: accountGate,
    pusher: pusher,
    fetcher: StubRemoteChangeFetcher(
      records: [], serverChangeTokenData: Data([0x8E])),
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  let subscriber = RecordingCloudSyncSubscriber()
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncMode: .live,
    cloudSyncSubscriber: subscriber,
    cloudSyncCoordinator: coordinator,
    cloudDataMaintenanceCoordinator: coordinator,
    cloudSyncServiceFactory: { mode in
      MobileCloudSyncServices(
        subscriber: mode == .live ? subscriber : NoOpCloudSyncSubscriber(),
        coordinator: mode == .live ? coordinator : nil)
    })
  let listID = "01966a3f-7c8b-7d4e-8f3a-00000000c798"
  let plan = LorvexImportPlan(entries: [
    LorvexImportPlanEntry(category: .lists, recordCount: 1, isSupported: true)
  ])
  let decoded = LorvexDataImporter.DecodedImport(
    payload: LorvexDataExportPayload(
      lists: [ExportList(id: listID, name: "Never escape after queued Off")]))

  let oldCycle = Task { await store.runCloudSyncCycle() }
  await accountGate.waitUntilEntered()
  let importTask = Task {
    try await store.applyDataImport(plan: plan, decoded: decoded)
  }
  for _ in 0..<1_000 where !store.isDataImportRunning { await Task.yield() }
  #expect(store.isDataImportRunning)

  await store.setCloudSyncModeFromSettings(.off)
  #expect(store.pendingCloudSyncMode == .off)
  await accountGate.release()

  _ = await oldCycle.value
  let summary = try await importTask.value
  #expect(summary.totalImported == 1)
  #expect(store.cloudSyncMode == .off)
  #expect(store.pendingCloudSyncMode == nil)
  let importedRecordName = CloudSyncEnvelopeRecord.recordName(
    entityType: EntityKind.list.asString, entityId: listID)
  #expect(await pusher.pushedRecordsByName[importedRecordName] == nil)
}
