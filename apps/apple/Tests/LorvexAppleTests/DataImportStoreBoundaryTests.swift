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

private func emptyDataImport() -> (
  plan: LorvexImportPlan,
  decoded: LorvexDataImporter.DecodedImport
) {
  (
    LorvexImportPlan(entries: []),
    LorvexDataImporter.DecodedImport(payload: LorvexDataExportPayload()))
}

@MainActor
@Test
func appStoreDataImportWaitsForACoalescedPostImportRefresh() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
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
func dataImportIsRejectedWhileAnotherDataOperationRuns() async throws {
  let payload = emptyDataImport()
  let appStore = AppStore(core: try makeInMemoryCore(), cloudSyncMode: .off)
  appStore.isCloudDataDeletionRunning = true
  await #expect(throws: LorvexDataImporter.BusyError.self) {
    _ = try await appStore.applyDataImport(plan: payload.plan, decoded: payload.decoded)
  }

  let mobileStore = MobileStore(core: try makeInMemoryCore(), todayString: { "2026-05-23" })
  mobileStore.isLocalDataResetRunning = true
  await #expect(throws: LorvexDataImporter.BusyError.self) {
    _ = try await mobileStore.applyDataImport(plan: payload.plan, decoded: payload.decoded)
  }
}

@MainActor
@Test
func mobileStoreDataImportUploadsTheImportedRowsAfterItsLocalRefresh() async throws {
  let preview = try await makeSeededInMemoryCore()
  let sync = TestCloudSync(store: preview)
  let store = MobileStore(
    core: preview, todayString: { "2026-05-23" }, cloudSyncMode: .live,
    cloudSyncController: sync.controller)
  let payload = emptyDataImport()

  _ = try await store.applyDataImport(plan: payload.plan, decoded: payload.decoded)

  // One best-effort pass before the import, one after it to upload.
  #expect(try sync.engine.sendCount == 2)
  #expect(!store.isDataImportRunning)
}
