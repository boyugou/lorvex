import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import LorvexSync
import Testing

@testable import LorvexMobile

// MARK: - Gate

/// Async barrier for the overlapping-refresh tests: blocks the *first*
/// `loadToday` at a controllable point (signaling entry first) so a test can
/// request more refreshes while the first is provably in flight. Later
/// invocations pass through so a coalesced rerun is not blocked. Mirrors the
/// watch store's `WatchRefreshGate`.
private actor MobileRefreshGate {
  private var invocations = 0
  private var didEnter = false
  private var released = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var blockedContinuation: CheckedContinuation<Void, Never>?

  func gate() async {
    invocations += 1
    guard invocations == 1 else { return }
    didEnter = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    guard !released else { return }
    await withCheckedContinuation { blockedContinuation = $0 }
  }

  func waitUntilEntered() async {
    if didEnter { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func release() {
    released = true
    blockedContinuation?.resume()
    blockedContinuation = nil
  }
}

/// Returns one server page exactly once, then an empty terminal page. This lets
/// the outer refresh flight observe `.newData` on its first pass and `.noData`
/// on the coalesced trailing pass.
private actor OneShotMobileRefreshFetcher: CloudSyncRemoteChangeFetching {
  private var records: [CKRecord]
  private(set) var callCount = 0

  init(records: [CKRecord]) {
    self.records = records
  }

  func fetchChanges(
    after _: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    callCount += 1
    let page = records
    records = []
    return CloudSyncRemoteChangeBatch(
      records: page,
      serverChangeTokenData: Data([UInt8(clamping: callCount)]),
      moreComing: false,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

// MARK: - Overlapping refreshes

@MainActor
@Test
func mobileOverlappingRefreshDoesNotClobberNewerSnapshotWithOlderRead() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.todayOverride = try await core.preview.loadToday()
  let gate = MobileRefreshGate()
  core.loadTodayGate = { await gate.gate() }
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  // Refresh A enters `loadToday`, captures the pre-change snapshot, and blocks.
  let first = Task { await store.refresh() }
  await gate.waitUntilEntered()

  // The data changes while A is suspended mid-read.
  let marker = try await core.preview.createTask(title: "Arrived after the first read", notes: "")
  core.todayOverride = try await core.preview.loadToday()

  // Refresh B arrives while A is in flight. It must coalesce into a rerun of
  // A's single-flight loop rather than run a second concurrent body.
  let second = Task { await store.refresh() }

  // A body that runs for B would commit the newer snapshot before A resumes;
  // wait for such a commit so releasing A afterwards would demonstrate the
  // older read clobbering it. With coalescing, nothing commits and this loop
  // simply times out with the snapshot still empty.
  for _ in 0..<50 {
    if store.snapshot.today.tasks.contains(where: { $0.id == marker.id }) { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  await gate.release()
  _ = await first.value
  _ = await second.value

  #expect(
    store.snapshot.today.tasks.contains { $0.id == marker.id },
    "the newest read must win — an older in-flight read must not clobber it")
  #expect(store.isLoading == false)
}

@MainActor
@Test
func mobileConcurrentRefreshTriggersCoalesceIntoSingleRerun() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let gate = MobileRefreshGate()
  core.loadTodayGate = { await gate.gate() }
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  // Refresh A enters `loadToday` and blocks on the gate.
  let first = Task { await store.refresh() }
  await gate.waitUntilEntered()

  // Three triggers land while A is in flight (scene-active, push, DB signal in
  // production). They must coalesce — none may run a concurrent body.
  let second = Task { await store.refresh() }
  let third = Task { await store.refresh() }
  let fourth = Task { await store.refresh() }
  try await Task.sleep(nanoseconds: 150_000_000)

  #expect(core.loadTodayCallCount == 1, "no second body may run while one is in flight")
  #expect(
    store.isLoading == true,
    "a coalesced trigger must not clear the loading state of the in-flight refresh")

  await gate.release()
  _ = await first.value
  _ = await second.value
  _ = await third.value
  _ = await fourth.value

  #expect(
    core.loadTodayCallCount == 2,
    "any number of pending triggers collapse into exactly one rerun")
  #expect(store.isLoading == false)
  #expect(store.snapshot.today.tasks.isEmpty == false)
}

@MainActor
@Test
func mobileRefreshCoalescingRetainsNewDataAcrossTrailingNoOpPass() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let gate = MobileRefreshGate()
  core.loadTodayGate = { await gate.gate() }

  let zoneID = CKRecordZone.ID(
    zoneName: CloudSyncZoneConstants.zoneName, ownerName: CKCurrentUserDefaultName)
  let envelope = SyncEnvelope(
    entityType: .task,
    entityId: "01966a3f-7c8b-7d4e-8f3a-000000000099",
    operation: .delete,
    version: try Hlc.parse("1711234567899_0000_a1b2c3d4a1b2c3d4"),
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: "{}",
    deviceId: "device-refresh-flight")
  let fetcher = OneShotMobileRefreshFetcher(
    records: [CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: zoneID)])
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: .available),
    pusher: RecordingRecordPusher(),
    fetcher: fetcher,
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator)

  let first = Task { await store.refresh() }
  await gate.waitUntilEntered()
  let overlapping = Task { await store.refresh() }
  for _ in 0..<1_000 where !store.refreshFlight.isPendingRerun {
    await Task.yield()
  }
  #expect(store.refreshFlight.isPendingRerun)

  await gate.release()
  let firstResult = await first.value
  let overlappingResult = await overlapping.value

  #expect(firstResult == .newData)
  #expect(
    overlappingResult == .newData,
    "the trailing no-op refresh must not erase data applied by the first pass")
  #expect(await fetcher.callCount >= 1)
}
