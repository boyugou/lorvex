import Foundation
import LorvexCore
import Testing
@preconcurrency import CloudKit

@testable import LorvexApple
@testable import LorvexCloudSync

// MARK: - Test double

actor RecordingCloudSyncSubscriber: CloudSyncSubscribing {
  private var callCount = 0

  func registerSubscription() async throws {
    callCount += 1
  }

  func registrationCallCount() -> Int { callCount }
}

struct FailingCloudSyncSubscriber: CloudSyncSubscribing {
  func registerSubscription() async throws {
    throw NSError(
      domain: "TestCloudKit", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "CKError: server unreachable"])
  }
}

actor FlakyCloudSyncSubscriber: CloudSyncSubscribing {
  private var callCount = 0

  func registerSubscription() async throws {
    callCount += 1
    if callCount == 1 {
      throw NSError(
        domain: "TestCloudKit", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "CKError: transient unavailable"])
    }
  }

  func registrationCallCount() -> Int { callCount }
}

// MARK: - Tests

@MainActor
@Test
func appStoreCallsRegisterSubscriptionOnFirstRefreshOnly() async throws {
  let subscriber = RecordingCloudSyncSubscriber()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
    cloudSyncSubscriber: subscriber
  )

  await store.refresh()
  let afterFirst = await subscriber.registrationCallCount()
  #expect(afterFirst == 1)
  #expect(store.lastCloudSyncSubscriptionErrorMessage == nil)

  await store.refresh()
  let afterSecond = await subscriber.registrationCallCount()
  #expect(afterSecond == 1, "registerSubscription must not be called on subsequent refreshes")
}

@MainActor
@Test
func appStoreDoesNotFailRefreshWhenSubscriptionThrows() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(
    core: core,
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
    cloudSyncSubscriber: FailingCloudSyncSubscriber()
  )

  await store.refresh()
  // refresh() must complete without propagating the subscription error
  #expect(store.errorMessage == nil || !store.errorMessage!.contains("CKError"))
  #expect(
    store.lastCloudSyncSubscriptionErrorMessage == store.userFacingErrorCopy.somethingWentWrong)
  let logs = try await core.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  let entry = try #require(
    logs.entries.first { $0.origin == "macos.cloud_sync.subscription" })
  #expect(entry.details?.contains("CKError") == true)
}

@MainActor
@Test
func appStoreRetriesSubscriptionAfterFailure() async throws {
  let subscriber = FlakyCloudSyncSubscriber()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
    cloudSyncSubscriber: subscriber
  )

  await store.refresh()
  #expect(store.hasRegisteredSubscription == false)
  #expect(
    store.lastCloudSyncSubscriptionErrorMessage == store.userFacingErrorCopy.somethingWentWrong)
  #expect(await subscriber.registrationCallCount() == 1)

  await store.refresh()
  #expect(store.hasRegisteredSubscription == true)
  #expect(store.lastCloudSyncSubscriptionErrorMessage == nil)
  #expect(await subscriber.registrationCallCount() == 2)
}

@MainActor
@Test
func appStoreHasRegisteredSubscriptionFlagFlipsAfterFirstRefresh() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
  )

  #expect(store.hasRegisteredSubscription == false)
  await store.refresh()
  #expect(store.hasRegisteredSubscription == true)
}

@MainActor
@Test
func appStoreLoadsLocalSurfacesBeforeSubscriptionRegistration() async throws {
  // Registering the CloudKit push subscription is a real network request on the
  // first cold-start refresh, so it must happen AFTER the local surfaces are
  // loaded and rendered — otherwise a slow/hung network freezes the first paint,
  // the codex finding #7 defect. This blocks registration and asserts the on-disk
  // data is already visible by the time registration starts, matching the iPhone
  // refresh ordering (`mobileRefreshPublishesLocalSnapshotBeforeSubscriptionRegistration`).
  let subscriber = BlockingCloudSyncSubscriber()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
    cloudSyncSubscriber: subscriber
  )

  #expect(store.today == .empty)
  let refreshTask = Task { await store.refresh() }
  await subscriber.waitForRegistrationToStart()

  // Registration has started and is blocked on the network; the local surface
  // must already be loaded — the refresh rendered it before touching the network,
  // and the registration flag is still unset because the call has not returned.
  #expect(store.today != .empty)
  #expect(store.hasRegisteredSubscription == false)

  await subscriber.releaseRegistration()
  await refreshTask.value
  #expect(store.hasRegisteredSubscription == true)
}

@MainActor
@Test
func accountNotificationResetsSubscriptionRegistration() async throws {
  // A CKAccountChanged notification always invalidates process-local
  // subscription registration. A same-account notification leaves the durable
  // SQLite traversal state alone; an actual identity switch pauses until the
  // explicit adoption flow runs.
  let subscriber = RecordingCloudSyncSubscriber()
  let fetcher = ScriptedMoreComingFetcher(
    moreComingScript: [false, false], tokenData: Data([0x61]))
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(),
    pusher: RecordingRecordPusher(),
    fetcher: fetcher,
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
    cloudSyncMode: .live,
    cloudSyncSubscriber: subscriber,
    cloudSyncCoordinator: coordinator)

  await store.refresh()
  #expect(store.hasRegisteredSubscription == true)
  #expect(await subscriber.registrationCallCount() == 1)
  let fetchesBeforeRecovery = await fetcher.callCount

  await store.handleCloudKitAccountChange()

  // A same-account recovery is itself the trigger: it must not leave the
  // subscription invalidated or durable sync work waiting for an unrelated
  // activation/mutation after the prior unavailable cycle canceled its wake.
  #expect(store.hasRegisteredSubscription == true)
  #expect(await subscriber.registrationCallCount() == 2)
  #expect(await fetcher.callCount > fetchesBeforeRecovery)
}

@MainActor
@Test
func firstAccountNotificationRecoversPriorUnavailablePauseAndDrains() async throws {
  let subscriber = RecordingCloudSyncSubscriber()
  let accountIdentifier = MutableAccountIdentifier(nil)
  let pauseStore = RecordingCloudSyncPauseStore()
  let fetcher = ScriptedMoreComingFetcher(
    moreComingScript: [false], tokenData: Data([0x63]))
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(),
    pusher: RecordingRecordPusher(),
    fetcher: fetcher,
    accountIdentifier: accountIdentifier,
    accountIdentityStore: RecordingAccountIdentityStore(),
    accountPauseStore: pauseStore)
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
    cloudSyncMode: .live,
    cloudSyncSubscriber: subscriber,
    cloudSyncCoordinator: coordinator)

  // The first notification arrives while CloudKit cannot resolve an account.
  // It must pause durably and must not start account-bound network work.
  await store.handleCloudKitAccountChange()
  #expect(await pauseStore.reason == .accountChanged)
  #expect(store.cloudSyncPauseReason == .accountChanged)
  #expect(store.hasRegisteredSubscription == false)
  #expect(await subscriber.registrationCallCount() == 0)
  #expect(await fetcher.callCount == 0)

  // The next CKAccountChanged edge reveals this device's first account. The
  // handler's refresh must let the fresh-database start gate consume the exact
  // unavailable-account pause, register the subscription, and run a real
  // coordinator pull without another trigger.
  await accountIdentifier.set("account-A")
  await store.handleCloudKitAccountChange()

  #expect(await pauseStore.reason == nil)
  #expect(store.cloudSyncPauseReason == nil)
  #expect(store.hasRegisteredSubscription == true)
  #expect(await subscriber.registrationCallCount() == 1)
  #expect(await fetcher.callCount > 0)
}

@MainActor
@Test
func noOpSubscriberRegisterSubscriptionIsIdempotentAndThrowsFree() async throws {
  let subscriber = NoOpCloudSyncSubscriber()
  try await subscriber.registerSubscription()
  try await subscriber.registerSubscription()
  // No assertion needed — reaching here means no throw occurred.
}

// MARK: - F1: per-subscription save result is not discarded

/// Fake `modifySubscriptions` seam returning a scripted per-subscription result
/// for the subscription the subscriber saves. `result == nil` returns an EMPTY
/// `saveResults` (the "operation succeeded but reported no per-item result"
/// shape) so the missing-result branch can be driven.
private struct FakeSubscriptionModifier: CloudKitSubscriptionModifying {
  let result: Result<CKSubscription, any Error>?

  func modifySubscriptions(
    saving subscriptionsToSave: [CKSubscription],
    deleting subscriptionIDsToDelete: [CKSubscription.ID]
  ) async throws -> (
    saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>],
    deleteResults: [CKSubscription.ID: Result<Void, any Error>]
  ) {
    var saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>] = [:]
    if let result {
      for subscription in subscriptionsToSave {
        saveResults[subscription.subscriptionID] = result
      }
    }
    return (saveResults, [:])
  }
}

@Test
func cloudKitSubscriberSucceedsWhenPerSubscriptionSaveSucceeds() async throws {
  let saved = CKDatabaseSubscription(
    subscriptionID: CloudKitCloudSyncSubscriber.databaseSubscriptionID)
  let subscriber = CloudKitCloudSyncSubscriber(
    modifier: FakeSubscriptionModifier(result: .success(saved)))
  // Reaching here without throwing proves a per-subscription success is honored.
  try await subscriber.registerSubscription()
}

@Test
func cloudKitSubscriberThrowsWhenPerSubscriptionSaveFails() async throws {
  // F1: a per-subscription `.failure` inside an otherwise-successful operation
  // must PROPAGATE, so the caller leaves `hasRegisteredSubscription` false and
  // the next refresh retries instead of latching a never-installed subscription.
  let failure = NSError(
    domain: CKErrorDomain, code: CKError.Code.quotaExceeded.rawValue,
    userInfo: [NSLocalizedDescriptionKey: "CKError: subscription quota exceeded"])
  let subscriber = CloudKitCloudSyncSubscriber(
    modifier: FakeSubscriptionModifier(result: .failure(failure)))

  await #expect(throws: (any Error).self) {
    try await subscriber.registerSubscription()
  }
}

@Test
func cloudKitSubscriberThrowsMissingResultWhenNoPerSubscriptionResult() async throws {
  // F1: an operation that returned but reported NO per-subscription result must
  // throw a missing-result error rather than being read as success.
  let subscriber = CloudKitCloudSyncSubscriber(modifier: FakeSubscriptionModifier(result: nil))

  await #expect(
    throws: CloudSyncSubscriptionError.subscriptionSaveResultMissing(
      CloudKitCloudSyncSubscriber.databaseSubscriptionID)
  ) {
    try await subscriber.registerSubscription()
  }
}
