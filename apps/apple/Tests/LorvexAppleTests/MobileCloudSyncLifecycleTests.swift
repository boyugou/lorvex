import CloudKit
import Foundation
import LorvexCore
import Testing

@testable import LorvexCloudSync
@testable import LorvexMobile

// MARK: - Helpers

/// A live-mode store over `core` whose controller runs on fake engines. The
/// controller works against the core's real in-memory service, so outbox and
/// inbound apply behave as in production.
@MainActor
private func makeLiveStore(
  core: StubCoreService,
  accountChecker: any CloudKitAccountStatusChecking = StubAccountStatusChecker()
) -> (store: MobileStore, sync: TestCloudSync) {
  let sync = TestCloudSync(store: core.preview, accountChecker: accountChecker)
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    cloudSyncMode: .live,
    cloudSyncController: sync.controller)
  return (store, sync)
}

/// Makes the engine's sends upload every queued record and report them
/// saved, the way CloudKit accepts a batch.
private func acceptEverySend(_ sync: TestCloudSync) throws {
  let controller = sync.controller
  try sync.engine.onSend = {
    let batch = await controller.nextBatch(scope: .all)
    await controller.handleSentRecords(saved: batch, failed: [])
  }
}

/// Holds an engine call until the test releases it.
private actor SyncGate {
  private var started: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?
  private var hasStarted = false

  func enter() async {
    hasStarted = true
    started?.resume()
    started = nil
    await withCheckedContinuation { release = $0 }
  }

  func waitForEntry() async {
    if hasStarted { return }
    await withCheckedContinuation { started = $0 }
  }

  func open() {
    release?.resume()
    release = nil
  }
}

// MARK: - Refresh and change signals

@MainActor
@Test
func mobileRefreshLoadsLocalFirstThenReloadsAfterInboundApply() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let (store, sync) = makeLiveStore(core: core)
  try await sync.deliverOnFirstFetch([
    inboundSelectiveRecord(.task, "01966a3f-7c8b-7d4e-8f3a-000000000010", 3)
  ])

  let result = await store.refresh()

  #expect(result == .newData)
  // The refresh loads local surfaces before the sync pass, so the UI shows
  // on-disk data at once, then reloads Today after the pass applied the
  // fetched record.
  #expect(core.loadTodayCallCount == 2)
  #expect(store.lastCloudSyncCycleReport?.fetchedRecordCount == 1)
}

@MainActor
@Test
func mobileDatabaseChangeSignalObserverRefreshesStore() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
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

// MARK: - Sync mode

@MainActor
@Test
func mobileCycleNoOpsWhenSyncModeIsOff() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" })  // cloudSyncMode defaults to .off

  #expect(await store.runCloudSyncCycle() == .noData)
  #expect(store.lastCloudSyncCycleReport == nil)
}

@MainActor
@Test
func mobileSettingsCloudSyncModePersistsAndStartsAndStopsTheController() async throws {
  let suiteName = "test.mobile.cloudSyncMode.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try makeInMemoryCore()
  let sync = TestCloudSync(store: core)
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    defaults: defaults,
    cloudSyncController: sync.controller)

  await store.setCloudSyncModeFromSettings(.live)

  #expect(store.cloudSyncMode == .live)
  #expect(MobileSetupPreferences(defaults: defaults).cloudSyncMode == .live)
  #expect(await sync.controller.state == .running)

  await store.setCloudSyncModeFromSettings(.off)

  #expect(store.cloudSyncMode == .off)
  #expect(MobileSetupPreferences(defaults: defaults).cloudSyncMode == .off)
  #expect(await sync.controller.state == .stopped)
  #expect(await store.runCloudSyncCycle() == .noData)
}

@MainActor
@Test
func mobileCloudSyncSettingsChangeRefreshesDiagnostics() async throws {
  let suiteName = "test.mobile.cloudSyncMode.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" }, defaults: defaults)

  await store.setCloudSyncModeFromSettings(.live)

  #expect(core.loadRuntimeDiagnosticsCallCount == 1)
}

// MARK: - Status

@MainActor
@Test
func mobileCloudSyncStatusReportUsesStoreLiveFields() async throws {
  let successDate = Date(timeIntervalSince1970: 1_779_465_600)
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    cloudSyncMode: .live)

  store.cloudKitAccountAvailability = .restricted
  store.lastCloudSyncRemoteChangeSucceededAt = successDate
  store.lastCloudSyncRemoteChangeErrorMessage = "remote failed"

  let report = store.mobileCloudSyncStatusReport

  #expect(report.mode == .live)
  #expect(report.accountAvailability == .restricted)
  #expect(report.lastPullAt == successDate)
  #expect(report.lastPullError == "remote failed")
  #expect(report.lastPushError == nil)
}

@MainActor
@Test
func mobileCloudSyncCycleRecordsUnavailableAccountState() async throws {
  let (store, _) = makeLiveStore(
    core: StubCoreService(preview: try await makeSeededInMemoryCore()),
    accountChecker: StubAccountStatusChecker(availability: .noAccount))

  let result = await store.runCloudSyncCycle()

  #expect(result == .noData)
  #expect(store.cloudKitAccountAvailability == .noAccount)
  #expect(store.lastCloudSyncCycleReport == nil)
}

/// Counts account probes, so a test can prove the Settings refresh never
/// touches iCloud while sync is off.
private actor CountingAccountStatusChecker: CloudKitAccountStatusChecking {
  private(set) var calls = 0
  func checkAccountStatus() async throws -> CloudKitAccountAvailability {
    calls += 1
    return .available
  }
}

@MainActor
@Test
func mobileAccountRefreshSkipsTheProbeWhileSyncIsOff() async throws {
  let core = try await makeSeededInMemoryCore()
  let checker = CountingAccountStatusChecker()
  let sync = TestCloudSync(store: core, accountChecker: checker)
  let store = MobileStore(
    core: core, todayString: { "2026-05-23" }, cloudSyncMode: .off,
    cloudSyncController: sync.controller)

  await store.refreshCloudKitAccountAvailability()
  #expect(store.cloudKitAccountAvailability == .couldNotDetermine)
  #expect(await checker.calls == 0)

  let (liveStore, _) = makeLiveStore(
    core: StubCoreService(preview: try await makeSeededInMemoryCore()),
    accountChecker: checker)
  await liveStore.refreshCloudKitAccountAvailability()
  #expect(liveStore.cloudKitAccountAvailability == .available)
  #expect(await checker.calls == 1)
}

// MARK: - Sync cycle

@MainActor
@Test
func mobileCycleNoOpsWhenLiveWithoutController() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    cloudSyncMode: .live)

  #expect(await store.runCloudSyncCycle() == .noData)
  #expect(store.lastCloudSyncCycleReport == nil)
}

@MainActor
@Test
func mobileCycleUploadsTheOutboxAndRecordsSuccess() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let (store, sync) = makeLiveStore(core: core)
  _ = await sync.controller.start()
  try acceptEverySend(sync)

  let result = await store.runCloudSyncCycle()

  #expect(result == .newData)
  let report = try #require(store.lastCloudSyncCycleReport)
  #expect(report.pushedRecordCount > 0, "the seeded database's outbox goes out")
  #expect(report.failedPushCount == 0)
  #expect(store.lastCloudSyncRemoteChangeSucceededAt != nil)
  #expect(store.lastCloudSyncRemoteChangeErrorMessage == nil)
  #expect(try core.preview.pendingOutbound().isEmpty, "every confirmed row left the outbox")
}

@MainActor
@Test
func mobileCycleCoalescesOverlappingTriggersAndRetainsProgress() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let (store, sync) = makeLiveStore(core: core)
  _ = await sync.controller.start()
  let gate = SyncGate()
  let controller = sync.controller
  let engine = try sync.engine
  let firstSend = OnceFlag()
  engine.onSend = {
    if firstSend.claim() { await gate.enter() }
    let batch = await controller.nextBatch(scope: .all)
    await controller.handleSentRecords(saved: batch, failed: [])
  }

  let first = Task { await store.runCloudSyncCycle() }
  await gate.waitForEntry()

  let overlapping = Task { await store.runCloudSyncCycle() }
  for _ in 0..<1_000 where !store.cloudSyncCycleFlight.isPendingRerun {
    await Task.yield()
  }
  #expect(store.cloudSyncCycleFlight.isPendingRerun)
  #expect(engine.sendCount == 1, "the overlapping trigger waits for the pass in flight")

  await gate.open()
  let firstResult = await first.value
  let overlappingResult = await overlapping.value

  #expect(firstResult == .newData)
  #expect(
    overlappingResult == .newData,
    "the trailing no-op pass must not erase progress made by the first pass")
  #expect(engine.sendCount == 2, "one trailing pass ran for the overlapping trigger")
  #expect(
    (store.lastCloudSyncCycleReport?.pushedRecordCount ?? 0) > 0,
    "the trailing pass retains the first pass's report for post-cycle fan-out")
}

/// A task action returns once the store shows it, not once iCloud has it: the
/// sync pass the write starts runs on its own, so the task can be acted on
/// again, and the action's feedback plays, while the pass is still sending.
///
/// A regression is a hang (an action that waited for the pass never returns
/// while the gate holds it), which the time limit turns into a failure. The
/// limit is well above the length of a full suite run, because the suite's
/// main-actor tests queue for one actor and each test's clock includes its
/// wait: this test reads about a minute in a run that finishes in 75 seconds.
@MainActor
@Test(.timeLimit(.minutes(5)))
func mobileTaskActionDoesNotWaitForItsSyncPass() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let (store, sync) = makeLiveStore(core: core)
  _ = await sync.controller.start()
  let gate = SyncGate()
  let controller = sync.controller
  let engine = try sync.engine
  let firstSend = OnceFlag()
  engine.onSend = {
    if firstSend.claim() { await gate.enter() }
    let batch = await controller.nextBatch(scope: .all)
    await controller.handleSentRecords(saved: batch, failed: [])
  }
  let taskID = LorvexPreviewSeedID.agendaTask

  #expect(await store.completeTask(taskID))
  await gate.waitForEntry()
  #expect(store.isCloudSyncCycleRunning, "the completion's sync pass is still sending")
  #expect(!store.taskIsMutating(taskID))
  #expect(await store.reopenTask(taskID), "the task takes its next action before the pass ends")

  await gate.open()
  await store.runCloudSyncCycle()
}

// MARK: - Factory

@Test
func cloudSyncFactoryEnvOverrideBeatsPersistedMode() {
  #expect(CloudSyncFactory.resolveMode(persistedMode: .off, environment: [:]) == .off)
  #expect(CloudSyncFactory.resolveMode(persistedMode: .live, environment: [:]) == .live)
  #expect(
    CloudSyncFactory.resolveMode(
      persistedMode: .off, environment: ["LORVEX_CLOUD_SYNC": "live"]) == .live)
  #expect(
    CloudSyncFactory.resolveMode(
      persistedMode: .live, environment: ["LORVEX_CLOUD_SYNC": "bogus"]) == .off)
}
