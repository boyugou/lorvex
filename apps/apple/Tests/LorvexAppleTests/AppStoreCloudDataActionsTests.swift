@preconcurrency import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexApple

/// macOS store-level state transitions around "Delete Lorvex iCloud data
/// everywhere": a successful deletion turns sync off (persisted + runtime) and
/// records the re-opt-in state; a post-barrier cleanup failure keeps the same
/// fail-closed state for retry; and explicit re-enable lifts only the deletion
/// pause after publishing a fresh complete generation.
struct AppStoreCloudDataActionsTests {

  private actor DeletionCleanupGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func enterAndWaitForRelease() async {
      guard !entered else { return }
      entered = true
      for waiter in entryWaiters { waiter.resume() }
      entryWaiters.removeAll()
      await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
      if entered { return }
      await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
      releaseContinuation?.resume()
      releaseContinuation = nil
    }
  }

  private static let zoneID = CKRecordZone.ID(
    zoneName: CloudSyncZoneConstants.zoneName, ownerName: CKCurrentUserDefaultName)

  @MainActor
  private func makeFixture(
    pusher: RecordingRecordPusher = RecordingRecordPusher(),
    pauseStore: RecordingCloudSyncPauseStore = RecordingCloudSyncPauseStore(),
    identityStore: RecordingAccountIdentityStore = RecordingAccountIdentityStore(),
    core: (any LorvexCoreServicing)? = nil,
    storeMode: CloudSyncMode = .live
  ) async throws -> (store: AppStore, settings: AppSettingsStore, suiteName: String) {
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(availability: .available),
      pusher: pusher,
      fetcher: RecordingPusherRemoteChangeFetcher(pusher: pusher),
      // A confirmed account identity so the explicit re-enable path can adopt and
      // lift the pause; adoption fails closed on a nil identity (that path is
      // covered by the CloudSync account-adopt tests).
      accountIdentifier: StubAccountIdentifier(identifier: "cloud-data-test-account"),
      accountIdentityStore: identityStore,
      accountPauseStore: pauseStore)
    let suiteName = "LorvexAppleTests.cloudData.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let settings = AppSettingsStore(defaults: defaults, environment: [:])
    settings.cloudSyncMode = storeMode
    let resolvedCore: any LorvexCoreServicing
    if let core {
      resolvedCore = core
    } else {
      resolvedCore = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    }
    let store = AppStore(
      core: resolvedCore,
      cloudSyncMode: storeMode,
      cloudSyncCoordinator: storeMode == .live ? coordinator : nil,
      cloudDataMaintenanceCoordinator: coordinator)
    return (store, settings, suiteName)
  }

  @MainActor
  @Test
  func deleteCloudDataEverywhereTurnsSyncOffAndRecordsReoptInState() async throws {
    let pusher = RecordingRecordPusher()
    let pauseStore = RecordingCloudSyncPauseStore()
    let (store, settings, suiteName) = try await makeFixture(pusher: pusher, pauseStore: pauseStore)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    let errorMessage = await store.deleteCloudDataEverywhere(settings: settings)

    #expect(errorMessage == nil)
    #expect(await pusher.deleteZoneCallCount == 1)
    #expect(settings.cloudSyncMode == .off, "the persisted mode flips off")
    #expect(store.cloudSyncMode == .off, "the runtime mode halts cycles immediately")
    #expect(await pauseStore.reason == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }

  @MainActor
  @Test
  func cleanupFailureTurnsSyncOffAndKeepsDeletionBarrierForRetry() async throws {
    let pusher = RecordingRecordPusher(deleteZoneError: CKError(.networkUnavailable))
    let pauseStore = RecordingCloudSyncPauseStore()
    let (store, settings, suiteName) = try await makeFixture(pusher: pusher, pauseStore: pauseStore)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    let errorMessage = await store.deleteCloudDataEverywhere(settings: settings)

    #expect(errorMessage != nil)
    #expect(settings.cloudSyncMode == .off)
    #expect(store.cloudSyncMode == .off)
    #expect(await pauseStore.reason == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }

  @MainActor
  @Test
  func pendingDeletionCleanupDoesNotStartDuringDataImport() async throws {
    let pusher = RecordingRecordPusher()
    let (store, _, suiteName) = try await makeFixture(pusher: pusher)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
    store.isDataImportRunning = true

    await store.retryPendingCloudDataDeletionCleanup()

    #expect(await pusher.allRecordZonesCallCount == 0)
    #expect(!store.isCloudDeletionMaintenanceRunning)
  }

  @MainActor
  @Test
  func explicitReenableLiftsDeletionPauseAfterPublishingFreshGeneration() async throws {
    let core = try makeInMemoryCore()
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(.deleted(
      deletionGeneration: 2, retiredZoneNames: [], modifiedAt: nil))
    let pauseStore = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    let identityStore = RecordingAccountIdentityStore(initial: "cloud-data-test-account")
    let (store, _, suiteName) = try await makeFixture(
      pusher: pusher, pauseStore: pauseStore, identityStore: identityStore,
      core: core, storeMode: .off)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    await store.liftCloudDeletionPauseForExplicitReenable()

    #expect(await pauseStore.reason == nil, "flipping sync back on is the explicit re-opt-in")
    #expect(store.cloudSyncPauseReason == nil)
  }

  @MainActor
  @Test
  func explicitReenableLeavesAccountChangedPauseForItsOwnConsentFlow() async throws {
    let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    let pauseStore = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let (store, _, suiteName) = try await makeFixture(pauseStore: pauseStore, core: core, storeMode: .off)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    await store.liftCloudDeletionPauseForExplicitReenable()

    #expect(
      await pauseStore.reason == .accountChanged,
      "an account-switch pause must not be lifted by a mode toggle")
    #expect(core.fullResyncBackfillCallCount == 0)
  }

  @MainActor
  @Test
  func reenableRequestedDuringDeletionCannotRecreateCloudDataAfterSuccess() async throws {
    let gate = DeletionCleanupGate()
    let pusher = RecordingRecordPusher(
      allRecordZonesHook: { await gate.enterAndWaitForRelease() })
    let pauseStore = RecordingCloudSyncPauseStore()
    let (store, settings, suiteName) = try await makeFixture(
      pusher: pusher, pauseStore: pauseStore, core: try makeInMemoryCore(),
      storeMode: .off)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    let deletion = Task { await store.deleteCloudDataEverywhere(settings: settings) }
    await gate.waitUntilEntered()
    let prematureReenable = Task {
      await store.liftCloudDeletionPauseForExplicitReenable()
    }
    await Task.yield()
    await gate.release()

    #expect(await deletion.value == nil)
    await prematureReenable.value
    guard case .deleted? = try await pusher.currentZoneGenerationState() else {
      Issue.record("a mode toggle made before deletion completed must not rebuild the cloud zone")
      return
    }
    #expect(await pauseStore.reason == .userDeletedZone)
    #expect(settings.cloudSyncMode == .off)
    #expect(store.cloudSyncMode == .off)
  }

  @MainActor
  @Test
  func reenableRequestCapturedBeforeDeletionCannotRunAfterDeletion() async throws {
    let gate = DeletionCleanupGate()
    let pusher = RecordingRecordPusher(
      allRecordZonesHook: { await gate.enterAndWaitForRelease() })
    let pauseStore = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    await pusher.setGenerationState(
      .deleted(deletionGeneration: 2, retiredZoneNames: [], modifiedAt: nil))
    let (store, settings, suiteName) = try await makeFixture(
      pusher: pusher, pauseStore: pauseStore, core: try makeInMemoryCore(),
      storeMode: .off)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    // Model Settings capturing the user's toggle before its Task is scheduled.
    // A later accepted deletion supersedes that older intent even when the Task
    // does not execute until the deletion has reached its durable terminal state.
    let staleRequest = try #require(store.makeCloudDeletionReenableRequest())
    let deletion = Task { await store.deleteCloudDataEverywhere(settings: settings) }
    await gate.waitUntilEntered()
    await gate.release()
    #expect(await deletion.value == nil)

    await store.liftCloudDeletionPauseForExplicitReenable(request: staleRequest)

    guard case .deleted? = try await pusher.currentZoneGenerationState() else {
      Issue.record("a re-enable intent older than deletion must not rebuild the cloud zone")
      return
    }
    #expect(await pauseStore.reason == .userDeletedZone)
    #expect(settings.cloudSyncMode == .off)
    #expect(store.cloudSyncMode == .off)
  }

  @MainActor
  @Test
  func resumeRequestCapturedBeforeDeletionCannotAdoptTheNewDeletedZone() async throws {
    let pusher = RecordingRecordPusher()
    let pauseStore = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let (store, settings, suiteName) = try await makeFixture(
      pusher: pusher, pauseStore: pauseStore, core: try makeInMemoryCore())
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
    await store.refreshCloudSyncPauseReason()
    let staleRequest = try #require(await store.makeCloudSyncResumeRequest())

    #expect(await store.deleteCloudDataEverywhere(settings: settings) == nil)
    await store.adoptCurrentCloudAccountAndResumeSync(request: staleRequest)

    guard case .deleted? = try await pusher.currentZoneGenerationState() else {
      Issue.record("a resume click older than deletion must not recreate the cloud zone")
      return
    }
    #expect(await pauseStore.reason == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }
}
