@testable import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexApple

/// Turning iCloud sync on and off in the running Mac app: turning it on goes
/// live before anything waits, lifts a standing deletion pause, starts the
/// controller, and its first refresh uploads the database; turning it off
/// stops the controller. A request that a cloud-data deletion superseded, or
/// one made while sync is already live, changes nothing.
struct AppStoreCloudSyncModeActionsTests {
  @MainActor
  private func makeOffStore(
    initialPause: CloudSyncPauseReason? = nil
  ) async throws -> (store: AppStore, sync: TestCloudSync) {
    let core = try makeInMemoryCore()
    let sync = TestCloudSync(store: core)
    if let initialPause {
      await sync.identities.saveLastAccountIdentifier("account-a")
      await sync.pause.savePauseReason(initialPause)
    }
    let store = AppStore(core: core, cloudSyncMode: .off, cloudSyncController: sync.controller)
    return (store, sync)
  }

  @MainActor
  @Test
  func turningSyncOnGoesLiveAndUploadsTheDatabase() async throws {
    let (store, sync) = try await makeOffStore()
    let request = try #require(store.makeCloudDeletionReenableRequest())

    let finish = store.turnOnCloudSync(request: request)

    #expect(store.cloudSyncMode == .live, "the switch happens before anything waits")
    await finish?.value
    #expect(await sync.controller.state == .running)
    #expect(try sync.engine.sendCount >= 1, "the first refresh runs a pass")
  }

  @MainActor
  @Test
  func turningSyncOnLiftsAStandingDeletionPause() async throws {
    let (store, sync) = try await makeOffStore(initialPause: .userDeletedZone)
    let request = try #require(store.makeCloudDeletionReenableRequest())

    await store.turnOnCloudSync(request: request)?.value

    #expect(store.cloudSyncMode == .live)
    #expect(await sync.pause.loadPauseReason() == nil, "turning sync on is the explicit re-opt-in")
    #expect(store.cloudSyncPauseReason == nil)
  }

  @MainActor
  @Test
  func aDeletionAcceptedAfterTheRequestSupersedesIt() async throws {
    let (store, sync) = try await makeOffStore()
    let request = try #require(store.makeCloudDeletionReenableRequest())
    store.cloudDataDeletionEpoch += 1

    let finish = store.turnOnCloudSync(request: request)

    #expect(finish == nil)
    #expect(store.cloudSyncMode == .off)
    #expect(sync.engines.engines.isEmpty)
  }

  @MainActor
  @Test
  func turningSyncOnWhileLiveChangesNothing() async throws {
    let (store, sync) = try await makeOffStore()
    let request = try #require(store.makeCloudDeletionReenableRequest())
    await store.turnOnCloudSync(request: request)?.value
    let laterRequest = try #require(store.makeCloudDeletionReenableRequest())

    let finish = store.turnOnCloudSync(request: laterRequest)

    #expect(finish == nil)
    #expect(sync.engines.engines.count == 1)
  }

  @MainActor
  @Test
  func turningSyncOffStopsTheControllerAndOnAgainResumes() async throws {
    let (store, sync) = try await makeOffStore()
    let first = try #require(store.makeCloudDeletionReenableRequest())
    await store.turnOnCloudSync(request: first)?.value

    store.turnOffCloudSync()
    for _ in 0..<1_000 where await sync.controller.state != .stopped { await Task.yield() }
    #expect(store.cloudSyncMode == .off)
    #expect(await sync.controller.state == .stopped)
    #expect(sync.engines.engines[0].cancelled)

    let second = try #require(store.makeCloudDeletionReenableRequest())
    await store.turnOnCloudSync(request: second)?.value
    #expect(store.cloudSyncMode == .live)
    #expect(await sync.controller.state == .running)
  }
}
