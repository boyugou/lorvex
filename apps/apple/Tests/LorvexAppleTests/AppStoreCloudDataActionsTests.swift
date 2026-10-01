@preconcurrency import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexCloudSync

/// macOS store-level state transitions around "Delete iCloud Data": a
/// confirmed deletion turns sync off (persisted and runtime) and records the
/// re-opt-in pause; an unconfirmed one leaves sync as it was; and turning sync
/// back on lifts only the deletion pause, never an account-change pause, and
/// never on the strength of a request made before a later deletion.
struct AppStoreCloudDataActionsTests {
  @MainActor
  private func makeFixture(
    storeMode: CloudSyncMode = .live,
    initialPause: CloudSyncPauseReason? = nil,
    currentAccount: String = "account-a"
  ) async throws -> (store: AppStore, settings: AppSettingsStore, sync: TestCloudSync, suite: String) {
    let core = try makeInMemoryCore()
    let sync = TestCloudSync(store: core, account: currentAccount)
    if let initialPause {
      await sync.identities.saveLastAccountIdentifier("account-a")
      await sync.pause.savePauseReason(initialPause)
    }
    let suite = "LorvexAppleTests.cloudData.\(UUID().uuidString)"
    let settings = AppSettingsStore(
      defaults: try #require(UserDefaults(suiteName: suite)), environment: [:])
    settings.cloudSyncMode = storeMode
    let store = AppStore(
      core: core, cloudSyncMode: storeMode, cloudSyncController: sync.controller)
    if storeMode == .live { _ = await sync.controller.start() }
    return (store, settings, sync, suite)
  }

  @MainActor
  @Test
  func deleteCloudDataEverywhereTurnsSyncOffAndRecordsReoptInState() async throws {
    let (store, settings, sync, suite) = try await makeFixture()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    sync.confirmZoneDeletions()

    let errorMessage = await store.deleteCloudDataEverywhere(settings: settings)

    #expect(errorMessage == nil)
    #expect(try sync.engine.queuedZoneDeletes() == [CloudSyncController.zoneName])
    #expect(settings.cloudSyncMode == .off, "the persisted mode flips off")
    #expect(store.cloudSyncMode == .off, "the runtime mode stops passes immediately")
    #expect(try await sync.pause.loadPauseReason() == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }

  @MainActor
  @Test
  func deletionWorksWithSyncOff() async throws {
    let (store, settings, sync, suite) = try await makeFixture(storeMode: .off)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    sync.confirmZoneDeletions()

    #expect(await store.deleteCloudDataEverywhere(settings: settings) == nil)
    #expect(try await sync.pause.loadPauseReason() == .userDeletedZone)
  }

  @MainActor
  @Test
  func anUnconfirmedDeletionReportsAnErrorAndLeavesSyncAsItWas() async throws {
    let (store, settings, sync, suite) = try await makeFixture()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    // The zone exists, but CloudKit never confirms deleting it.
    try sync.engine.zones = [TestCloudSync.lorvexZone]

    let errorMessage = await store.deleteCloudDataEverywhere(settings: settings)

    #expect(errorMessage != nil)
    #expect(settings.cloudSyncMode == .live)
    #expect(store.cloudSyncMode == .live)
    #expect(try await sync.pause.loadPauseReason() == nil)
    #expect(store.cloudSyncPauseReason == nil)
  }

  @MainActor
  @Test
  func explicitReenableLiftsTheDeletionPause() async throws {
    let (store, _, sync, suite) = try await makeFixture(
      storeMode: .off, initialPause: .userDeletedZone)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

    let request = try #require(store.makeCloudDeletionReenableRequest())
    await store.liftCloudDeletionPauseForExplicitReenable(request: request)

    #expect(try await sync.pause.loadPauseReason() == nil, "turning sync back on is the re-opt-in")
    #expect(store.cloudSyncPauseReason == nil)
  }

  @MainActor
  @Test
  func explicitReenableLeavesAccountChangedPauseForItsOwnConsentFlow() async throws {
    let (store, _, sync, suite) = try await makeFixture(
      storeMode: .off, initialPause: .accountChanged)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

    let request = try #require(store.makeCloudDeletionReenableRequest())
    await store.liftCloudDeletionPauseForExplicitReenable(request: request)

    #expect(
      try await sync.pause.loadPauseReason() == .accountChanged,
      "an account-switch pause must not be lifted by a mode toggle")
  }

  @MainActor
  @Test
  func noReenableRequestCanBeMadeWhileADeletionRuns() async throws {
    let (store, _, _, suite) = try await makeFixture(storeMode: .off)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    store.isCloudDataDeletionRunning = true
    #expect(store.makeCloudDeletionReenableRequest() == nil)
  }

  @MainActor
  @Test
  func reenableRequestCapturedBeforeDeletionCannotRunAfterDeletion() async throws {
    let (store, settings, sync, suite) = try await makeFixture(storeMode: .off)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    sync.confirmZoneDeletions()

    // Settings captures the user's toggle before its Task is scheduled; a
    // deletion accepted afterwards supersedes that older intent.
    let staleRequest = try #require(store.makeCloudDeletionReenableRequest())
    #expect(await store.deleteCloudDataEverywhere(settings: settings) == nil)

    await store.liftCloudDeletionPauseForExplicitReenable(request: staleRequest)

    #expect(try await sync.pause.loadPauseReason() == .userDeletedZone)
    #expect(settings.cloudSyncMode == .off)
    #expect(store.cloudSyncMode == .off)
  }

  @MainActor
  @Test
  func resumeRequestCapturedBeforeDeletionCannotAdoptAfterIt() async throws {
    // The signed-in account differs from the bound one, so the pause stands.
    let (store, settings, sync, suite) = try await makeFixture(
      initialPause: .accountChanged, currentAccount: "account-b")
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    sync.confirmZoneDeletions()
    await store.refreshCloudSyncPauseReason()
    let staleRequest = try #require(await store.makeCloudSyncResumeRequest())

    #expect(await store.deleteCloudDataEverywhere(settings: settings) == nil)
    await store.adoptCurrentCloudAccountAndResumeSync(request: staleRequest)

    #expect(try await sync.pause.loadPauseReason() == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }
}
