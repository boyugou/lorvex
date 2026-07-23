@preconcurrency import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexApple

/// Remote-change fetcher modelling an inbound CloudKit page that lands during a
/// refresh's tail sync cycle. On its FIRST fetch it applies one record to the
/// core — a task the pre-sync fan-out never loaded — and returns a page carrying
/// a record so the cycle reports `fetchedRecordCount > 0`; every later fetch is
/// empty so the drain converges after one iteration.
///
/// The apply is a direct `createTask` rather than an envelope decode: the
/// AppStore refresh lifecycle only observes `fetchedRecordCount > 0` and the
/// post-apply DB, so this drives that surface without hand-building a wire
/// envelope. The returned record's type is irrelevant to the count — a
/// non-Lorvex record is ignored by the engine's apply but still counted as
/// fetched, which is exactly the signal the rerun trigger reads.
private actor InboundApplyingFetcher: CloudSyncRemoteChangeFetching {
  private let core: SwiftLorvexCoreService
  private var didApply = false
  private(set) var appliedTaskID: LorvexTask.ID?

  init(core: SwiftLorvexCoreService) { self.core = core }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    guard !didApply else {
      return CloudSyncRemoteChangeBatch(
        records: [], serverChangeTokenData: Data([0x02]),
        moreComing: false,
        observedGenerationRoot: true,
        observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
    }
    didApply = true
    let created = try await core.createTask(title: "Inbound-applied task", notes: "")
    appliedTaskID = created.id
    let marker = CKRecord(
      recordType: "NotLorvex",
      recordID: CKRecord.ID(
        recordName: "inbound-marker",
        zoneID: context.zoneID))
    return CloudSyncRemoteChangeBatch(
      records: [marker], serverChangeTokenData: Data([0x01]),
      moreComing: false,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

/// Suspends the first coordinator account probe so the test can issue another
/// AppStore-level sync trigger while the first pass is definitely in flight.
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

// concurrency-M3: on macOS the tail sync cycle of `refresh()` can apply inbound
// records AFTER the fan-out already read the UI surfaces and republished the
// widget. Mobile reruns its local-surface load on `.newData`; macOS must mirror
// that by reusing the single-flight `refresh()` loop — setting `refreshPending`
// so the in-flight fan-out reruns once, re-reading the applied records into the
// cached Today surface and republishing the widget in the same cycle instead of
// stranding them until an unrelated later refresh.
@MainActor
@Test("an inbound sync applying records mid-refresh reruns the fan-out so they reach the UI and widget")
func appStoreRerunsFanOutWhenInboundSyncAppliesRecordsMidRefresh() async throws {
  let core = try makeInMemoryCore()
  let fetcher = InboundApplyingFetcher(core: core)
  let widget = RecordingWidgetSnapshotPublisher()
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: .available),
    pusher: RecordingRecordPusher(),
    fetcher: fetcher,
    accountIdentifier: StubAccountIdentifier(identifier: "inbound-rerun-account"),
    accountIdentityStore: RecordingAccountIdentityStore(),
    accountPauseStore: RecordingCloudSyncPauseStore())
  let store = AppStore(
    core: core,
    widgetSnapshotPublisher: widget,
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator)

  // Empty core: the first fan-out loads zero open tasks and publishes the widget
  // once; the tail sync cycle then applies the inbound task. The applied task is
  // committed before the cycle returns, so a rerun of the fan-out sees it.
  await store.refresh()

  let appliedID = try #require(await fetcher.appliedTaskID)
  // Reaching the CACHED Today surface (not a live re-query) proves the fan-out
  // reran after the inbound apply — the first fan-out loaded before the task
  // existed, so its presence here means a second load committed it to state.
  #expect(store.today.tasks.contains { $0.id == appliedID })
  // The widget snapshot was republished from the reloaded state: two publishes
  // total (one per fan-out). Exactly two also proves the coalescing settled
  // without stampeding into further reruns — the drained backlog fetches nothing
  // on the rerun's own cycle.
  #expect(widget.publishedSnapshots().count == 2)
  // The single-flight loop left no dangling state.
  #expect(store.isRefreshing == false)
  #expect(store.refreshPending == false)
}

@MainActor
@Test("a CloudSync trigger arriving mid-cycle runs one serialized trailing pass")
func appStoreCloudSyncCycleCoalescesOverlappingTriggers() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let accountGate = AppStoreCloudSyncAccountGate()
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: accountGate,
    pusher: RecordingRecordPusher(),
    fetcher: StubRemoteChangeFetcher(records: []),
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  let store = AppStore(
    core: core,
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator)

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

  #expect(await accountGate.callCount == 2)
  #expect(!store.cloudSyncCycleFlight.isRunning)
  #expect(!store.cloudSyncCycleFlight.isPendingRerun)
}
