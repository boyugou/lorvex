@preconcurrency import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexCloudSync
@testable import LorvexMobile

/// iOS store-level state transitions around "Delete iCloud Data": a confirmed
/// deletion turns sync off (persisted and runtime) and records the re-opt-in
/// pause; an unconfirmed one leaves sync as it was; and switching the mode
/// back to Live lifts only the deletion pause, never an account-change pause,
/// and never on the strength of a request made before a later deletion.
struct MobileCloudDataDeletionTests {
  @MainActor
  private func makeStore(
    mode: CloudSyncMode,
    initialPause: CloudSyncPauseReason? = nil,
    currentAccount: String = "account-a"
  ) async throws -> (store: MobileStore, sync: TestCloudSync, suite: String) {
    let core = try makeInMemoryCore()
    let sync = TestCloudSync(store: core, account: currentAccount)
    if let initialPause {
      await sync.identities.saveLastAccountIdentifier("account-a")
      await sync.pause.savePauseReason(initialPause)
    }
    let suite = "LorvexMobileTests.cloudData.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    MobileSetupPreferences(defaults: defaults).setCloudSyncMode(mode)
    let store = MobileStore(
      core: core,
      todayString: { "2026-07-09" },
      defaults: defaults,
      cloudSyncMode: mode,
      cloudSyncController: sync.controller)
    if mode == .live { _ = await sync.controller.start() }
    return (store, sync, suite)
  }

  private func persistedMode(_ suite: String) -> CloudSyncMode? {
    UserDefaults(suiteName: suite).map { MobileSetupPreferences(defaults: $0).cloudSyncMode }
  }

  @MainActor
  @Test
  func deleteCloudDataEverywhereTurnsSyncOffAndRecordsReoptInState() async throws {
    let (store, sync, suite) = try await makeStore(mode: .live)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    sync.confirmZoneDeletions()

    let errorMessage = await store.deleteCloudDataEverywhere()

    #expect(errorMessage == nil)
    #expect(try sync.engine.queuedZoneDeletes() == [CloudSyncController.zoneName])
    #expect(store.cloudSyncMode == .off, "the runtime mode stops passes immediately")
    #expect(persistedMode(suite) == .off, "the persisted mode flips off")
    #expect(await sync.pause.loadPauseReason() == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }

  @MainActor
  @Test
  func deletionWorksWithSyncOff() async throws {
    let (store, sync, suite) = try await makeStore(mode: .off)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    sync.confirmZoneDeletions()

    #expect(await store.deleteCloudDataEverywhere() == nil)
    #expect(await sync.pause.loadPauseReason() == .userDeletedZone)
    #expect(await sync.controller.state == .paused(.userDeletedZone))
  }

  @MainActor
  @Test
  func anUnconfirmedDeletionReportsAnErrorAndLeavesSyncAsItWas() async throws {
    let (store, sync, suite) = try await makeStore(mode: .live)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    try sync.engine.zones = [TestCloudSync.lorvexZone]

    let errorMessage = await store.deleteCloudDataEverywhere()

    #expect(errorMessage != nil)
    #expect(store.cloudSyncMode == .live)
    #expect(persistedMode(suite) == .live)
    #expect(await sync.pause.loadPauseReason() == nil)
  }

  @MainActor
  @Test
  func anUnconfirmedDeletionWithSyncOffTakesItsTemporaryEngineDown() async throws {
    let (store, sync, suite) = try await makeStore(mode: .off)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    sync.engines.configure = { $0.zones = [TestCloudSync.lorvexZone] }

    #expect(await store.deleteCloudDataEverywhere() != nil)
    #expect(try sync.engine.cancelled)
    #expect(await sync.controller.state == .stopped)
  }

  @MainActor
  @Test
  func switchingToLiveLiftsTheDeletionPause() async throws {
    let (store, sync, suite) = try await makeStore(mode: .off, initialPause: .userDeletedZone)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

    await store.setCloudSyncModeFromSettings(.live)

    #expect(store.cloudSyncMode == .live)
    #expect(await sync.pause.loadPauseReason() == nil, "switching to Live is the re-opt-in")
    #expect(store.cloudSyncPauseReason == nil)
  }

  @MainActor
  @Test
  func switchingToLiveLeavesAccountChangedPauseForItsOwnConsentFlow() async throws {
    // The signed-in account differs from the bound one, so the pause stands.
    let (store, sync, suite) = try await makeStore(
      mode: .off, initialPause: .accountChanged, currentAccount: "account-b")
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

    await store.setCloudSyncModeFromSettings(.live)

    #expect(
      await sync.pause.loadPauseReason() == .accountChanged,
      "an account-switch pause must not be lifted by a mode toggle")
    #expect(store.cloudSyncPauseReason == .accountChanged)
  }

  @MainActor
  @Test
  func modeRequestCapturedBeforeDeletionCannotRunAfterDeletion() async throws {
    let (store, sync, suite) = try await makeStore(mode: .off)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    sync.confirmZoneDeletions()

    // Settings captures the user's toggle before its Task is scheduled; a
    // deletion accepted afterwards supersedes that older intent.
    let staleRequest = store.makeCloudSyncModeRequest(.live)
    #expect(await store.deleteCloudDataEverywhere() == nil)

    await store.setCloudSyncModeFromSettings(staleRequest)

    #expect(store.cloudSyncMode == .off)
    #expect(persistedMode(suite) == .off)
    #expect(await sync.pause.loadPauseReason() == .userDeletedZone)
  }

  @MainActor
  @Test
  func resumeRequestCapturedBeforeDeletionCannotAdoptAfterIt() async throws {
    let (store, sync, suite) = try await makeStore(
      mode: .live, initialPause: .accountChanged, currentAccount: "account-b")
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    sync.confirmZoneDeletions()
    await store.refreshCloudSyncPauseReason()
    let staleRequest = try #require(await store.makeCloudSyncResumeRequest())

    #expect(await store.deleteCloudDataEverywhere() == nil)
    await store.adoptCurrentCloudAccountAndResumeSync(request: staleRequest)

    #expect(await sync.pause.loadPauseReason() == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }
}
