import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// Coverage for the Cloud Sync queue state Settings shows: that it is re-read
/// whenever the outbox can have moved, that the narrow and the composed read
/// stay one value, and that the state derived from it describes what will
/// actually happen to the queued rows.

@MainActor
@Test
func mobileSyncStatusIsNilBeforeAnyReadAndPopulatesFromNarrowRead() async throws {
  // An empty store, so every pending row in these assertions comes from the
  // writes the test itself makes.
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  #expect(store.syncStatus == nil)
  #expect(store.syncPendingRowCount == 0)

  _ = try await core.createTask(title: "Queued edit", notes: "")
  await store.refreshSyncStatus()

  let pendingCount = try #require(store.syncStatus?.pendingCount)
  #expect(pendingCount > 0)
  #expect(store.mobileCloudSyncStatusReport.pendingCount == pendingCount)
  #expect(store.syncPendingRowCount == pendingCount)
}

@MainActor
@Test
func mobileSyncStatusTracksFurtherWritesOnEachNarrowRead() async throws {
  // The reported bug: the depth loaded once per process and never moved again,
  // so a second edit had to show up as more queued rows.
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  _ = try await core.createTask(title: "First edit", notes: "")
  await store.refreshSyncStatus()
  let afterFirst = try #require(store.syncStatus?.pendingCount)

  _ = try await core.createTask(title: "Second edit", notes: "")
  await store.refreshSyncStatus()
  let afterSecond = try #require(store.syncStatus?.pendingCount)

  #expect(afterSecond > afterFirst)
}

@MainActor
@Test
func mobileRefreshRereadsSyncStatusWithoutTheHeavyDiagnosticsLoad() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()

  #expect(core.loadSyncStatusCallCount >= 1)
  #expect(
    core.loadRuntimeDiagnosticsCallCount == 0,
    "the refresh fan-out must not pull the full diagnostics composition")
  #expect(store.syncStatus != nil)
}

@MainActor
@Test
func mobileLoadRuntimeDiagnosticsKeepsSyncStatusConsistent() async throws {
  // An empty store, so every pending row in these assertions comes from the
  // writes the test itself makes.
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  _ = try await core.createTask(title: "Diagnostics parity", notes: "")
  await store.loadRuntimeDiagnostics()

  let diagnosticsSync = try #require(store.runtimeDiagnostics?.sync)
  #expect(store.syncStatus == diagnosticsSync)
  #expect(store.syncPendingRowCount == diagnosticsSync.pendingCount)
}

@MainActor
@Test
func mobileCycleTailRereadsStatusOnlyWhenTheCycleDidWork() async throws {
  // A retry wake that is paced out returns `.noData` and touches nothing; it
  // must not spend a read per wake. A cycle that pushed, applied, or failed did
  // move the outbox, so its depth is re-read.
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.reloadInboundSurfacesIfNeeded(after: .noData)
  #expect(core.loadSyncStatusCallCount == 0)

  await store.reloadInboundSurfacesIfNeeded(after: .failed)
  #expect(core.loadSyncStatusCallCount == 1)

  await store.reloadInboundSurfacesIfNeeded(after: .newData)
  #expect(core.loadSyncStatusCallCount == 2)
}

@MainActor
@Test
func mobileCloudSyncActivityStateDescribesWhatHappensToQueuedRows() async throws {
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" }, cloudSyncMode: .live)

  #expect(store.cloudSyncActivityState == .checking)

  await store.refreshSyncStatus()
  #expect(store.cloudSyncActivityState == .upToDate)

  _ = try await core.createTask(title: "Queued edit", notes: "")
  await store.refreshSyncStatus()
  store.cloudKitAccountAvailability = .available
  #expect(store.cloudSyncActivityState == .syncing)

  // Nothing can drain the queue while the account is gone, so the line must not
  // claim work is in progress.
  store.cloudKitAccountAvailability = .noAccount
  #expect(store.cloudSyncActivityState == .waiting)
}
