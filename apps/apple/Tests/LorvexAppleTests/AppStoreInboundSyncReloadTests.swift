@preconcurrency import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple
@testable import LorvexCloudSync

/// Suspends the first account probe (the controller's start) so the test can
/// issue another AppStore-level sync trigger while the first pass is
/// definitely in flight.
private actor AppStoreCloudSyncAccountGate: CloudKitAccountStatusChecking {
  private var entered = false
  private var released = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private(set) var callCount = 0

  func checkAccountStatus() async throws -> CloudKitAccountAvailability {
    callCount += 1
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

@MainActor
private final class CompletionFlag {
  var isSet = false
}

// On macOS the tail sync pass of `refresh()` can apply inbound records AFTER
// the fan-out already read the UI surfaces and republished the widget. The
// store reuses the single-flight `refresh()` loop — the in-flight fan-out
// reruns once, re-reading the applied records into the cached Today surface
// and republishing the widget in the same refresh.
@MainActor
@Test("an inbound sync applying records mid-refresh reruns the fan-out so they reach the UI and widget")
func appStoreRerunsFanOutWhenInboundSyncAppliesRecordsMidRefresh() async throws {
  let core = try makeInMemoryCore()
  let logicalDay = try await core.loadToday().logicalDay
  let (appliedID, records) = try await TestCloudSync.peerRecords { peer in
    try await peer.createTask(
      TaskCreateDraft(
        title: "Inbound-applied task",
        plannedDate: logicalDay.flatMap(LorvexDateFormatters.ymdUTC.date(from:)))
    ).id
  }
  let sync = TestCloudSync(store: core)
  try await sync.deliverOnFirstFetch(records)
  let widget = RecordingWidgetSnapshotPublisher()
  let store = AppStore(
    core: core,
    widgetSnapshotPublisher: widget,
    cloudSyncMode: .live,
    cloudSyncController: sync.controller)

  // Empty core: the first fan-out loads zero open tasks and publishes the widget
  // once; the tail sync pass then applies the inbound task.
  await store.refresh()

  let id = appliedID
  // Reaching the CACHED Today surface (not a live re-query) proves the fan-out
  // reran after the inbound apply.
  #expect(store.today.tasks.contains { $0.id == id })
  // Two publishes total (one per fan-out): the coalescing settled without
  // further reruns, since the rerun's own pass fetches nothing.
  #expect(widget.publishedSnapshots().count == 2)
  #expect(store.isRefreshing == false)
  #expect(store.refreshPending == false)
}

@MainActor
@Test("a CloudSync trigger arriving mid-cycle runs one serialized trailing pass")
func appStoreCloudSyncCycleCoalescesOverlappingTriggers() async throws {
  let preview = try await makeSeededInMemoryCore()
  let core = StubCoreService(preview: preview)
  let accountGate = AppStoreCloudSyncAccountGate()
  let sync = TestCloudSync(store: preview, accountChecker: accountGate)
  let store = AppStore(
    core: core,
    cloudSyncMode: .live,
    cloudSyncController: sync.controller)

  let first = Task { await store.runCloudSyncCycle() }
  await accountGate.waitUntilEntered()

  let overlapping = Task { await store.runCloudSyncCycle() }
  for _ in 0..<1_000 where !store.cloudSyncCycleFlight.isPendingRerun {
    await Task.yield()
  }

  #expect(store.cloudSyncCycleFlight.isPendingRerun)
  #expect(await accountGate.callCount == 1)

  await accountGate.release()
  await first.value
  await overlapping.value

  // The controller started once; the trailing pass reused it.
  #expect(await accountGate.callCount == 1)
  #expect(try sync.engine.fetchCount == 2)
  #expect(!store.cloudSyncCycleFlight.isRunning)
  #expect(!store.cloudSyncCycleFlight.isPendingRerun)
}

// A pass that fetches only this device's own uploads coming back skips every
// record as already applied. Nothing changed, so nothing reloads: an echo of
// each local write must not cost a second read of every surface.
@MainActor
@Test("a pass that fetches only this device's own uploads reloads nothing")
func appStoreOwnUploadsComingBackReloadNothing() async throws {
  let preview = try await makeSeededInMemoryCore()
  let core = StubCoreService(preview: preview)
  let sync = TestCloudSync(store: preview)
  _ = await sync.controller.start()
  let echo = await sync.controller.nextBatch(scope: .all)
  try #require(!echo.isEmpty)
  try await sync.deliverOnFirstFetch(echo)
  let store = AppStore(
    core: core,
    cloudSyncMode: .live,
    cloudSyncController: sync.controller)
  let loadsBefore = core.loadTodayCallCount

  await store.runCloudSyncCycle()

  #expect(core.loadTodayCallCount == loadsBefore)
  #expect(!store.isRefreshing)
  #expect(!store.cloudSyncCycleFlight.isRunning)
}

// A pass that runs outside a refresh (the post-mutation drain, or one the
// engine ran on its own) and applies a change no domain bounds — here a peer's
// preference edit — falls back to a full local reload. That reload must not
// wait on the pass running it; if it did, the pass and the refresh would each
// wait for the other.
@MainActor
@Test("an unattributable inbound change outside a refresh reloads without wedging either flight")
func appStoreUnattributableInboundOutsideRefreshDoesNotWedge() async throws {
  let preview = try await makeSeededInMemoryCore()
  let core = StubCoreService(preview: preview)
  let (_, records) = try await TestCloudSync.peerRecords { peer in
    try await peer.setPreference(key: PreferenceKeys.prefTimezone, value: "Pacific/Auckland")
  }
  let sync = TestCloudSync(store: preview)
  try await sync.deliverOnFirstFetch(records)
  let store = AppStore(
    core: core,
    cloudSyncMode: .live,
    cloudSyncController: sync.controller)
  let loadsBefore = core.loadTodayCallCount

  let finished = CompletionFlag()
  Task { @MainActor in
    await store.runCloudSyncCycle()
    finished.isSet = true
  }
  for _ in 0..<500 where !finished.isSet {
    try await Task.sleep(for: .milliseconds(10))
  }

  #expect(finished.isSet)
  // The fallback reload re-read local surfaces from the post-apply state.
  #expect(core.loadTodayCallCount > loadsBefore)
  #expect(!store.isRefreshing)
  #expect(!store.cloudSyncCycleFlight.isRunning)
}

// The local pass of a refresh must not wait on CloudKit. A helper-process
// write (the MCP host, a widget) raises a change signal whose refresh has to
// reach the UI even while a sync pass is stuck on a slow network; only the
// refresh's sync tail may wait for that pass.
@MainActor
@Test("a refresh reloads local surfaces while a sync cycle is still waiting on the network")
func appStoreLocalRefreshDoesNotWaitOnInFlightCycle() async throws {
  let preview = try await makeSeededInMemoryCore()
  let core = StubCoreService(preview: preview)
  let accountGate = AppStoreCloudSyncAccountGate()
  let sync = TestCloudSync(store: preview, accountChecker: accountGate)
  let store = AppStore(
    core: core,
    cloudSyncMode: .live,
    cloudSyncController: sync.controller)

  // A post-mutation drain is in flight and suspended on the network.
  let cycle = Task { await store.runCloudSyncCycle() }
  await accountGate.waitUntilEntered()
  let loadsBefore = core.loadTodayCallCount

  let refresh = Task { await store.refresh() }
  for _ in 0..<500 where core.loadTodayCallCount == loadsBefore || store.isRefreshing {
    try await Task.sleep(for: .milliseconds(10))
  }

  #expect(core.loadTodayCallCount > loadsBefore)
  #expect(!store.isRefreshing)
  #expect(store.isCloudSyncCycleRunning)

  await accountGate.release()
  await cycle.value
  await refresh.value
  #expect(!store.isCloudSyncCycleRunning)
}

// A task action must not wait on CloudKit: its feedback and its undo step
// follow the local write, while the sync pass the write starts may still be
// waiting on the network. A regression is a hang, which the time limit turns
// into a failure; the limit is well above a full suite run because every
// main-actor test's clock includes its wait for the main actor.
@MainActor
@Test(
  "completing a task registers its undo step while its sync pass waits on the network",
  .timeLimit(.minutes(5)))
func appStoreTaskActionDoesNotWaitOnItsSyncPass() async throws {
  let preview = try await makeSeededInMemoryCore()
  let core = StubCoreService(preview: preview)
  let accountGate = AppStoreCloudSyncAccountGate()
  let sync = TestCloudSync(store: preview, accountChecker: accountGate)
  let store = AppStore(
    core: core,
    cloudSyncMode: .live,
    cloudSyncController: sync.controller)
  let undoManager = UndoManager()

  await store.completeTask(id: LorvexPreviewSeedID.agendaTask, undoManager: undoManager)

  await accountGate.waitUntilEntered()
  #expect(store.isCloudSyncCycleRunning, "the completion's sync pass is still waiting")
  #expect(undoManager.canUndo, "⌘Z reopens the task before the pass ends")

  await accountGate.release()
  for _ in 0..<500 where store.isCloudSyncCycleRunning {
    try await Task.sleep(for: .milliseconds(10))
  }
}
