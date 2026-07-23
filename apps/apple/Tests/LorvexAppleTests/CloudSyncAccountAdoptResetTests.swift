import Foundation
import LorvexDomain
import LorvexStore
import LorvexSync
import Testing

@testable import LorvexCloudSync
@testable import LorvexCore

private struct AdoptionRebuildFailure: Error {}

private func requireAdoptionRequest(
  _ coordinator: CloudSyncEngineCoordinator,
  sync: any EnvelopeSyncServicing,
  reason: CloudSyncPauseReason
) async throws -> CloudSyncAccountAdoptionRequest {
  try #require(
    await coordinator.makeAccountAdoptionRequest(
      sync: sync, expectedPauseReason: reason))
}

/// Models both sides of a generation rebuild: the old ready zone is already
/// terminal, while candidate readback returns exactly the immutable records the
/// pusher accepted plus the required control observations.
private actor AdoptionGenerationFetcher: CloudSyncRemoteChangeFetching {
  let pusher: RecordingRecordPusher

  init(pusher: RecordingRecordPusher) { self.pusher = pusher }

  func fetchChanges(
    after _: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    let records =
      context.readyWitness == nil
      ? await Array(pusher.pushedRecordsByName.values) : []
    return CloudSyncRemoteChangeBatch(
      records: records, serverChangeTokenData: Data([0xAD]),
      moreComing: false,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers:
        traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

struct CloudSyncAccountAdoptResetTests {
  @Test
  func confirmedAccountSwitchPausesWithoutCopyingDataAutomatically() async throws {
    let pause = RecordingCloudSyncPauseStore()
    let identities = RecordingAccountIdentityStore(initial: "account-A")
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: identities,
      accountPauseStore: pause)

    #expect(try await coordinator.handleAccountChange() == .suppressedDifferentAccount)
    #expect(await pause.reason == .accountChanged)
    #expect(await identities.loadLastAccountIdentifier() == "account-A")
  }

  @Test
  func sameAccountNotificationDoesNotCreateAFalsePause() async throws {
    let pause = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
      accountPauseStore: pause)

    #expect(try await coordinator.handleAccountChange() == .backfilled)
    #expect(await pause.reason == nil)
  }

  @Test
  func freshDatabaseStartGateConsumesPriorUnavailableAccountPause() async throws {
    let core = try makeInMemoryCore()
    let pause = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let identities = RecordingAccountIdentityStore()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
      accountIdentityStore: identities,
      accountPauseStore: pause)

    #expect(await coordinator.passesAccountStartGate(sync: core) == .proceed)
    #expect(await identities.loadLastAccountIdentifier() == "account-A")
    #expect(await identities.savedIdentifiers == ["account-A"])
    #expect(await pause.reason == nil)
    #expect(await pause.clearCount == 1)
    #expect(try core.cloudTraversalAccountBinding() == nil)
  }

  @Test
  func sameAccountNotificationNeverClearsAnUnfinishedAdoption() async throws {
    let pause = RecordingCloudSyncPauseStore(initial: .adoptionInProgress)
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-B"),
      accountPauseStore: pause)

    #expect(try await coordinator.handleAccountChange() == .backfillFailed)
    #expect(await pause.reason == .adoptionInProgress)
    #expect(await pause.clearCount == 0)
  }

  @Test
  func sameAccountNotificationNeverClearsAFailedAdoption() async throws {
    let pause = RecordingCloudSyncPauseStore(initial: .backfillFailed)
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-B"),
      accountPauseStore: pause)

    #expect(try await coordinator.handleAccountChange() == .backfillFailed)
    #expect(await pause.reason == .backfillFailed)
    #expect(await pause.clearCount == 0)
  }

  @Test
  func relaunchGateHaltsWhenExternalIdentityAdvancedButAdoptionDidNotFinish() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-adopt-gate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = SwiftLorvexCoreService(
      databasePath: directory.appendingPathComponent("db.sqlite").path)
    let pause = RecordingCloudSyncPauseStore(initial: .adoptionInProgress)
    let pusher = RecordingRecordPusher()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-B"),
      accountPauseStore: pause)

    #expect(await coordinator.passesAccountStartGate(sync: core) == .halt)
    #expect(await pause.reason == .adoptionInProgress)
    #expect(await pusher.ensureZoneCallCount == 0)
  }

  @Test
  func failedAdoptionTransitionsToDurableRetryWithoutLiftingTheGate() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-adopt-failure-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = SwiftLorvexCoreService(
      databasePath: directory.appendingPathComponent("db.sqlite").path)
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")

    let pause = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let pusher = RecordingRecordPusher(currentZoneEpochError: AdoptionRebuildFailure())
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
      accountPauseStore: pause)

    let request = try await requireAdoptionRequest(
      coordinator, sync: core, reason: .accountChanged)
    #expect(
      !(await coordinator.confirmBackfillIntoCurrentAccount(
        sync: core, request: request)))
    #expect(await pause.reason == .backfillFailed)
    // The authoritative generation read now precedes the first local mutation,
    // so a transport failure leaves the original binding intact for retry.
    #expect(try core.cloudTraversalAccountBinding()?.accountIdentifier == "account-A")
    #expect(await coordinator.passesAccountStartGate(sync: core) == .halt)
  }

  @Test
  func executeUsesDeletedStateAfterAnAdvisoryRequestReadFailure() async throws {
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let task = try await core.createTask(
      title: "Preserved across deleted-state retry", notes: "")
    try core.deferUnknownTypeRecords([
      RawEnvelopeFields(
        entityType: EntityName.task, entityId: task.id,
        operation: "future_operation",
        version: "1711234567892_0000_b1c2d3e4b1c2d3e4",
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
        payload: #"{"future":true}"#, deviceId: "future-device")
    ])
    #expect(try core.unresolvedFutureRecordCount() == 1)

    let pause = RecordingCloudSyncPauseStore(initial: .backfillFailed)
    let pusher = RecordingRecordPusher(
      currentZoneEpochError: AdoptionRebuildFailure())
    await pusher.setGenerationState(
      .deleted(deletionGeneration: 4, retiredZoneNames: [], modifiedAt: nil))
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: AdoptionGenerationFetcher(pusher: pusher),
      accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
      accountPauseStore: pause)

    let request = try await requireAdoptionRequest(
      coordinator, sync: core, reason: .backfillFailed)
    #expect(request.deletionGeneration == nil)
    await pusher.setCurrentZoneEpochError(nil)

    #expect(
      await coordinator.confirmBackfillIntoCurrentAccount(
        sync: core, request: request))
    #expect(await pause.reason == nil)
    #expect(try core.unresolvedFutureRecordCount() == 0)
    #expect((try await core.loadTask(id: task.id)).title == task.title)
    let pushedRecords = await Array(pusher.pushedRecordsByName.values)
    let pushedEntityIDs: [String] = pushedRecords.compactMap { record -> String? in
      guard case .decoded(let envelope) = CloudSyncEnvelopeRecord.decode(record) else {
        return nil
      }
      return envelope.entityId
    }
    #expect(pushedEntityIDs.contains(task.id))
  }

  @Test
  func staleExpectedPauseCannotOverwriteANewerDeletedZoneConsentGate() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-adopt-stale-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = SwiftLorvexCoreService(
      databasePath: directory.appendingPathComponent("db.sqlite").path)
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let pause = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    let identities = RecordingAccountIdentityStore(initial: "account-A")
    let pusher = RecordingRecordPusher()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: identities, accountPauseStore: pause)

    #expect(
      await coordinator.makeAccountAdoptionRequest(
        sync: core, expectedPauseReason: .accountChanged) == nil)
    #expect(await pause.reason == .userDeletedZone)
    #expect(await identities.loadLastAccountIdentifier() == "account-A")
    #expect(try core.cloudTraversalAccountBinding()?.accountIdentifier == "account-A")
    #expect(await pusher.ensureZoneCallCount == 0)
  }

  @Test
  func crashAfterDatabaseAdoptionStaysClosedUntilExplicitRetryPublishesFullInventory()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-adopt-crash-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = SwiftLorvexCoreService(
      databasePath: directory.appendingPathComponent("db.sqlite").path)
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-B")
    let task = try await core.createTask(title: "Inventory after adoption crash", notes: "")
    let pause = RecordingCloudSyncPauseStore(initial: .adoptionInProgress)
    let pusher = RecordingRecordPusher()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: AdoptionGenerationFetcher(pusher: pusher),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-B"),
      accountPauseStore: pause)

    #expect(try await coordinator.runCycle(sync: core) == nil)
    #expect(await pause.reason == .adoptionInProgress)
    #expect(await pusher.ensureZoneCallCount == 0)

    let request = try await requireAdoptionRequest(
      coordinator, sync: core, reason: .adoptionInProgress)
    #expect(
      await coordinator.confirmBackfillIntoCurrentAccount(
        sync: core, request: request))
    #expect(await pause.reason == nil)
    #expect((await pusher.zoneEpoch ?? 0) > RecordingRecordPusher.readyDescriptor.epoch)
    let pushedRecords = await Array(pusher.pushedRecordsByName.values)
    let pushedEntityIDs: [String] = pushedRecords.compactMap { record -> String? in
      guard case .decoded(let envelope) = CloudSyncEnvelopeRecord.decode(record) else {
        return nil
      }
      return envelope.entityId
    }
    #expect(pushedEntityIDs.contains(task.id))
    #expect(try core.currentGenerationSnapshotStaging() == nil)
  }

  @Test
  func terminalPauseCASNeverClearsANewerDeletedZoneReason() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-adopt-cas-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = SwiftLorvexCoreService(
      databasePath: directory.appendingPathComponent("db.sqlite").path)
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let pause = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let pusher = RecordingRecordPusher(
      completeZoneRebuildHook: {
        await pause.savePauseReason(.userDeletedZone)
      })
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: AdoptionGenerationFetcher(pusher: pusher),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
      accountPauseStore: pause)

    let request = try await requireAdoptionRequest(
      coordinator, sync: core, reason: .accountChanged)
    #expect(
      !(await coordinator.confirmBackfillIntoCurrentAccount(
        sync: core, request: request)))
    #expect(await pause.reason == .userDeletedZone)
  }

  @Test
  func successfulAdoptionClearsOnlyAfterExactReadyGenerationAndLocalFinalization() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-adopt-success-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = SwiftLorvexCoreService(
      databasePath: directory.appendingPathComponent("db.sqlite").path)
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let task = try await core.createTask(title: "Must cross the account boundary", notes: "")

    let pause = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let identities = RecordingAccountIdentityStore(initial: "account-A")
    let pusher = RecordingRecordPusher()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: AdoptionGenerationFetcher(pusher: pusher),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: identities, accountPauseStore: pause)

    let request = try await requireAdoptionRequest(
      coordinator, sync: core, reason: .accountChanged)
    #expect(
      await coordinator.confirmBackfillIntoCurrentAccount(
        sync: core, request: request))
    #expect(await pause.reason == nil)
    #expect(await pause.savedReasons.first == .adoptionInProgress)
    #expect(await pause.clearCount == 1)
    #expect(await identities.loadLastAccountIdentifier() == "account-B")
    let binding = try #require(try core.cloudTraversalAccountBinding())
    let databaseInstanceIdentifier = try core.databaseInstanceIdentifier()
    #expect(binding.accountIdentifier == "account-B")
    #expect(binding.databaseInstanceIdentifier == databaseInstanceIdentifier)
    #expect(try core.currentGenerationSnapshotStaging() == nil)
    let pushedRecords = await Array(pusher.pushedRecordsByName.values)
    let pushedEntityIDs: [String] = pushedRecords.compactMap { record -> String? in
      guard case .decoded(let envelope) = CloudSyncEnvelopeRecord.decode(record) else {
        return nil
      }
      return envelope.entityId
    }
    #expect(pushedEntityIDs.contains(task.id))
  }

  @Test
  func preparedAdoptionCannotFollowALaterLiveAccountSwitch() async throws {
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let account = MutableAccountIdentifier("account-B")
    let pause = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let identities = RecordingAccountIdentityStore(initial: "account-A")
    let pusher = RecordingRecordPusher()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: account, accountIdentityStore: identities,
      accountPauseStore: pause)

    let request = try await requireAdoptionRequest(
      coordinator, sync: core, reason: .accountChanged)
    await account.set("account-C")

    #expect(
      !(await coordinator.confirmBackfillIntoCurrentAccount(
        sync: core, request: request)))
    #expect(await pause.reason == .accountChanged)
    #expect(await identities.loadLastAccountIdentifier() == "account-A")
    #expect(try core.cloudTraversalAccountBinding()?.accountIdentifier == "account-A")
    #expect(await pusher.ensureZoneCallCount == 0)
    let pushedRecords = await pusher.pushedRecordsByName
    #expect(pushedRecords.isEmpty)
  }

  @Test
  func repeatedSameReasonPauseInvalidatesAnOlderAdoptionRequest() async throws {
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let pause = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let identities = RecordingAccountIdentityStore(initial: "account-A")
    let pusher = RecordingRecordPusher()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: identities, accountPauseStore: pause)

    let request = try await requireAdoptionRequest(
      coordinator, sync: core, reason: .accountChanged)
    // The visible reason is unchanged, but this is a newer pause event with a
    // distinct revision. The old capability must not authorize the new event.
    await pause.savePauseReason(.accountChanged)

    #expect(
      !(await coordinator.confirmBackfillIntoCurrentAccount(
        sync: core, request: request)))
    #expect(await pause.reason == .accountChanged)
    #expect(await identities.loadLastAccountIdentifier() == "account-A")
    #expect(try core.cloudTraversalAccountBinding()?.accountIdentifier == "account-A")
    #expect(await pusher.ensureZoneCallCount == 0)
    let pushedRecords = await pusher.pushedRecordsByName
    #expect(pushedRecords.isEmpty)
  }

  @Test
  func missingExternalIdentityCannotHideASQLiteAccountMismatch() async throws {
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let pause = RecordingCloudSyncPauseStore()
    let identities = RecordingAccountIdentityStore()
    let pusher = RecordingRecordPusher()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: identities, accountPauseStore: pause)

    #expect(await coordinator.passesAccountStartGate(sync: core) == .halt)
    #expect(await identities.loadLastAccountIdentifier() == "account-A")
    #expect(await identities.savedIdentifiers == ["account-A"])
    #expect(await pause.reason == .accountChanged)
    #expect(try core.cloudTraversalAccountBinding()?.accountIdentifier == "account-A")
    #expect(await pusher.ensureZoneCallCount == 0)
  }

  @Test
  func missingExternalIdentityIsRepairedFromMatchingSQLiteAuthority() async throws {
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let pause = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let identities = RecordingAccountIdentityStore()
    let pusher = RecordingRecordPusher()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
      accountIdentityStore: identities, accountPauseStore: pause)

    #expect(await coordinator.passesAccountStartGate(sync: core) == .proceed)
    #expect(await identities.loadLastAccountIdentifier() == "account-A")
    #expect(await identities.savedIdentifiers == ["account-A"])
    #expect(await pause.reason == nil)
    #expect(await pause.clearCount == 1)
    #expect(try core.cloudTraversalAccountBinding()?.accountIdentifier == "account-A")
    #expect(await pusher.ensureZoneCallCount == 0)
  }

  @Test
  func explicitAdoptionRecoversARestoredDatabaseAndMovesItToTheLiveAccount() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-adopt-restored-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = SwiftLorvexCoreService(
      databasePath: directory.appendingPathComponent("db.sqlite").path)
    let originalBinding = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let task = try await core.createTask(title: "Restored inventory", notes: "")
    let restoredDatabaseIdentifier = "restored-\(UUID().uuidString)"
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: restoredDatabaseIdentifier)
    }
    #expect(try core.databaseInstanceIdentifier() == restoredDatabaseIdentifier)
    #expect(
      try core.cloudTraversalAccountBindingForAdoption()?.databaseInstanceIdentifier
        == originalBinding.databaseInstanceIdentifier)

    let pause = RecordingCloudSyncPauseStore(initial: .accountChanged)
    let identities = RecordingAccountIdentityStore(initial: "account-A")
    let pusher = RecordingRecordPusher()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: AdoptionGenerationFetcher(pusher: pusher),
      accountIdentifier: StubAccountIdentifier(identifier: "account-B"),
      accountIdentityStore: identities, accountPauseStore: pause)

    let request = try await requireAdoptionRequest(
      coordinator, sync: core, reason: .accountChanged)
    #expect(
      await coordinator.confirmBackfillIntoCurrentAccount(
        sync: core, request: request))

    let finalBinding = try #require(try core.cloudTraversalAccountBinding())
    #expect(finalBinding.accountIdentifier == "account-B")
    #expect(finalBinding.databaseInstanceIdentifier == restoredDatabaseIdentifier)
    #expect(await identities.loadLastAccountIdentifier() == "account-B")
    #expect(await pause.reason == nil)
    let pushedRecords = await Array(pusher.pushedRecordsByName.values)
    let pushedEntityIDs: [String] = pushedRecords.compactMap { record -> String? in
      guard case .decoded(let envelope) = CloudSyncEnvelopeRecord.decode(record) else {
        return nil
      }
      return envelope.entityId
    }
    #expect(pushedEntityIDs.contains(task.id))
  }

  @Test
  func newerDeletedGenerationInvalidatesPreparedReenableRequest() async throws {
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let pause = RecordingCloudSyncPauseStore(initial: .userDeletedZone)
    let identities = RecordingAccountIdentityStore(initial: "account-A")
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(
      .deleted(
        deletionGeneration: 4, retiredZoneNames: [], modifiedAt: nil))
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(), pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
      accountIdentityStore: identities, accountPauseStore: pause)

    let request = try #require(
      await coordinator.makeSameAccountDeletedZoneReenableRequest(sync: core))
    await pusher.setGenerationState(
      .deleted(
        deletionGeneration: 5, retiredZoneNames: [], modifiedAt: nil))

    #expect(
      !(await coordinator.confirmDeletedZoneReenable(
        sync: core, request: request, authorization: { true })))
    #expect(await pause.reason == .userDeletedZone)
    #expect(await identities.loadLastAccountIdentifier() == "account-A")
    #expect(try core.cloudTraversalAccountBinding()?.accountIdentifier == "account-A")
    #expect(await pusher.ensureZoneCallCount == 0)
    let pushedRecords = await pusher.pushedRecordsByName
    #expect(pushedRecords.isEmpty)
    guard case .deleted(let generation, _, _)? = try await pusher.currentZoneGenerationState()
    else {
      Issue.record("the newer deleted generation must remain authoritative")
      return
    }
    #expect(generation == 5)
  }

  @Test
  func unconfirmableIdentityFailsClosed() async throws {
    let pause = RecordingCloudSyncPauseStore()
    let coordinator = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: StubAccountIdentifier(identifier: nil),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
      accountPauseStore: pause)

    #expect(try await coordinator.handleAccountChange() == .suppressedDifferentAccount)
    #expect(await pause.reason == .accountChanged)
  }
}
