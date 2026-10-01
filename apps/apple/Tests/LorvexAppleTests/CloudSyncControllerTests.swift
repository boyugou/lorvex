import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync
import Testing

@testable import LorvexCloudSync

// MARK: - Harness

private struct Harness {
  let core: SwiftLorvexCoreService
  let controller: CloudSyncController
  let engines: FakeCloudSyncEngineBox
  let identities: InMemoryCloudSyncAccountIdentityStore
  let pause: InMemoryCloudSyncPauseStateStore
  let fields: InMemoryCloudSyncRecordSystemFieldsStore
  let account: MutableAccountIdentifier

  init(
    storedAccount: String? = nil, currentAccount: String? = "account-a",
    accountChecker: any CloudKitAccountStatusChecking = StubAccountStatusChecker()
  ) async throws {
    core = try SwiftLorvexCoreService.inMemory()
    engines = FakeCloudSyncEngineBox()
    identities = InMemoryCloudSyncAccountIdentityStore()
    if let storedAccount { await identities.saveLastAccountIdentifier(storedAccount) }
    pause = InMemoryCloudSyncPauseStateStore()
    fields = InMemoryCloudSyncRecordSystemFieldsStore()
    account = MutableAccountIdentifier(currentAccount)
    controller = CloudSyncController(
      store: core,
      accountChecker: accountChecker,
      accountIdentifier: account,
      accountIdentityStore: identities,
      pauseStore: pause,
      systemFieldsStore: fields,
      makeEngine: engines.factory)
  }

  var engine: FakeCloudSyncEngine {
    get throws { try #require(engines.latest) }
  }

  func zoneCheckpoint() throws -> String? {
    try core.cloudSyncEngineCheckpoint(.zoneEstablished)
  }

  /// The batch the engine would send now, decoded by record name.
  func batch() async -> [CKRecord] {
    await controller.nextBatch(scope: .all)
  }
}

/// Captures a controller state reported from inside an engine callback.
private actor ObservedState {
  private(set) var value: CloudSyncControllerState?
  func set(_ state: CloudSyncControllerState) { value = state }
}

private let lorvexZone = CKRecordZone.ID(
  zoneName: CloudSyncController.zoneName, ownerName: CKCurrentUserDefaultName)

private func envelope(of record: CKRecord) throws -> SyncEnvelope {
  guard case .decoded(let envelope) = CloudSyncEnvelopeRecord.decode(record) else {
    throw CancellationError()
  }
  return envelope
}

/// A server copy of `envelope` whose HLC is `offsetMs` later (or earlier) and
/// whose title is `title`.
private func serverRecord(
  from envelope: SyncEnvelope, title: String, offsetMs: Int64
) throws -> CKRecord {
  var payload = try #require(
    try JSONSerialization.jsonObject(with: Data(envelope.payload.utf8)) as? [String: Any])
  payload["title"] = title
  let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
  let version = try Hlc(
    physicalMs: UInt64(Int64(envelope.version.physicalMs) + offsetMs),
    counter: envelope.version.counter,
    deviceSuffix: "ffffffffffffffff")
  let server = SyncEnvelope(
    entityType: envelope.entityType, entityId: envelope.entityId,
    operation: envelope.operation, version: version,
    payloadSchemaVersion: envelope.payloadSchemaVersion,
    payload: String(decoding: data, as: UTF8.self), deviceId: "peer-device")
  return CloudSyncEnvelopeRecord.makeRecord(server, zoneID: lorvexZone)
}

private func conflict(client: CKRecord, server: CKRecord) -> CKError {
  CKError(
    .serverRecordChanged,
    userInfo: [
      CKRecordChangedErrorServerRecordKey: server,
      CKRecordChangedErrorClientRecordKey: client,
    ])
}

/// An account checker that holds every status lookup until the test opens it,
/// so a test can act while an evaluation awaits the network.
private final class GatedAccountStatusChecker: CloudKitAccountStatusChecking, @unchecked Sendable {
  private let lock = NSLock()
  private var entered = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var held: [CheckedContinuation<Void, Never>] = []
  private var isOpen = false

  func checkAccountStatus() async throws -> CloudKitAccountAvailability {
    await withCheckedContinuation { continuation in
      let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
        entered = true
        if isOpen {
          continuation.resume()
        } else {
          held.append(continuation)
        }
        defer { entryWaiters = [] }
        return entryWaiters
      }
      waiters.forEach { $0.resume() }
    }
    return .available
  }

  func waitForLookup() async {
    await withCheckedContinuation { continuation in
      let resumeNow = lock.withLock {
        if entered { return true }
        entryWaiters.append(continuation)
        return false
      }
      if resumeNow { continuation.resume() }
    }
  }

  func open() {
    let waiting = lock.withLock {
      isOpen = true
      defer { held = [] }
      return held
    }
    waiting.forEach { $0.resume() }
  }
}

// MARK: - Start and account

@Suite struct CloudSyncControllerLifecycleTests {
  @Test func firstStartBindsTheAccountAndQueuesTheWholeDatabase() async throws {
    let h = try await Harness()
    _ = try await h.core.createTask(title: "Existing", notes: "")

    let state = await h.controller.start()

    #expect(state == .running)
    #expect(await h.identities.loadLastAccountIdentifier() == "account-a")
    #expect(try h.zoneCheckpoint() == "0")
    let engine = try h.engine
    #expect(engine.queuesZoneSave)
    #expect(engine.pendingSaveNames == (try h.core.unsyncedOutboundRecordNames()))
    #expect(!engine.pendingSaveNames.isEmpty)
  }

  @Test func restartDoesNotQueueTheBackfillAgain() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let before = try h.core.unsyncedOutboundRecordNames()
    await h.controller.stop()
    _ = await h.controller.start()
    #expect(try h.core.unsyncedOutboundRecordNames() == before)
    #expect(h.engines.engines.count == 2)
  }

  @Test func aDifferentAccountPausesWithoutAnEngine() async throws {
    let h = try await Harness(storedAccount: "account-a", currentAccount: "account-b")
    let state = await h.controller.start()
    #expect(state == .paused(.accountChanged))
    #expect(h.engines.engines.isEmpty)
    #expect(try await h.pause.loadPauseReason() == .accountChanged)
  }

  @Test func switchingBackToTheBoundAccountResumes() async throws {
    let h = try await Harness(storedAccount: "account-a", currentAccount: "account-b")
    _ = await h.controller.start()
    await h.account.set("account-a")
    let state = await h.controller.handleAccountChange()
    #expect(state == .running)
    #expect(try await h.pause.loadPauseReason() == nil)
  }

  @Test func adoptingTheNewAccountResetsZoneStateAndUploadsAgain() async throws {
    let h = try await Harness(storedAccount: "account-a", currentAccount: "account-b")
    try h.core.setCloudSyncEngineCheckpoint(.zoneEstablished, value: "1")
    try h.core.setCloudSyncEngineCheckpoint(.engineState, value: "c3RhdGU=")
    _ = await h.controller.start()

    let state = try await h.controller.adoptCurrentAccount()

    #expect(state == .running)
    #expect(await h.identities.loadLastAccountIdentifier() == "account-b")
    #expect(try h.zoneCheckpoint() == "0")
    #expect(try h.engine.initialState == nil)
    #expect(try h.engine.queuesZoneSave)
  }

  @Test func stoppingWhileAStartAwaitsTheAccountLeavesSyncStopped() async throws {
    let checker = GatedAccountStatusChecker()
    let h = try await Harness(accountChecker: checker)

    let starting = Task { await h.controller.start() }
    await checker.waitForLookup()
    await h.controller.stop()
    checker.open()

    #expect(await starting.value == .stopped, "the superseded evaluation reports stopped")
    #expect(h.engines.engines.isEmpty, "no engine starts after sync was turned off")
    #expect(await h.controller.state == .stopped)
  }

  @Test func pausingWhileAStartAwaitsTheAccountKeepsSyncPaused() async throws {
    let checker = GatedAccountStatusChecker()
    let h = try await Harness(accountChecker: checker)

    let starting = Task { await h.controller.start() }
    await checker.waitForLookup()
    try await h.controller.enterUserDeletedZonePause()
    checker.open()

    #expect(await starting.value == .stopped, "the superseded evaluation reports stopped")
    #expect(h.engines.engines.isEmpty)
    #expect(await h.controller.state == .paused(.userDeletedZone))
  }

  @Test func anEngineAccountChangeSetsTheEngineAsideBeforeChecking() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.account.set("account-b")

    await h.controller.handleEngineAccountChange()
    #expect(await h.controller.engine == nil, "nothing syncs while the account is checked")

    #expect(await h.controller.start() == .paused(.accountChanged))
    #expect(h.engines.engines.count == 1, "no engine starts for the other account")
  }

  @Test func aSignInToTheBoundAccountKeepsTheEngine() async throws {
    let h = try await Harness()
    _ = await h.controller.start()

    // An engine started without saved state reports the signed-in account as
    // a sign-in; replacing it would start another engine that does the same.
    await h.controller.handleEngineAccountChange(isSignIn: true)

    #expect(await h.controller.engine != nil)
    #expect(h.engines.engines.count == 1)
    #expect(try h.engine.cancelled == false)
    #expect(await h.controller.state == .running)
  }

  @Test func aSignInToAnotherAccountSetsTheEngineAside() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.account.set("account-b")

    await h.controller.handleEngineAccountChange(isSignIn: true)

    #expect(await h.controller.engine == nil)
    #expect(await h.controller.start() == .paused(.accountChanged))
  }

  @Test func anAccountChangeNotificationSetsTheEngineAsideFirst() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.account.set("account-b")
    #expect(await h.controller.handleAccountChange() == .paused(.accountChanged))
    #expect(try h.engine.cancelled)
  }

  @Test func aFailedStartRecoversOnTheNextStart() async throws {
    let h = try await Harness(currentAccount: nil)
    #expect(await h.controller.start() == .unavailable(.couldNotDetermine))
    await h.account.set("account-a")
    #expect(await h.controller.start() == .running)
  }

  @Test func aReseedMarkerQueuesTheDatabaseAgain() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.stop()
    try h.core.setCloudSyncEngineCheckpoint(.reseedRequired, value: "true")

    _ = await h.controller.start()
    #expect(try h.core.cloudSyncEngineCheckpoint(.reseedRequired) == nil, "a clean backfill clears it")
  }

  @Test func aRefetchRequestStartsTheNextEngineWithoutSavedState() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.stop()
    let saved = Data("saved-state".utf8).base64EncodedString()
    try h.core.setCloudSyncEngineCheckpoint(.engineState, value: saved)
    try h.core.setCloudSyncEngineCheckpoint(.refetchRequired, value: "true")

    #expect(await h.controller.start() == .running)
    #expect(try h.engine.initialState == nil, "the whole zone is fetched again")
    #expect(try h.core.cloudSyncEngineCheckpoint(.refetchRequired) == nil, "the request is one-shot")

    await h.controller.stop()
    try h.core.setCloudSyncEngineCheckpoint(.engineState, value: saved)
    _ = await h.controller.start()
    #expect(try h.engine.initialState != nil, "later starts resume from saved state")
  }

  @Test func aRefetchRequestReplacesTheRunningEngineOnTheNextSync() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let first = try h.engine
    try h.core.setCloudSyncEngineCheckpoint(
      .engineState, value: Data("saved-state".utf8).base64EncodedString())
    try h.core.setCloudSyncEngineCheckpoint(.refetchRequired, value: "true")

    _ = try await h.controller.syncNow()

    let second = try h.engine
    #expect(second !== first)
    #expect(first.cancelled)
    #expect(second.initialState == nil)
    #expect(second.fetchCount == 1)
    #expect(try h.core.cloudSyncEngineCheckpoint(.refetchRequired) == nil)
  }

  @Test func replacingTheStoreStopsAndSyncsTheNewDatabase() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let replacement = try SwiftLorvexCoreService.inMemory()
    let task = try await replacement.createTask(title: "After reset", notes: "")

    await h.controller.replaceStore(replacement)
    #expect(await h.controller.state == .stopped)
    _ = await h.controller.start()
    await h.controller.noteLocalChanges()
    let names = await h.batch().compactMap { try? envelope(of: $0).entityId }
    #expect(names.contains(task.id))
  }

  @Test func syncNowStillSendsWhenTheFetchFails() async throws {
    let h = try await Harness()
    h.engines.configure = { engine in engine.onFetch = { throw CKError(.networkFailure) } }
    _ = await h.controller.start()
    await #expect(throws: CKError.self) { try await h.controller.syncNow() }
    #expect(try h.engine.sendCount == 1)
  }

  @Test func deletingWhileStoppedBorrowsAnEngineThatDoesNotSyncOnItsOwn() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.stop()
    _ = try? await h.controller.deleteAllCloudData()
    #expect(h.engines.engines.count == 2)
    #expect(try h.engine.automaticallySync == false)
    #expect(h.engines.engines[0].automaticallySync)
  }

  @Test func aStartDuringACloudDeletionDoesNotAdoptTheDeletionEngine() async throws {
    let h = try await Harness()
    let controller = h.controller
    let observed = ObservedState()
    h.engines.configure = { engine in
      engine.zones = [lorvexZone]
      engine.onSend = { await observed.set(await controller.start()) }
    }

    _ = try? await h.controller.deleteAllCloudData()

    #expect(await observed.value == .stopped, "the start leaves the state to the deletion")
    #expect(h.engines.engines.count == 1, "no sync engine starts beside the deletion engine")
  }

  @Test func signedOutICloudStopsTheEngineAndKeepsState() async throws {
    let h = try await Harness(currentAccount: nil)
    let state = await h.controller.start()
    #expect(state == .unavailable(.couldNotDetermine))
    #expect(h.engines.engines.isEmpty)
  }
}

// MARK: - Outbound

@Suite struct CloudSyncControllerOutboundTests {
  @Test func aSavedBatchConfirmsItsOutboxRowsAndCachesSystemFields() async throws {
    let h = try await Harness()
    _ = try await h.core.createTask(title: "Send me", notes: "")
    _ = await h.controller.start()

    let records = await h.batch()
    #expect(!records.isEmpty)
    await h.controller.handleSentRecords(saved: records, failed: [])

    #expect(try h.core.unsyncedOutboundRecordNames().isEmpty)
    #expect(await h.fields.cachedRecordCount() == records.count)
  }

  @Test func onlyPendingRecordNamesAreSent() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let engine = try h.engine
    engine.remove(pendingRecordZoneChanges: engine.pendingRecordZoneChanges)
    _ = try await h.core.createTask(title: "Not pending yet", notes: "")

    #expect(await h.batch().isEmpty)
    await h.controller.noteLocalChanges()
    #expect(!(await h.batch()).isEmpty)
  }

  /// A task both devices renamed; `peer`'s record is already on the server.
  /// `localEditsLast` decides whose rename carries the later HLC.
  private func contestedTask(localEditsLast: Bool = false) async throws -> (
    h: Harness, taskID: LorvexTask.ID, local: CKRecord, server: CKRecord
  ) {
    let peer = try await Harness()
    let task = try await peer.core.createTask(title: "Original", notes: "")
    _ = await peer.controller.start()
    let created = await peer.batch()
    await peer.controller.handleSentRecords(saved: created, failed: [])

    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.handleFetchedRecords(created)
    _ = await h.batch()
    await h.controller.handleSentRecords(saved: [], failed: [])
    let renameLocal = { _ = try await h.core.updateTask(TaskUpdateDraft(id: task.id, title: "Local title")) }
    let renamePeer = { _ = try await peer.core.updateTask(TaskUpdateDraft(id: task.id, title: "Server title")) }
    try await (localEditsLast ? renamePeer : renameLocal)()
    try await Task.sleep(for: .milliseconds(5))
    try await (localEditsLast ? renameLocal : renamePeer)()

    await h.controller.noteLocalChanges()
    await peer.controller.noteLocalChanges()
    let local = try #require(
      await h.batch().first { (try? envelope(of: $0).entityId) == task.id })
    let server = try #require(
      await peer.batch().first { (try? envelope(of: $0).entityId) == task.id })
    return (h, task.id, local, server)
  }

  @Test func aNewerServerEditWinsTheMerge() async throws {
    let (h, taskID, local, server) = try await contestedTask()

    await h.controller.handleSentRecords(
      saved: [], failed: [(local, conflict(client: local, server: server))])

    #expect(try await h.core.loadTask(id: taskID).title == "Server title")
    #expect(
      await h.fields.systemFields(
        accountIdentifier: "account-a", zoneName: CloudSyncController.zoneName,
        recordName: local.recordID.recordName) != nil,
      "the merged server record's system fields are cached after the commit")
  }

  @Test func anOlderServerEditLosesAndTheLocalEditGoesOutAgain() async throws {
    let (h, taskID, local, server) = try await contestedTask(localEditsLast: true)

    await h.controller.handleSentRecords(
      saved: [], failed: [(local, conflict(client: local, server: server))])

    #expect(try await h.core.loadTask(id: taskID).title == "Local title")
    #expect(try h.engine.pendingSaveNames.contains(local.recordID.recordName))
    #expect(!(try h.core.unsyncedOutboundRecordNames().isEmpty))
  }

  @Test func aSemanticReplayOfTheSameEditIsConfirmed() async throws {
    let h = try await Harness()
    _ = try await h.core.createTask(title: "Same", notes: "")
    _ = await h.controller.start()
    let records = await h.batch()
    let record = try #require(records.first)
    let copy = CloudSyncEnvelopeRecord.makeRecord(try envelope(of: record), zoneID: lorvexZone)

    await h.controller.handleSentRecords(
      saved: Array(records.dropFirst()), failed: [(record, conflict(client: record, server: copy))])

    #expect(try h.core.unsyncedOutboundRecordNames().isEmpty)
    #expect(
      await h.fields.systemFields(
        accountIdentifier: "account-a", zoneName: CloudSyncController.zoneName,
        recordName: record.recordID.recordName) != nil)
  }

  @Test func zoneNotFoundBeforeTheZoneExistsRecreatesIt() async throws {
    let h = try await Harness()
    _ = try await h.core.createTask(title: "First", notes: "")
    _ = await h.controller.start()
    let records = await h.batch()
    let error = CKError(.zoneNotFound)

    await h.controller.handleSentRecords(saved: [], failed: records.map { ($0, error) })

    #expect(await h.controller.state == .running)
    #expect(try h.engine.queuesZoneSave)
    #expect(try h.engine.pendingSaveNames.count == records.count)
  }

  @Test func zoneNotFoundAfterTheZoneExistedPausesInsteadOfReuploading() async throws {
    let h = try await Harness()
    _ = try await h.core.createTask(title: "First", notes: "")
    _ = await h.controller.start()
    try h.core.setCloudSyncEngineCheckpoint(.zoneEstablished, value: "1")
    let records = await h.batch()

    await h.controller.handleSentRecords(
      saved: [], failed: records.map { ($0, CKError(.zoneNotFound)) })

    #expect(await h.controller.state == .paused(.userDeletedZone))
    #expect(try await h.pause.loadPauseReason() == .userDeletedZone)
    #expect(try h.zoneCheckpoint() == nil)
  }

  @Test func unknownItemForgetsTheCachedRecordAndSendsItAgain() async throws {
    let h = try await Harness()
    let task = try await h.core.createTask(title: "Gone on the server", notes: "")
    _ = await h.controller.start()
    await h.controller.handleSentRecords(saved: await h.batch(), failed: [])
    _ = try await h.core.updateTask(TaskUpdateDraft(id: task.id, title: "Edited"))
    await h.controller.noteLocalChanges()
    let record = try #require(
      await h.batch().first { (try? envelope(of: $0).entityId) == task.id })
    let name = record.recordID.recordName

    await h.controller.handleSentRecords(saved: [], failed: [(record, CKError(.unknownItem))])

    #expect(
      await h.fields.systemFields(
        accountIdentifier: "account-a", zoneName: CloudSyncController.zoneName,
        recordName: name) == nil,
      "a stale change tag would make every retry fail the same way")
    #expect(try h.engine.pendingSaveNames.contains(name))
    #expect(!(try h.core.unsyncedOutboundRecordNames().isEmpty))
  }

  @Test func aNewerLocalEditMadeDuringASendIsQueuedAgain() async throws {
    let h = try await Harness()
    let task = try await h.core.createTask(title: "First", notes: "")
    _ = await h.controller.start()
    let sent = await h.batch()
    let record = try #require(sent.first { (try? envelope(of: $0).entityId) == task.id })
    let name = record.recordID.recordName
    _ = try await h.core.updateTask(TaskUpdateDraft(id: task.id, title: "Second"))
    // CloudKit drops a record from the pending set once it saves it.
    try h.engine.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID)])

    await h.controller.handleSentRecords(saved: sent, failed: [])

    #expect(try h.engine.pendingSaveNames.contains(name), "the newer edit still has to go out")
  }

  @Test func quotaExceededKeepsRowsQueuedAndReportsFullStorage() async throws {
    let h = try await Harness()
    _ = try await h.core.createTask(title: "Big", notes: "")
    _ = await h.controller.start()
    let records = await h.batch()

    await h.controller.handleSentRecords(
      saved: [], failed: records.map { ($0, CKError(.quotaExceeded)) })

    #expect(!(try h.core.unsyncedOutboundRecordNames().isEmpty))
    #expect(await h.controller.takePendingReport().iCloudStorageFull)
  }

  @Test func namesWithoutOutboxWorkAreDroppedFromTheEngine() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let engine = try h.engine
    let stale = CKRecord.ID(recordName: "stale", zoneID: lorvexZone)
    engine.add(pendingRecordZoneChanges: [.saveRecord(stale)])
    _ = await h.batch()
    #expect(!engine.pendingSaveNames.contains("stale"))
  }
}

// MARK: - Inbound and state

@Suite struct CloudSyncControllerInboundTests {
  @Test func fetchedRecordsApplyAndEstablishTheZone() async throws {
    let source = try await Harness()
    let task = try await source.core.createTask(title: "From a peer", notes: "")
    _ = await source.controller.start()
    let records = await source.batch()

    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.handleFetchedRecords(records)

    #expect(try await h.core.loadTask(id: task.id).title == "From a peer")
    #expect(try h.zoneCheckpoint() == "1")
    let report = await h.controller.takePendingReport()
    #expect(report.fetchedRecordCount == records.count)
    #expect(report.inbound.appliedEntityTypes.contains(.task))
  }

  @Test func recordsOutsideTheLorvexZoneAreIgnored() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let other = CKRecordZone.ID(zoneName: "LorvexGeneration-e1-1", ownerName: CKCurrentUserDefaultName)
    let record = CKRecord(recordType: CloudSyncEnvelopeRecord.recordType, recordID: .init(recordName: "x", zoneID: other))
    await h.controller.handleFetchedRecords([record])
    #expect(await h.controller.takePendingReport() == .empty)
  }

  @Test func stateIsPersistedUntilAnApplyFails() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.handleStateUpdate(Data("first".utf8))
    #expect(try h.core.cloudSyncEngineCheckpoint(.engineState) == Data("first".utf8).base64EncodedString())

    await h.controller.markInboundApplyFailedForTesting()
    await h.controller.handleStateUpdate(Data("second".utf8))
    #expect(try h.core.cloudSyncEngineCheckpoint(.engineState) == Data("first".utf8).base64EncodedString())

    await h.controller.setEngineAsideAfterInboundFailure()
    #expect(await h.controller.engine == nil, "the failed engine stops fetching at once")
    #expect(await h.controller.state == .running)

    _ = try? await h.controller.syncNow()
    #expect(h.engines.engines.count == 2, "the next sync rebuilds the engine")
    #expect(try h.engine.initialState == Data("first".utf8))
  }

  @Test func aRebuiltEngineIsGivenTheOutboxAgain() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.markInboundApplyFailedForTesting()
    await h.controller.setEngineAsideAfterInboundFailure()

    // A local edit lands while the engine is set aside.
    _ = try await h.core.createTask(title: "Written while set aside", notes: "")
    await h.controller.rebuildEngineIfNeeded()

    #expect(h.engines.engines.count == 2)
    #expect(try h.engine.pendingSaveNames.isEmpty == false)
  }

  @Test func aFailedApplyInASyncSetsTheEngineAside() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let controller = h.controller
    try h.engine.onFetch = { await controller.markInboundApplyFailedForTesting() }

    await #expect(throws: CloudSyncInboundApplyFailure.self) {
      _ = try await h.controller.syncNow()
    }

    #expect(await h.controller.engine == nil, "set aside without waiting for didFetchChanges")
    #expect(await h.controller.state == .running)
  }

  @Test func aStoppedControllerNeitherPersistsNorApplies() async throws {
    let source = try await Harness()
    _ = try await source.core.createTask(title: "From a peer", notes: "")
    _ = await source.controller.start()
    let records = await source.batch()

    // Stopped is how a controller runs a borrowed deletion engine: events that
    // engine reports must not touch local data.
    let h = try await Harness()
    await h.controller.handleStateUpdate(Data("state".utf8))
    await h.controller.handleFetchedRecords(records)
    #expect(try h.core.cloudSyncEngineCheckpoint(.engineState) == nil)
    #expect(await h.controller.takePendingReport() == .empty)
  }

  @Test func appliedRecordsCacheTheirSystemFields() async throws {
    let source = try await Harness()
    _ = try await source.core.createTask(title: "From a peer", notes: "")
    _ = await source.controller.start()
    let records = await source.batch()

    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.handleFetchedRecords(records)
    let name = try #require(records.first?.recordID.recordName)
    let cached = await h.fields.systemFields(
      accountIdentifier: "account-a", zoneName: CloudSyncController.zoneName, recordName: name)
    #expect(cached != nil)
  }

  @Test func legacyZonesAreDeletedWhenSeen() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let legacy = CKRecordZone.ID(zoneName: "LorvexGeneration-e3-7", ownerName: CKCurrentUserDefaultName)
    await h.controller.handleFetchedDatabaseChanges(modifiedZoneIDs: [legacy, lorvexZone], deletions: [])
    #expect(try h.engine.queuedZoneDeletes() == ["LorvexGeneration-e3-7"])
    #expect(try h.zoneCheckpoint() == "1")
  }

  @Test func aDeletedZonePausesSync() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.handleFetchedDatabaseChanges(
      modifiedZoneIDs: [], deletions: [(lorvexZone, .deleted)])
    #expect(await h.controller.state == .paused(.userDeletedZone))
    #expect(await h.controller.engine == nil)
  }

  @Test func anEncryptionKeyResetUploadsEverythingAgain() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    try h.core.setCloudSyncEngineCheckpoint(.zoneEstablished, value: "1")
    await h.controller.handleZoneGone(encryptedDataReset: true)
    _ = await h.controller.start()
    #expect(await h.controller.state == .running)
    #expect(try h.zoneCheckpoint() == "0")
    #expect(try await h.pause.loadPauseReason() == nil)
  }

  @Test func reenablingAfterDeletionStartsAFreshZone() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    await h.controller.handleZoneGone(encryptedDataReset: false)
    let state = try await h.controller.reenableAfterCloudDeletion()
    #expect(state == .running)
    #expect(try h.zoneCheckpoint() == "0")
  }
}

// MARK: - Retired transport

@Suite struct CloudSyncControllerLegacyCleanupTests {
  @Test func theRetiredSubscriptionsAndZonesAreRemovedOnce() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let engine = try h.engine
    #expect(engine.deletedSubscriptions == CloudSyncController.legacySubscriptionIDs)
    try h.core.setCloudSyncEngineCheckpoint(.legacyCleanup, value: nil)
    engine.zones = [
      lorvexZone,
      CKRecordZone.ID(zoneName: "LorvexGeneration-e2-4", ownerName: CKCurrentUserDefaultName),
    ]

    await h.controller.cleanUpLegacyTransportIfNeeded()
    await h.controller.cleanUpLegacyTransportIfNeeded()

    #expect(engine.deletedSubscriptions.count == 2 * CloudSyncController.legacySubscriptionIDs.count)
    #expect(engine.queuedZoneDeletes() == ["LorvexGeneration-e2-4"])
    #expect(try h.core.cloudSyncEngineCheckpoint(.legacyCleanup) == "1")
  }
}

// MARK: - Deleting iCloud data

@Suite struct CloudSyncControllerDeletionTests {
  @Test func deletingCloudDataRemovesLorvexAndLegacyZonesThenPauses() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let engine = try h.engine
    let legacy = CKRecordZone.ID(zoneName: "LorvexGeneration-e1-2", ownerName: CKCurrentUserDefaultName)
    let unrelated = CKRecordZone.ID(zoneName: "SomethingElse", ownerName: CKCurrentUserDefaultName)
    engine.zones = [lorvexZone, legacy, unrelated]
    let controller = h.controller
    engine.onSend = {
      await controller.handleSentDatabaseChanges(
        savedZoneIDs: [], failedZoneSaves: [], deletedZoneIDs: [lorvexZone, legacy],
        failedZoneDeletes: [:])
    }

    try await h.controller.deleteAllCloudData()

    #expect(Set(engine.queuedZoneDeletes()) == [CloudSyncController.zoneName, "LorvexGeneration-e1-2"])
    #expect(await h.controller.state == .paused(.userDeletedZone))
    #expect(try await h.pause.loadPauseReason() == .userDeletedZone)
  }

  @Test func anUnconfirmedDeletionThrowsAndDoesNotPause() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    try h.engine.zones = [lorvexZone]
    await #expect(throws: CloudSyncCloudDeletionIncomplete.self) {
      try await h.controller.deleteAllCloudData()
    }
    #expect(try await h.pause.loadPauseReason() == nil)
  }

  @Test func deletingWhenNothingExistsStillPauses() async throws {
    let h = try await Harness()
    try await h.controller.deleteAllCloudData()
    #expect(await h.controller.state == .paused(.userDeletedZone))
  }
}

// MARK: - Explicit sync

@Suite struct CloudSyncControllerExplicitSyncTests {
  @Test func syncNowReturnsWhatItsFetchApplied() async throws {
    let source = try await Harness()
    _ = try await source.core.createTask(title: "Peer task", notes: "")
    _ = await source.controller.start()
    let records = await source.batch()

    let h = try await Harness()
    _ = await h.controller.start()
    let controller = h.controller
    try h.engine.onFetch = { await controller.handleFetchedRecords(records) }

    let report = try #require(try await h.controller.syncNow())
    #expect(report.fetchedRecordCount == records.count)
    #expect(try h.engine.fetchCount == 1)
    #expect(try h.engine.sendCount == 1)
  }

  @Test func aFailedApplyAbortsTheSyncBeforeSending() async throws {
    let h = try await Harness()
    _ = await h.controller.start()
    let controller = h.controller
    try h.engine.onFetch = { await controller.markInboundApplyFailedForTesting() }
    await #expect(throws: CloudSyncInboundApplyFailure.self) {
      _ = try await h.controller.syncNow()
    }
    #expect(try h.engines.engines[0].sendCount == 0)
  }

  @Test func syncNowIsNilWhileNotRunning() async throws {
    let h = try await Harness()
    #expect(try await h.controller.syncNow() == nil)
  }
}
