@preconcurrency import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import LorvexSync
import Testing

@testable import LorvexApple
@testable import LorvexMobile

private final class RetryWakeClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date

  init(_ value: Date) { self.value = value }

  func now() -> Date { lock.withLock { value } }
  func set(_ value: Date) { lock.withLock { self.value = value } }
}

private actor RetryWakeSleepProbe {
  private var delays: [TimeInterval] = []
  private var continuation: CheckedContinuation<Void, Never>?

  func sleep(_ delay: TimeInterval) async throws {
    try Task.checkCancellation()
    delays.append(delay)
    await withCheckedContinuation { continuation = $0 }
    try Task.checkCancellation()
  }

  func waitUntilScheduled() async {
    while delays.isEmpty { await Task.yield() }
  }

  func recordedDelays() -> [TimeInterval] { delays }

  func fire() {
    continuation?.resume()
    continuation = nil
  }
}

private actor RetryWakeFailOncePusher: CloudSyncRecordPushing {
  private(set) var pushCallCount = 0

  func push(
    _ records: [CKRecord], context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    pushCallCount += 1
    return records.map { record in
      if pushCallCount == 1 {
        return CloudSyncPushResult(
          recordName: record.recordID.recordName, succeeded: false,
          errorMessage: "temporary network loss", isTransient: true)
      }
      return CloudSyncPushResult(recordName: record.recordID.recordName, succeeded: true)
    }
  }

  func waitForPushCallCount(_ target: Int) async {
    while pushCallCount < target { await Task.yield() }
  }
}

private struct RetryWakeFetchError: Error {}

/// Holds the coordinator gate on its first fetch, then fails that pass. Later
/// calls return a terminal empty page so an account-change recovery can prove it
/// actually ran instead of being suppressed by stale pacing state.
private actor GateableThrowOnceRetryWakeFetcher: CloudSyncRemoteChangeFetching {
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private(set) var callCount = 0

  func waitUntilEntered() async {
    if callCount > 0 { return }
    await withCheckedContinuation { enteredWaiters.append($0) }
  }

  func releaseFirstFetch() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }

  func fetchChanges(
    after _: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    callCount += 1
    if callCount == 1 {
      let waiters = enteredWaiters
      enteredWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
      await withCheckedContinuation { releaseContinuation = $0 }
      throw RetryWakeFetchError()
    }
    return CloudSyncRemoteChangeBatch(
      records: [], serverChangeTokenData: Data([0x9f]), moreComing: false,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

private func retryWakeEnvelope() -> SyncEnvelope {
  SyncEnvelope(
    entityType: .task,
    entityId: "01966a3f-7c8b-7d4e-8f3a-00000000f901",
    operation: .upsert,
    version: try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: #"{"title":"Retry wake"}"#,
    deviceId: "retry-wake-device")
}

private func retryWakeCoordinator(
  pusher: any CloudSyncRecordPushing,
  fetcher: any CloudSyncRemoteChangeFetching = StubRemoteChangeFetcher(records: []),
  accountAvailability: CloudKitAccountAvailability = .available,
  accountPauseStore: any CloudSyncPauseStateStoring = InMemoryCloudSyncPauseStateStore()
) -> CloudSyncEngineCoordinator {
  CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: accountAvailability),
    pusher: pusher,
    fetcher: fetcher,
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
    accountPauseStore: accountPauseStore)
}

private func outboundContinuationReport() -> CloudSyncCycleReport {
  CloudSyncCycleReport(
    pushedRecordCount: 1, failedPushCount: 0, fetchedRecordCount: 0,
    moreInboundComing: false, inbound: InboundApplyReport(),
    moreOutboundComing: true)
}

@MainActor
@Test
func macMainAppSchedulesPromptWakeForSuccessfulOutboundContinuation() async throws {
  let clock = RetryWakeClock(Date(timeIntervalSince1970: 1_700_000_000))
  let sleep = RetryWakeSleepProbe()
  let store = AppStore(
    core: StubFocusCoreService(preview: try await makeSeededInMemoryCore()),
    cloudSyncMode: .live,
    cloudSyncCoordinator: retryWakeCoordinator(pusher: RetryWakeFailOncePusher()),
    now: { clock.now() },
    cloudSyncRetrySleep: { try await sleep.sleep($0) })
  defer { store.cancelCloudSyncRetryWake() }

  store.updateCloudSyncRetryWake(
    after: outboundContinuationReport(), retryCurrentWork: false)
  await sleep.waitUntilScheduled()

  #expect(store.cloudSyncPacing.consecutiveFailures == 0)
  #expect(await sleep.recordedDelays() == [CloudSyncPacing.drainContinuationDelay])
}

@MainActor
@Test
func mobileMainAppSchedulesPromptWakeForSuccessfulOutboundContinuation() async throws {
  let clock = RetryWakeClock(Date(timeIntervalSince1970: 1_700_000_000))
  let sleep = RetryWakeSleepProbe()
  let store = MobileStore(
    core: StubFocusCoreService(preview: try await makeSeededInMemoryCore()),
    todayString: { "2026-05-23" }, now: { clock.now() },
    cloudSyncRetrySleep: { try await sleep.sleep($0) },
    cloudSyncMode: .live,
    cloudSyncCoordinator: retryWakeCoordinator(pusher: RetryWakeFailOncePusher()))
  defer { store.cancelCloudSyncRetryWake() }

  store.updateCloudSyncRetryWake(
    after: outboundContinuationReport(), retryCurrentWork: false)
  await sleep.waitUntilScheduled()

  #expect(store.cloudSyncPacing.consecutiveFailures == 0)
  #expect(await sleep.recordedDelays() == [CloudSyncPacing.drainContinuationDelay])
}

@MainActor
@Test
func macGenerationBoundaryKeepsPendingOutboxAliveWithABackoffWake() async throws {
  let clock = RetryWakeClock(Date(timeIntervalSince1970: 1_700_000_000))
  let sleep = RetryWakeSleepProbe()
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [PendingOutboundEnvelope(outboxId: 93, envelope: retryWakeEnvelope())]
  let pusher = RecordingRecordPusher(crossGenerationAfterPush: true)
  let store = AppStore(
    core: core, cloudSyncMode: .live,
    cloudSyncCoordinator: retryWakeCoordinator(pusher: pusher),
    now: { clock.now() },
    cloudSyncRetrySleep: { try await sleep.sleep($0) })
  defer { store.cancelCloudSyncRetryWake() }

  await store.runCloudSyncCycle()
  await sleep.waitUntilScheduled()

  #expect(await pusher.pushedRecordsByName.count == 1)
  #expect(core.markedSyncedIDs.isEmpty)
  #expect(store.cloudSyncPacing.consecutiveFailures == 1)
  #expect(await sleep.recordedDelays() == [CloudSyncPacing.baseDelay * 1.1])
}

@MainActor
@Test
func mobileGenerationBoundaryKeepsPendingOutboxAliveWithABackoffWake() async throws {
  let clock = RetryWakeClock(Date(timeIntervalSince1970: 1_700_000_000))
  let sleep = RetryWakeSleepProbe()
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [PendingOutboundEnvelope(outboxId: 94, envelope: retryWakeEnvelope())]
  let pusher = RecordingRecordPusher(crossGenerationAfterPush: true)
  let store = MobileStore(
    core: core, todayString: { "2026-05-23" }, now: { clock.now() },
    cloudSyncRetrySleep: { try await sleep.sleep($0) },
    cloudSyncMode: .live,
    cloudSyncCoordinator: retryWakeCoordinator(pusher: pusher))
  defer { store.cancelCloudSyncRetryWake() }

  _ = await store.runCloudSyncCycle()
  await sleep.waitUntilScheduled()

  #expect(await pusher.pushedRecordsByName.count == 1)
  #expect(core.markedSyncedIDs.isEmpty)
  #expect(store.cloudSyncPacing.consecutiveFailures == 1)
  #expect(await sleep.recordedDelays() == [CloudSyncPacing.baseDelay * 1.1])
}

@MainActor
@Test
func macExplicitlyUnavailableAccountCancelsInsteadOfPolling() async throws {
  let sleep = RetryWakeSleepProbe()
  let store = AppStore(
    core: StubFocusCoreService(preview: try await makeSeededInMemoryCore()),
    cloudSyncMode: .live,
    cloudSyncCoordinator: retryWakeCoordinator(
      pusher: RecordingRecordPusher(), accountAvailability: .noAccount),
    cloudSyncRetrySleep: { try await sleep.sleep($0) })
  defer { store.cancelCloudSyncRetryWake() }

  await store.runCloudSyncCycle()

  #expect(store.cloudKitAccountAvailability == .noAccount)
  #expect(await sleep.recordedDelays() == [])
}

@MainActor
@Test
func mobileDurablePauseCancelsInsteadOfRetryingANilCycle() async throws {
  let sleep = RetryWakeSleepProbe()
  let pauseStore = InMemoryCloudSyncPauseStateStore(reason: .backfillFailed)
  let store = MobileStore(
    core: StubFocusCoreService(preview: try await makeSeededInMemoryCore()),
    todayString: { "2026-05-23" },
    cloudSyncRetrySleep: { try await sleep.sleep($0) },
    cloudSyncMode: .live,
    cloudSyncCoordinator: retryWakeCoordinator(
      pusher: RecordingRecordPusher(), accountPauseStore: pauseStore))
  defer { store.cancelCloudSyncRetryWake() }

  _ = await store.runCloudSyncCycle()

  #expect(store.cloudSyncPauseReason == .backfillFailed)
  #expect(await sleep.recordedDelays() == [])
}

@MainActor
@Test
func macAccountRecoveryResetsFailureRecordedWhileWaitingForCoordinator() async throws {
  let clock = RetryWakeClock(Date(timeIntervalSince1970: 1_700_000_000))
  let fetcher = GateableThrowOnceRetryWakeFetcher()
  let subscriber = RecordingCloudSyncSubscriber()
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let coordinator = retryWakeCoordinator(
    pusher: RecordingRecordPusher(), fetcher: fetcher)
  let store = AppStore(
    core: core, cloudSyncMode: .live, cloudSyncSubscriber: subscriber,
    cloudSyncCoordinator: coordinator, now: { clock.now() })

  let gateHolder = Task { try? await coordinator.runCycle(sync: core) }
  await fetcher.waitUntilEntered()
  store.cloudSyncPacing.recordFailure()
  let recovery = Task { await store.handleCloudKitAccountChange() }
  while store.cloudSyncPacing.consecutiveFailures != 0 { await Task.yield() }

  // Model the in-flight cycle reporting its failure after the notification's
  // eager reset but before the queued account-change operation can finish.
  store.cloudSyncPacing.recordAttempt(now: clock.now())
  store.cloudSyncPacing.recordFailure()
  await fetcher.releaseFirstFetch()
  _ = await gateHolder.value
  await recovery.value

  #expect(await fetcher.callCount == 2)
  #expect(store.cloudSyncPacing.consecutiveFailures == 0)
  #expect(store.hasRegisteredSubscription)
  #expect(await subscriber.registrationCallCount() == 1)
}

@MainActor
@Test
func mobileAccountRecoveryResetsFailureRecordedWhileWaitingForCoordinator() async throws {
  let clock = RetryWakeClock(Date(timeIntervalSince1970: 1_700_000_000))
  let fetcher = GateableThrowOnceRetryWakeFetcher()
  let subscriber = RecordingCloudSyncSubscriber()
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let coordinator = retryWakeCoordinator(
    pusher: RecordingRecordPusher(), fetcher: fetcher)
  let store = MobileStore(
    core: core, todayString: { "2026-05-23" }, now: { clock.now() },
    cloudSyncMode: .live, cloudSyncSubscriber: subscriber,
    cloudSyncCoordinator: coordinator)

  let gateHolder = Task { try? await coordinator.runCycle(sync: core) }
  await fetcher.waitUntilEntered()
  store.cloudSyncPacing.recordFailure()
  let recovery = Task { await store.handleCloudKitAccountChange() }
  while store.cloudSyncPacing.consecutiveFailures != 0 { await Task.yield() }

  store.cloudSyncPacing.recordAttempt(now: clock.now())
  store.cloudSyncPacing.recordFailure()
  await fetcher.releaseFirstFetch()
  _ = await gateHolder.value
  await recovery.value

  #expect(await fetcher.callCount == 2)
  #expect(store.cloudSyncPacing.consecutiveFailures == 0)
  #expect(store.hasRegisteredSubscription)
  #expect(await subscriber.registrationCallCount() == 1)
}

@Test
func mobileCoalescedCycleReportKeepsTheLatestOutboundContinuationState() {
  let continuing = MobileCloudSyncCycleOutcome(
    lifecycle: .newData, report: outboundContinuationReport())
  let completed = MobileCloudSyncCycleOutcome(
    lifecycle: .noData,
    report: CloudSyncCycleReport(
      pushedRecordCount: 0, failedPushCount: 0, fetchedRecordCount: 0,
      moreInboundComing: false, inbound: InboundApplyReport()))

  #expect(
    MobileCloudSyncCycleOutcome.combine(continuing, completed)
      .report?.moreOutboundComing == false)
  #expect(
    MobileCloudSyncCycleOutcome.combine(completed, continuing)
      .report?.moreOutboundComing == true)
}

@MainActor
@Test
func macMainAppAutomaticallyRetriesAnIdleTransientOutboxFailure() async throws {
  let clock = RetryWakeClock(Date(timeIntervalSince1970: 1_700_000_000))
  let sleep = RetryWakeSleepProbe()
  let pusher = RetryWakeFailOncePusher()
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [PendingOutboundEnvelope(outboxId: 91, envelope: retryWakeEnvelope())]
  let store = AppStore(
    core: core, cloudSyncMode: .live,
    cloudSyncCoordinator: retryWakeCoordinator(pusher: pusher),
    now: { clock.now() },
    cloudSyncRetrySleep: { try await sleep.sleep($0) })
  defer { store.cancelCloudSyncRetryWake() }

  await store.runCloudSyncCycle()
  await sleep.waitUntilScheduled()
  #expect(store.cloudSyncPacing.consecutiveFailures == 1)
  #expect(await sleep.recordedDelays() == [CloudSyncPacing.baseDelay * 1.1])

  clock.set(clock.now().addingTimeInterval(CloudSyncPacing.baseDelay * 1.1))
  await sleep.fire()
  await pusher.waitForPushCallCount(2)
  while store.cloudSyncPacing.consecutiveFailures != 0 { await Task.yield() }

  #expect(store.lastCloudSyncCycleReport?.pushedRecordCount == 1)
  #expect(store.lastCloudSyncRemoteChangeErrorMessage == nil)
}

@MainActor
@Test
func mobileMainAppAutomaticallyRetriesAnIdleTransientOutboxFailure() async throws {
  let clock = RetryWakeClock(Date(timeIntervalSince1970: 1_700_000_000))
  let sleep = RetryWakeSleepProbe()
  let pusher = RetryWakeFailOncePusher()
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.outboxPending = [PendingOutboundEnvelope(outboxId: 92, envelope: retryWakeEnvelope())]
  let store = MobileStore(
    core: core, todayString: { "2026-05-23" }, now: { clock.now() },
    cloudSyncRetrySleep: { try await sleep.sleep($0) },
    cloudSyncMode: .live,
    cloudSyncCoordinator: retryWakeCoordinator(pusher: pusher))
  defer { store.cancelCloudSyncRetryWake() }

  _ = await store.runCloudSyncCycle()
  await sleep.waitUntilScheduled()
  #expect(store.cloudSyncPacing.consecutiveFailures == 1)
  #expect(await sleep.recordedDelays() == [CloudSyncPacing.baseDelay * 1.1])

  clock.set(clock.now().addingTimeInterval(CloudSyncPacing.baseDelay * 1.1))
  await sleep.fire()
  await pusher.waitForPushCallCount(2)
  while store.cloudSyncPacing.consecutiveFailures != 0 { await Task.yield() }

  #expect(store.lastCloudSyncCycleReport?.pushedRecordCount == 1)
  #expect(store.lastCloudSyncRemoteChangeErrorMessage == nil)
}
