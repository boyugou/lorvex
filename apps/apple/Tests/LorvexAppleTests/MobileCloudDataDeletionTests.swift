@preconcurrency import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexMobile

/// Mobile store-level state transitions around "Delete Lorvex iCloud data
/// everywhere": a successful deletion turns sync off (persisted + runtime,
/// services torn down) and records the re-opt-in state; a post-barrier cleanup
/// failure keeps that fail-closed state for retry; and flipping the sync mode
/// back to Live lifts only the deletion pause after a fresh generation is ready.
struct MobileCloudDataDeletionTests {

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

  private static func makeCoordinator(
    pusher: RecordingRecordPusher,
    pauseStore: RecordingCloudSyncPauseStore,
    identityStore: RecordingAccountIdentityStore = RecordingAccountIdentityStore()
  ) -> CloudSyncEngineCoordinator {
    CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(availability: .available),
      pusher: pusher,
      fetcher: RecordingPusherRemoteChangeFetcher(pusher: pusher),
      // A confirmed account identity so the explicit re-enable path can adopt and
      // lift the pause; adoption fails closed on a nil identity (covered by the
      // CloudSync account-adopt tests).
      accountIdentifier: StubAccountIdentifier(identifier: "mobile-cloud-data-test-account"),
      accountIdentityStore: identityStore,
      accountPauseStore: pauseStore)
  }

  @MainActor
  private func makeStore(
    core: (any LorvexCoreServicing)? = nil,
    mode: CloudSyncMode,
    coordinator: CloudSyncEngineCoordinator?,
    serviceFactory: @escaping @Sendable (CloudSyncMode) -> MobileCloudSyncServices = { _ in
      MobileCloudSyncServices(subscriber: NoOpCloudSyncSubscriber(), coordinator: nil)
    }
  ) async throws -> (store: MobileStore, suiteName: String) {
    let suiteName = "LorvexMobileTests.cloudData.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let resolvedCore: any LorvexCoreServicing
    if let core {
      resolvedCore = core
    } else {
      resolvedCore = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    }
    let store = MobileStore(
      core: resolvedCore,
      todayString: { "2026-07-09" },
      defaults: defaults,
      cloudSyncMode: mode,
      cloudSyncCoordinator: coordinator,
      cloudSyncServiceFactory: serviceFactory)
    return (store, suiteName)
  }

  @MainActor
  @Test
  func deleteCloudDataEverywhereTurnsSyncOffAndRecordsReoptInState() async throws {
    let pusher = RecordingRecordPusher()
    let pauseStore = RecordingCloudSyncPauseStore()
    let coordinator = Self.makeCoordinator(pusher: pusher, pauseStore: pauseStore)
    let (store, suiteName) = try await makeStore(mode: .live, coordinator: coordinator)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    let errorMessage = await store.deleteCloudDataEverywhere()

    #expect(errorMessage == nil)
    #expect(await pusher.deleteZoneCallCount == 1)
    #expect(store.cloudSyncMode == .off, "the runtime mode halts cycles immediately")
    #expect(
      MobileSetupPreferences(defaults: UserDefaults(suiteName: suiteName)!).cloudSyncMode == .off,
      "the persisted mode flips off")
    #expect(store.cloudSyncCoordinator == nil, "the live services are torn down")
    #expect(await pauseStore.reason == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }

  @MainActor
  @Test
  func deleteCloudDataWithSyncOffUsesOnDemandLiveServices() async throws {
    // The common case: sync is off (no coordinator on the store) and the user
    // wants the cloud copy gone. The action builds the live-wired coordinator
    // once for the operation.
    let pusher = RecordingRecordPusher()
    let pauseStore = RecordingCloudSyncPauseStore()
    let coordinator = Self.makeCoordinator(pusher: pusher, pauseStore: pauseStore)
    let (store, suiteName) = try await makeStore(
      mode: .off, coordinator: nil,
      serviceFactory: { mode in
        MobileCloudSyncServices(
          subscriber: NoOpCloudSyncSubscriber(),
          coordinator: mode == .live ? coordinator : nil)
      })
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    let errorMessage = await store.deleteCloudDataEverywhere()

    #expect(errorMessage == nil)
    #expect(await pusher.deleteZoneCallCount == 1)
    #expect(store.cloudSyncMode == .off)
    #expect(await pauseStore.reason == .userDeletedZone)
  }

  @MainActor
  @Test
  func cleanupFailureTurnsSyncOffAndKeepsDeletionBarrierForRetry() async throws {
    let pusher = RecordingRecordPusher(deleteZoneError: CKError(.networkUnavailable))
    let pauseStore = RecordingCloudSyncPauseStore()
    let coordinator = Self.makeCoordinator(pusher: pusher, pauseStore: pauseStore)
    let (store, suiteName) = try await makeStore(mode: .live, coordinator: coordinator)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    let errorMessage = await store.deleteCloudDataEverywhere()

    #expect(errorMessage != nil)
    #expect(store.cloudSyncMode == .off)
    #expect(store.cloudSyncCoordinator == nil)
    #expect(await pauseStore.reason == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }

  @MainActor
  @Test
  func pendingDeletionCleanupDoesNotStartDuringDataImport() async throws {
    let pusher = RecordingRecordPusher()
    let pauseStore = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    let coordinator = Self.makeCoordinator(pusher: pusher, pauseStore: pauseStore)
    let (store, suiteName) = try await makeStore(
      mode: .off, coordinator: coordinator)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
    store.isDataImportRunning = true

    await store.retryPendingCloudDataDeletionCleanup()

    #expect(await pusher.allRecordZonesCallCount == 0)
    #expect(!store.isCloudDeletionMaintenanceRunning)
  }

  @MainActor
  @Test
  func reenablingLiveModeLiftsDeletionPauseAfterPublishingFreshGeneration() async throws {
    let core = try makeInMemoryCore()
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(.deleted(
      deletionGeneration: 2, retiredZoneNames: [], modifiedAt: nil))
    let pauseStore = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    let identityStore = RecordingAccountIdentityStore(
      initial: "mobile-cloud-data-test-account")
    let coordinator = Self.makeCoordinator(
      pusher: pusher, pauseStore: pauseStore, identityStore: identityStore)
    let (store, suiteName) = try await makeStore(
      core: core, mode: .off, coordinator: nil,
      serviceFactory: { mode in
        MobileCloudSyncServices(
          subscriber: RecordingCloudSyncSubscriber(),
          coordinator: mode == .live ? coordinator : nil)
      })
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    await store.setCloudSyncModeFromSettings(.live)

    #expect(store.cloudSyncMode == .live)
    #expect(
      await pauseStore.reason == nil,
      "flipping sync back on is the explicit re-opt-in that lifts the deletion pause")
    #expect(store.cloudSyncPauseReason == nil)
  }

  @MainActor
  @Test
  func reenablingLiveModeLeavesAccountChangedPauseForItsOwnConsentFlow() async throws {
    let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    let pauseStore = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let coordinator = Self.makeCoordinator(
      pusher: RecordingRecordPusher(), pauseStore: pauseStore,
      identityStore: RecordingAccountIdentityStore(initial: "prior-account"))
    let (store, suiteName) = try await makeStore(
      core: core, mode: .off, coordinator: nil,
      serviceFactory: { mode in
        MobileCloudSyncServices(
          subscriber: RecordingCloudSyncSubscriber(),
          coordinator: mode == .live ? coordinator : nil)
      })
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    await store.setCloudSyncModeFromSettings(.live)

    #expect(
      await pauseStore.reason == .accountChanged,
      "an account-switch pause must not be lifted by a mode toggle")
    #expect(store.cloudSyncPauseReason == .accountChanged)
  }

  @MainActor
  @Test
  func modeChangeWaitsForOffModeDeletionMaintenanceBeforeRebuilding() async throws {
    let gate = DeletionCleanupGate()
    let pusher = RecordingRecordPusher(
      allRecordZonesHook: { await gate.enterAndWaitForRelease() })
    await pusher.setGenerationState(
      .deleted(deletionGeneration: 2, retiredZoneNames: [], modifiedAt: nil))
    let pauseStore = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    let identityStore = RecordingAccountIdentityStore(
      initial: "mobile-cloud-data-test-account")
    let (store, suiteName) = try await makeStore(
      core: try makeInMemoryCore(), mode: .off, coordinator: nil,
      serviceFactory: { mode in
        MobileCloudSyncServices(
          subscriber: NoOpCloudSyncSubscriber(),
          coordinator: mode == .live
            ? Self.makeCoordinator(
              pusher: pusher, pauseStore: pauseStore,
              identityStore: identityStore)
            : nil)
      })
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    let maintenance = Task { await store.retryPendingCloudDataDeletionCleanup() }
    await gate.waitUntilEntered()

    await store.setCloudSyncModeFromSettings(.live)

    #expect(store.cloudSyncMode == .off)
    #expect(store.pendingCloudSyncMode == .live)
    await gate.release()
    await maintenance.value
    #expect(store.cloudSyncMode == .live)
    #expect(store.pendingCloudSyncMode == nil)
  }

  @MainActor
  @Test
  func modeRequestCapturedBeforeDeletionCannotRunAfterDeletion() async throws {
    let pusher = RecordingRecordPusher()
    let pauseStore = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    let coordinator = Self.makeCoordinator(pusher: pusher, pauseStore: pauseStore)
    let (store, suiteName) = try await makeStore(
      core: try makeInMemoryCore(), mode: .off, coordinator: nil,
      serviceFactory: { mode in
        MobileCloudSyncServices(
          subscriber: NoOpCloudSyncSubscriber(),
          coordinator: mode == .live ? coordinator : nil)
      })
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    // The Binding captures this token synchronously, but its Task may not run
    // until a later user-requested deletion has completed.
    let staleRequest = store.makeCloudSyncModeRequest(.live)
    #expect(await store.deleteCloudDataEverywhere() == nil)

    await store.setCloudSyncModeFromSettings(staleRequest)

    #expect(store.cloudSyncMode == .off)
    #expect(store.pendingCloudSyncMode == nil)
    guard case .deleted? = try await pusher.currentZoneGenerationState() else {
      Issue.record("a mode intent older than deletion must not rebuild the cloud zone")
      return
    }
    #expect(await pauseStore.reason == .userDeletedZone)
  }

  @MainActor
  @Test
  func resumeRequestCapturedBeforeDeletionCannotAdoptTheNewDeletedZone() async throws {
    let pusher = RecordingRecordPusher()
    let pauseStore = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let coordinator = Self.makeCoordinator(pusher: pusher, pauseStore: pauseStore)
    let (store, suiteName) = try await makeStore(
      core: try makeInMemoryCore(), mode: .live, coordinator: coordinator)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
    await store.refreshCloudSyncPauseReason()
    let staleRequest = try #require(await store.makeCloudSyncResumeRequest())

    #expect(await store.deleteCloudDataEverywhere() == nil)
    // Model a stale task retaining/reacquiring the same maintenance coordinator
    // after deletion detached ordinary live sync.
    store.cloudSyncCoordinator = coordinator
    await store.adoptCurrentCloudAccountAndResumeSync(request: staleRequest)

    guard case .deleted? = try await pusher.currentZoneGenerationState() else {
      Issue.record("a resume click older than deletion must not recreate the cloud zone")
      return
    }
    #expect(await pauseStore.reason == .userDeletedZone)
    #expect(store.cloudSyncPauseReason == .userDeletedZone)
  }
}
