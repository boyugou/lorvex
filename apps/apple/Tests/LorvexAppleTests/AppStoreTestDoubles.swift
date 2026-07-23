import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore
import LorvexWidgetKitSupport
import LorvexCloudSync

@testable import LorvexApple

/// Test-only compatibility namespace for fixtures created before generation
/// zones became dynamic. Production has no fixed-zone authority; this literal
/// intentionally matches ``RecordingRecordPusher.readyDescriptor``.
enum CloudSyncZoneConstants {
  static let zoneName = "LorvexData-e1-test-generation-1"
}

actor RecordingTaskSearchIndexer: TaskSearchIndexing {
  private var indexedIDs: [LorvexTask.ID] = []

  func replaceIndexedTasks(_ tasks: [LorvexTask]) async throws {
    indexedIDs = tasks.map(\.id)
  }

  func lastIndexedIDs() -> [LorvexTask.ID] {
    indexedIDs
  }
}

actor RecordingTaskReminderScheduler: TaskReminderScheduling {
  private var scheduledIDs: [LorvexTask.ID] = []
  private var scheduledReminderIDs: [TaskReminder.ID] = []
  private var scheduledFireDates: [Date] = []
  var report: TaskReminderScheduleReport?

  func scheduleReminders(_ reminders: [ScheduledTaskReminder]) async -> TaskReminderScheduleReport {
    scheduledIDs = reminders.map(\.taskID)
    scheduledReminderIDs = reminders.map(\.reminderID)
    scheduledFireDates = reminders.map(\.fireDate)
    if let report {
      return report
    }
    return .scheduled(scheduledIDs.count)
  }

  func lastScheduledIDs() -> [LorvexTask.ID] {
    scheduledIDs
  }

  func lastScheduledReminderIDs() -> [TaskReminder.ID] {
    scheduledReminderIDs
  }

  func lastScheduledFireDates() -> [Date] {
    scheduledFireDates
  }
}

actor RecordingBadgeSetter {
  private var counts: [Int] = []

  func set(_ count: Int) {
    counts.append(count)
  }

  func lastCount() -> Int? {
    counts.last
  }
}

@MainActor
final class RecordingWidgetSnapshotPublisher: WidgetSnapshotPublishing {
  private var snapshots: [LorvexWidgetKitSupport.WidgetSnapshot] = []

  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    let snapshot = WidgetSnapshotProjector(
      now: { Date(timeIntervalSince1970: 1_779_465_600) }
    ).snapshot(
      storageGeneration: source.storageGeneration,
      logicalDay: source.logicalDay,
      today: source.today,
      currentFocus: source.currentFocus,
      timezone: source.timezone,
      habitCatalog: source.habits,
      listCatalog: source.lists,
      statsSource: source.stats)
    snapshots.append(snapshot)
    return snapshot
  }

  func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?
  ) async throws -> LorvexWidgetKitSupport.WidgetSnapshot {
    let snapshot = WidgetSnapshotProjector(now: { Date(timeIntervalSince1970: 1_779_465_600) })
      .snapshot(
        today: today,
        currentFocus: currentFocus,
        timezone: "UTC",
        habitCatalog: habitCatalog,
        listCatalog: lists)
    snapshots.append(snapshot)
    return snapshot
  }

  func publishedSnapshots() -> [LorvexWidgetKitSupport.WidgetSnapshot] {
    snapshots
  }
}

/// Fake CloudKit account checker for coordinator tests.
struct StubAccountStatusChecker: CloudKitAccountStatusChecking {
  var availability: CloudKitAccountAvailability = .available
  func checkAccountStatus() async throws -> CloudKitAccountAvailability { availability }
}

/// Fake iCloud account identifier returning a scripted, stable identity string
/// (or `nil` for "signed out / indeterminate / lookup failed" — the fail-closed
/// unknown). Drives the account-switch backfill-guard tests without a real
/// iCloud account, using the single CloudKit-user-record identity format.
struct StubAccountIdentifier: CloudKitAccountIdentifying {
  var identifier: String?
  func currentAccountIdentifier() async -> String? { identifier }
}

/// Account identifier returning scripted values on successive reads (the final
/// value repeats once the script is exhausted), so a test can simulate the
/// signed-in iCloud account FLIPPING mid-cycle — the start gate reads one
/// account and the cycle tail reads another. A `nil` entry models an
/// undeterminable identity that cycle.
actor ScriptedAccountIdentifier: CloudKitAccountIdentifying {
  private let script: [String?]
  private(set) var callCount = 0

  init(_ script: [String?]) { self.script = script }

  func currentAccountIdentifier() async -> String? {
    defer { callCount += 1 }
    return callCount < script.count ? script[callCount] : (script.last ?? nil)
  }
}

/// Mutable account identity for deterministic operation-serialization tests.
actor MutableAccountIdentifier: CloudKitAccountIdentifying {
  private var identifier: String?

  init(_ identifier: String?) { self.identifier = identifier }

  func currentAccountIdentifier() async -> String? { identifier }
  func set(_ identifier: String?) { self.identifier = identifier }
}

/// Account identifier that reports `before` until `switchAfterChunks` chunks have
/// been pushed (observed via the shared ``RecordingRecordPusher``'s chunk count),
/// then `after` — a different account (a mid-drain switch) or `nil` (a mid-drain
/// identity read failure). Keying the flip on the pusher's chunk count, not on
/// read order, makes it robust to how many times the cycle's gates read the
/// identity: the first chunk always pushes under `before`, and everything after
/// the flip is caught by the per-request boundary guard.
struct ChunkFlippingAccountIdentifier: CloudKitAccountIdentifying {
  let pusher: RecordingRecordPusher
  let before: String
  let after: String?
  let switchAfterChunks: Int

  func currentAccountIdentifier() async -> String? {
    let chunksPushed = await pusher.pushBatchSizes.count
    return chunksPushed >= switchAfterChunks ? after : before
  }
}

/// In-memory account-identity store recording every save, so the account-switch
/// guard tests can assert whether the recorded identity advanced.
actor RecordingAccountIdentityStore: CloudSyncAccountIdentityStoring {
  private var identifier: String?
  private(set) var savedIdentifiers: [String] = []

  init(initial: String? = nil) { self.identifier = initial }

  func loadLastAccountIdentifier() async -> String? { identifier }

  func saveLastAccountIdentifier(_ identifier: String) async {
    self.identifier = identifier
    savedIdentifiers.append(identifier)
  }
}

/// In-memory pause-state store recording every save/clear so the account-guard
/// tests can assert the coordinator durably paused (or resumed) sync.
actor RecordingCloudSyncPauseStore: CloudSyncPauseStateStoring {
  private var snapshot: CloudSyncPauseSnapshot?
  private var revision: UInt64
  var reason: CloudSyncPauseReason? { snapshot?.reason }
  private(set) var savedReasons: [CloudSyncPauseReason] = []
  private(set) var clearCount = 0

  init(initial: CloudSyncPauseReason? = nil) {
    let initialRevision: UInt64 = initial == nil ? 0 : 1
    revision = initialRevision
    snapshot = initial.map {
      CloudSyncPauseSnapshot(reason: $0, revision: initialRevision)
    }
  }

  func loadPauseSnapshot() async -> CloudSyncPauseSnapshot? { snapshot }

  func savePauseReason(_ reason: CloudSyncPauseReason) async {
    snapshot = nextSnapshot(reason)
    savedReasons.append(reason)
  }

  func clearPauseReason() async {
    guard snapshot != nil else { return }
    advanceRevision()
    snapshot = nil
    clearCount += 1
  }

  @discardableResult
  func compareAndSetPauseSnapshot(
    expected: CloudSyncPauseSnapshot?, replacement: CloudSyncPauseReason?
  ) async -> CloudSyncPauseTransition {
    guard snapshot == expected else { return .rejected }
    if let replacement {
      let next = nextSnapshot(replacement)
      snapshot = next
      savedReasons.append(replacement)
      return .applied(next)
    } else {
      advanceRevision()
      snapshot = nil
      clearCount += 1
      return .applied(nil)
    }
  }

  @discardableResult
  func setPauseReasonPreservingUserDeletedZone(
    _ reason: CloudSyncPauseReason?
  ) async -> CloudSyncPauseReason? {
    if snapshot?.reason == .userDeletedZone { return .userDeletedZone }
    guard snapshot?.reason != reason else { return reason }
    if let reason {
      snapshot = nextSnapshot(reason)
      savedReasons.append(reason)
    } else {
      advanceRevision()
      snapshot = nil
      clearCount += 1
    }
    return snapshot?.reason
  }

  private func nextSnapshot(_ reason: CloudSyncPauseReason) -> CloudSyncPauseSnapshot {
    advanceRevision()
    return CloudSyncPauseSnapshot(reason: reason, revision: revision)
  }

  private func advanceRevision() {
    revision &+= 1
    if revision == 0 { revision = 1 }
  }
}

/// Generation-aware record pusher used by app-surface tests. It models one
/// already-published generation by default and implements the full typed seam;
/// tests that exercise a rebuild drive its state transitions explicitly.
actor RecordingRecordPusher: CloudSyncRecordPushing {
  struct StubPushError: Error {}
  struct StubEpochFetchError: Error {}
  struct StubZoneRebuildBeginError: Error {}
  struct StubZoneDeleteError: Error {}
  struct StubZoneFinalizeError: Error {}
  struct StubZoneEnumerationError: Error {}

  private(set) var pushedRecordNames: [String] = []
  private(set) var pushedRecordsByName: [String: CKRecord] = [:]
  private(set) var pushBatchSizes: [Int] = []
  private(set) var rebuildingPushedRecordNames: [String] = []
  private(set) var readyPushedRecordNames: [String] = []
  private(set) var ensureZoneCallCount = 0
  private(set) var clearRecordSystemFieldsCacheCallCount = 0
  private(set) var deleteZoneCallCount = 0
  private(set) var retiredLedgerFinalizeCallCount = 0
  private(set) var allRecordZonesCallCount = 0
  private(set) var zoneRebuildFloors: [Int] = []
  let failingRecordNames: Set<String>
  let throwOnPush: Bool
  let deleteZoneError: Error?
  let throwCKErrorCode: CKError.Code?
  let throwingRecordNames: Set<String>
  let scriptedResultsByRecordName: [String: CloudSyncPushResult]
  private let orderRecorder: OrderRecorderBox?
  private var deleteZoneFailuresBeforeSuccess: Int
  private var retiredLedgerFinalizeFailuresBeforeSuccess: Int
  private var allRecordZonesFailuresBeforeSuccess: Int
  private var recordZoneNames: Set<String>
  private var zoneRebuildBeginFailuresBeforeSuccess: Int
  private var currentZoneEpochError: Error?
  private var state: CloudSyncZoneGenerationState?
  private var remoteRetentionMetadata: CloudSyncAuditRetentionMetadata
  private var scriptedRetentionMergeResults: [CloudSyncAuditRetentionMetadata]
  private let completeZoneRebuildHook: (@Sendable () async throws -> Void)?
  private let currentZoneGenerationStateHook: (@Sendable () async -> Void)?
  private let ensureZoneErrorCode: CKError.Code?
  private let allRecordZonesHook: (@Sendable () async throws -> Void)?
  private let crossGenerationAfterPush: Bool
  private(set) var proposedRetentionMetadata: [CloudSyncAuditRetentionMetadata] = []
  private(set) var reconciledConflictReceiptBatches:
    [[CloudSyncSystemFieldsReceipt]] = []
  private let pushHook: (@Sendable ([CKRecord]) async throws -> Void)?
  private var generationRootValidationResults: [Bool]

  var zoneEpoch: Int? { state?.epoch }

  static let readyDescriptor = CloudSyncGenerationDescriptor(
    epoch: 1, generationID: "test-generation-1",
    zoneName: "LorvexData-e1-test-generation-1",
    readyWitness: "test-ready-witness-1")

  init(
    failingRecordNames: Set<String> = [], throwOnPush: Bool = false,
    throwCKErrorCode: CKError.Code? = nil,
    throwingRecordNames: Set<String> = [],
    scriptedResultsByRecordName: [String: CloudSyncPushResult] = [:],
    deleteZoneError: Error? = nil,
    orderRecorder: OrderRecorderBox? = nil,
    zoneEpoch: Int? = nil,
    currentZoneEpochError: Error? = nil,
    zoneRebuildBeginFailuresBeforeSuccess: Int = 0,
    deleteZoneFailuresBeforeSuccess: Int = 0,
    retiredLedgerFinalizeFailuresBeforeSuccess: Int = 0,
    allRecordZonesFailuresBeforeSuccess: Int = 0,
    recordZoneNames: Set<String> = [],
    remoteRetentionMetadata: CloudSyncAuditRetentionMetadata = .initial,
    scriptedRetentionMergeResults: [CloudSyncAuditRetentionMetadata] = [],
    completeZoneRebuildHook: (@Sendable () async throws -> Void)? = nil,
    currentZoneGenerationStateHook: (@Sendable () async -> Void)? = nil,
    ensureZoneErrorCode: CKError.Code? = nil,
    allRecordZonesHook: (@Sendable () async throws -> Void)? = nil,
    crossGenerationAfterPush: Bool = false,
    pushHook: (@Sendable ([CKRecord]) async throws -> Void)? = nil,
    generationRootValidationResults: [Bool] = []
  ) {
    self.failingRecordNames = failingRecordNames
    self.throwOnPush = throwOnPush
    self.throwCKErrorCode = throwCKErrorCode
    self.throwingRecordNames = throwingRecordNames
    self.scriptedResultsByRecordName = scriptedResultsByRecordName
    self.deleteZoneError = deleteZoneError
    self.orderRecorder = orderRecorder
    self.deleteZoneFailuresBeforeSuccess = deleteZoneFailuresBeforeSuccess
    self.retiredLedgerFinalizeFailuresBeforeSuccess =
      retiredLedgerFinalizeFailuresBeforeSuccess
    self.allRecordZonesFailuresBeforeSuccess = allRecordZonesFailuresBeforeSuccess
    self.recordZoneNames = recordZoneNames
    self.zoneRebuildBeginFailuresBeforeSuccess = zoneRebuildBeginFailuresBeforeSuccess
    self.currentZoneEpochError = currentZoneEpochError
    self.remoteRetentionMetadata = remoteRetentionMetadata
    self.scriptedRetentionMergeResults = scriptedRetentionMergeResults
    self.completeZoneRebuildHook = completeZoneRebuildHook
    self.currentZoneGenerationStateHook = currentZoneGenerationStateHook
    self.ensureZoneErrorCode = ensureZoneErrorCode
    self.allRecordZonesHook = allRecordZonesHook
    self.crossGenerationAfterPush = crossGenerationAfterPush
    self.pushHook = pushHook
    self.generationRootValidationResults = generationRootValidationResults
    if let zoneEpoch {
      self.state = .ready(
        descriptor: CloudSyncGenerationDescriptor(
          epoch: zoneEpoch, generationID: "test-generation-\(zoneEpoch)",
          zoneName: "LorvexData-e\(zoneEpoch)-test-generation-\(zoneEpoch)",
          readyWitness: "test-ready-witness-\(zoneEpoch)"),
        retiredZoneNames: [])
    } else {
      self.state = .ready(descriptor: Self.readyDescriptor, retiredZoneNames: [])
    }
  }

  func currentZoneGenerationState() async throws -> CloudSyncZoneGenerationState? {
    if let currentZoneEpochError { throw currentZoneEpochError }
    await currentZoneGenerationStateHook?()
    return state
  }

  func setCurrentZoneEpochError(_ error: Error?) { currentZoneEpochError = error }
  func setGenerationState(_ state: CloudSyncZoneGenerationState?) {
    self.state = state
  }

  func beginZoneRebuild(
    atLeast floor: Int, ownerIdentifier: String, allowFromDeleted _: Bool,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneRebuildLease {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    if zoneRebuildBeginFailuresBeforeSuccess > 0 {
      zoneRebuildBeginFailuresBeforeSuccess -= 1
      throw StubZoneRebuildBeginError()
    }
    zoneRebuildFloors.append(floor)
    if case .rebuilding(
      let current, let previousActive, _, let retired, _
    ) = state {
      if current.ownerIdentifier == ownerIdentifier { return current }
      // This seam models a foreign lease whose production 24-hour takeover
      // interval has elapsed. The real pusher owns the modification-date CAS;
      // coordinator tests own cleanup/order and need the returned replacement.
      let epoch = max(current.epoch, floor) + 1
      let generation = "test-generation-\(epoch)"
      let replacement = CloudSyncZoneRebuildLease(
        identifier: "test-rebuild-\(epoch)", ownerIdentifier: ownerIdentifier,
        epoch: epoch, generationID: generation,
        candidateZoneName: "LorvexData-e\(epoch)-\(generation)")
      let abandoned = retired.contains(current.candidateZoneName)
        ? retired : retired + [current.candidateZoneName]
      state = .rebuilding(
        lease: replacement, previousActive: previousActive, phase: .claimed,
        retiredZoneNames: abandoned, leaseActivityAt: Date(timeIntervalSince1970: 0))
      return replacement
    }
    let epoch = max(state?.epoch ?? 0, floor) + 1
    let generation = "test-generation-\(epoch)"
    let lease = CloudSyncZoneRebuildLease(
      identifier: "test-rebuild-\(epoch)", ownerIdentifier: ownerIdentifier,
      epoch: epoch, generationID: generation,
      candidateZoneName: "LorvexData-e\(epoch)-\(generation)")
    state = .rebuilding(
      lease: lease, previousActive: state?.activeDescriptor,
      phase: .claimed, retiredZoneNames: state?.retiredZoneNames ?? [],
      leaseActivityAt: Date(timeIntervalSince1970: 0))
    return lease
  }

  func restartZoneRebuild(
    _ lease: CloudSyncZoneRebuildLease,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneRebuildLease {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    guard case .rebuilding(let current, let active, _, let retired, _) = state,
      current == lease
    else { throw CloudSyncZoneEpochError.zoneRebuildLeaseLost }
    let epoch = lease.epoch + 1
    let generation = "test-generation-\(epoch)"
    let next = CloudSyncZoneRebuildLease(
      identifier: "test-rebuild-\(epoch)", ownerIdentifier: lease.ownerIdentifier,
      epoch: epoch, generationID: generation,
      candidateZoneName: "LorvexData-e\(epoch)-\(generation)")
    state = .rebuilding(
      lease: next, previousActive: active, phase: .claimed,
      retiredZoneNames: retired + [lease.candidateZoneName],
      leaseActivityAt: Date(timeIntervalSince1970: 0))
    return next
  }

  func advanceZoneRebuildPhase(
    _ lease: CloudSyncZoneRebuildLease, to phase: CloudSyncZoneRebuildPhase,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    guard case .rebuilding(let current, let active, _, let retired, _) = state,
      current == lease
    else { throw CloudSyncZoneEpochError.zoneRebuildLeaseLost }
    state = .rebuilding(
      lease: lease, previousActive: active, phase: phase,
      retiredZoneNames: retired, leaseActivityAt: Date(timeIntervalSince1970: 0))
  }

  func completeZoneRebuild(
    _ lease: CloudSyncZoneRebuildLease, readyWitness: String,
    manifest _: CloudSyncGenerationManifest,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncGenerationDescriptor {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    guard case .rebuilding(let current, let active, _, let retired, _) = state,
      current == lease
    else { throw CloudSyncZoneEpochError.zoneRebuildLeaseLost }
    let descriptor = CloudSyncGenerationDescriptor(
      epoch: lease.epoch, generationID: lease.generationID,
      zoneName: lease.candidateZoneName, readyWitness: readyWitness)
    state = .ready(
      descriptor: descriptor,
      retiredZoneNames: retired + (active.map { [$0.zoneName] } ?? []))
    try await completeZoneRebuildHook?()
    return descriptor
  }

  func markCloudDataDeleted(
    atLeast generationFloor: Int,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneGenerationState {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    let names = (state?.retiredZoneNames ?? [])
      + (state?.activeDescriptor.map { [$0.zoneName] } ?? [])
    let deleted = CloudSyncZoneGenerationState.deleted(
      deletionGeneration: max(state?.epoch ?? 0, generationFloor) + 1,
      retiredZoneNames: names, modifiedAt: nil)
    state = deleted
    return deleted
  }

  func ensureZone(
    _ zoneID: CKRecordZone.ID, expectation _: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    _ = zoneID
    ensureZoneCallCount += 1
    orderRecorder?.record("ensureZone")
    if let ensureZoneErrorCode { throw CKError(ensureZoneErrorCode) }
  }

  func ensureGenerationRoot(
    _ lease: CloudSyncZoneRebuildLease,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws { _ = lease }

  func validateGenerationRoot(
    context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> Bool {
    guard !generationRootValidationResults.isEmpty else { return true }
    return generationRootValidationResults.removeFirst()
  }

  func saveGenerationSeal(
    _ lease: CloudSyncZoneRebuildLease, readyWitness _: String,
    manifest _: CloudSyncGenerationManifest,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws { _ = lease }

  func publishTraversalWitness(
    context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    traversalIdentifier _: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func deleteTraversalWitness(
    context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    traversalIdentifier _: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func readAuditRetentionMetadata(
    context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncAuditRetentionMetadata? { remoteRetentionMetadata }

  func mergeAuditRetentionMetadata(
    _ proposed: CloudSyncAuditRetentionMetadata,
    context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncAuditRetentionMetadata {
    proposedRetentionMetadata.append(proposed)
    if !scriptedRetentionMergeResults.isEmpty {
      remoteRetentionMetadata = scriptedRetentionMergeResults.removeFirst()
    } else {
      remoteRetentionMetadata = proposed
    }
    return remoteRetentionMetadata
  }

  func currentRemoteRetentionMetadata() -> CloudSyncAuditRetentionMetadata {
    remoteRetentionMetadata
  }

  func publishGenerationWake(
    descriptor _: CloudSyncGenerationDescriptor,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func push(
    _ records: [CKRecord], context _: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    pushBatchSizes.append(records.count)
    if let throwCKErrorCode { throw CKError(throwCKErrorCode) }
    if throwOnPush
      || !throwingRecordNames.isDisjoint(with: records.map { $0.recordID.recordName })
    { throw StubPushError() }
    pushedRecordNames.append(contentsOf: records.map { $0.recordID.recordName })
    switch expectation {
    case .rebuilding:
      rebuildingPushedRecordNames.append(contentsOf: records.map { $0.recordID.recordName })
    case .ready:
      readyPushedRecordNames.append(contentsOf: records.map { $0.recordID.recordName })
    case .previousActive:
      break
    }
    for record in records {
      pushedRecordsByName[record.recordID.recordName] = record
    }
    try await pushHook?(records)
    let results = records.map { record in
      scriptedResultsByRecordName[record.recordID.recordName]
        ?? CloudSyncPushResult(
          recordName: record.recordID.recordName,
          succeeded: !failingRecordNames.contains(record.recordID.recordName),
          errorMessage: failingRecordNames.contains(record.recordID.recordName)
            ? "stub push failure" : nil)
    }
    if crossGenerationAfterPush {
      let replacement = CloudSyncGenerationDescriptor(
        epoch: Self.readyDescriptor.epoch + 1,
        generationID: "test-generation-after-push",
        zoneName: "LorvexData-e2-test-generation-after-push",
        readyWitness: "test-ready-witness-after-push")
      state = .ready(descriptor: replacement, retiredZoneNames: [])
    }
    return results
  }

  func commitReconciledConflictSystemFields(
    _ receipts: [CloudSyncSystemFieldsReceipt], context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {
    reconciledConflictReceiptBatches.append(receipts)
  }

  func physicallyDelete(
    _ recordIDs: [CKRecord.ID], context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> [CKRecord.ID: Result<Void, any Error>] {
    Dictionary(uniqueKeysWithValues: recordIDs.map { ($0, .success(())) })
  }

  func deleteRetiredZone(
    zoneName: String, accountIdentifier _: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {
    deleteZoneCallCount += 1
    orderRecorder?.record("deleteZone")
    if deleteZoneFailuresBeforeSuccess > 0 {
      deleteZoneFailuresBeforeSuccess -= 1
      throw StubZoneDeleteError()
    }
    if let deleteZoneError { throw deleteZoneError }
    recordZoneNames.remove(zoneName)
  }

  func finalizeRetiredZoneDeletion(
    zoneName: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {
    retiredLedgerFinalizeCallCount += 1
    orderRecorder?.record("finalizeRetiredZone")
    if retiredLedgerFinalizeFailuresBeforeSuccess > 0 {
      retiredLedgerFinalizeFailuresBeforeSuccess -= 1
      throw StubZoneFinalizeError()
    }
    guard let state else { return }
    let remaining = state.retiredZoneNames.filter { $0 != zoneName }
    switch state {
    case .ready(let descriptor, _, _):
      self.state = .ready(descriptor: descriptor, retiredZoneNames: remaining)
    case .rebuilding(let lease, let active, let phase, _, let leaseActivityAt):
      self.state = .rebuilding(
        lease: lease, previousActive: active, phase: phase,
        retiredZoneNames: remaining, leaseActivityAt: leaseActivityAt)
    case .deleted(let deletionGeneration, _, let modifiedAt):
      self.state = .deleted(
        deletionGeneration: deletionGeneration,
        retiredZoneNames: remaining, modifiedAt: modifiedAt)
    }
  }

  func allRecordZones(
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> [CKRecordZone] {
    allRecordZonesCallCount += 1
    try await allRecordZonesHook?()
    if allRecordZonesFailuresBeforeSuccess > 0 {
      allRecordZonesFailuresBeforeSuccess -= 1
      throw StubZoneEnumerationError()
    }
    return recordZoneNames.sorted().map {
      CKRecordZone(zoneID: CKRecordZone.ID(
        zoneName: $0, ownerName: CKCurrentUserDefaultName))
    }
  }

  func clearRecordSystemFieldsCache(
    accountIdentifier _: String, zoneName _: String
  ) async { clearRecordSystemFieldsCacheCallCount += 1 }

  func clearAllRecordSystemFieldsCache() async {
    clearRecordSystemFieldsCacheCallCount += 1
  }
}

/// Readback fake for generation rebuilds. It returns the exact records most
/// recently accepted by ``RecordingRecordPusher`` so candidate readback tests
/// exercise the real snapshot-manifest comparison instead of bypassing it.
struct RecordingPusherRemoteChangeFetcher: CloudSyncRemoteChangeFetching {
  let pusher: RecordingRecordPusher

  func fetchChanges(
    after _: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    let records = await Array(pusher.pushedRecordsByName.values)
    return CloudSyncRemoteChangeBatch(
      records: records, serverChangeTokenData: Data([1]),
      moreComing: false,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

/// Fake remote-change fetcher returning a fixed batch of CKRecords.
struct StubRemoteChangeFetcher: CloudSyncRemoteChangeFetching {
  var records: [CKRecord]
  var deletedRecordNames: [String] = []
  var serverChangeTokenData: Data?
  var moreComing = false
  var zoneName = CloudSyncZoneConstants.zoneName

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    CloudSyncRemoteChangeBatch(
      records: records, deletedRecordNames: deletedRecordNames,
      serverChangeTokenData: serverChangeTokenData,
      moreComing: moreComing,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

/// Fetcher whose `moreComing` flag is scripted per call: it returns the
/// successive elements of `moreComingScript`, then false once the script is
/// exhausted. Drives the inbound-backlog drain test, where a coordinator must
/// keep pulling while `moreComing` is true. Records how many fetches ran.
actor ScriptedMoreComingFetcher: CloudSyncRemoteChangeFetching {
  private let moreComingScript: [Bool]
  private let records: [CKRecord]
  private let tokenData: Data?
  private(set) var callCount = 0

  init(moreComingScript: [Bool], records: [CKRecord] = [], tokenData: Data? = nil) {
    self.moreComingScript = moreComingScript
    self.records = records
    self.tokenData = tokenData
  }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    let moreComing = callCount < moreComingScript.count ? moreComingScript[callCount] : false
    callCount += 1
    return CloudSyncRemoteChangeBatch(
      records: records, serverChangeTokenData: tokenData,
      moreComing: moreComing,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

/// Fetcher that runs an injected async side effect on its FIRST `fetchChanges`
/// call, then returns an empty batch. The fetch happens after the start gate
/// proceeded but before the cycle tail, so the side effect deterministically
/// interleaves mid-cycle work — e.g. a `CKAccountChanged` that flips the device to
/// a different iCloud account while an in-flight cycle is still applying records.
actor SideEffectOnFetchRemoteChangeFetcher: CloudSyncRemoteChangeFetching {
  private let onFirstFetch: @Sendable () async -> Void
  private var didFire = false

  init(onFirstFetch: @escaping @Sendable () async -> Void) { self.onFirstFetch = onFirstFetch }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    if !didFire {
      didFire = true
      await onFirstFetch()
    }
    if let boundaryGuard, !(await boundaryGuard()) {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    return CloudSyncRemoteChangeBatch(
      records: [], serverChangeTokenData: nil,
      moreComing: false,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

/// Suspends one fetch until the test releases it, exposing a deterministic
/// window in which a second top-level coordinator operation attempts to enter.
actor GateableRemoteChangeFetcher: CloudSyncRemoteChangeFetching {
  private var didEnter = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func waitUntilEntered() async {
    if didEnter { return }
    await withCheckedContinuation { entryWaiters.append($0) }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    didEnter = true
    let waiters = entryWaiters
    entryWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
    await withCheckedContinuation { releaseContinuation = $0 }
    return CloudSyncRemoteChangeBatch(
      records: [], serverChangeTokenData: nil,
      moreComing: false, observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

/// Holds a `CloudSyncEngineCoordinator` so a fake constructed before the
/// coordinator can call back into it (breaking the construction cycle). The
/// coordinator is a value type whose stores are shared reference types, so the
/// held copy drives the SAME stores as the coordinator under test.
actor CloudSyncCoordinatorBox {
  private(set) var coordinator: CloudSyncEngineCoordinator?
  func set(_ coordinator: CloudSyncEngineCoordinator) { self.coordinator = coordinator }
}

/// Fetcher that throws a scripted `CKError` on its first call, then returns a
/// fixed batch on every subsequent call. Drives the CloudKit-error recovery
/// tests (`changeTokenExpired`, `zoneNotFound`) where the coordinator must
/// reset state and retry the fetch once within the same cycle.
actor ThrowOnceRemoteChangeFetcher: CloudSyncRemoteChangeFetching {
  let error: CKError
  let recoveredRecords: [CKRecord]
  let recoveredTokenData: Data?
  private(set) var callCount = 0

  init(error: CKError, recoveredRecords: [CKRecord], recoveredTokenData: Data? = nil) {
    self.error = error
    self.recoveredRecords = recoveredRecords
    self.recoveredTokenData = recoveredTokenData
  }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    callCount += 1
    if callCount == 1 { throw error }
    return CloudSyncRemoteChangeBatch(
      records: recoveredRecords, serverChangeTokenData: recoveredTokenData,
      moreComing: false,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers: traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

/// Reports `before` until a specific fetcher has entered CloudKit once, then
/// `after`. This couples an account flip to the external fetch boundary rather
/// than to a fragile number of identity reads, which legitimately grows as new
/// per-request guards are added.
struct FetchCountSwitchingAccountIdentifier: CloudKitAccountIdentifying {
  let fetcher: ThrowOnceRemoteChangeFetcher
  let before: String
  let after: String

  func currentAccountIdentifier() async -> String? {
    await fetcher.callCount == 0 ? before : after
  }
}

/// Shared monotonic event log so a test can assert the relative order of steps
/// that happen across two different fakes (for example, a fleet-visible delete
/// barrier versus physical zone cleanup). Lock-backed so a synchronous fake and an
/// actor-isolated fake can both append.
final class OrderRecorderBox: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [String] = []

  func record(_ event: String) {
    lock.lock()
    defer { lock.unlock() }
    events.append(event)
  }

  var snapshot: [String] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
}

/// Captured arguments for the atomic current-and-future EventKit replacement.
struct FakeEventKitFutureSeriesReplacement: Equatable, Sendable {
  let originalLorvexEventID: String
  let occurrenceDate: Date
  let replacement: CalendarEventExport
  let replacementLorvexEventID: String
  let target: EventKitWriteTarget
}

/// Fake `EventKitAccessing`: records ingest fetches + write-back calls and
/// returns a configurable event list, without touching a real `EKEventStore`.
actor FakeEventKitAccess: EventKitAccessing {
  var fetchResult: [EventKitFetchedEvent] = []
  var availableCalendarResult: [EventKitCalendarDescriptor] = []
  var writableCalendarResult: [EventKitCalendarDescriptor] = []
  var lorvexEventCalendarIDResult: String?
  var eventSourceResult: EventKitEventSource?
  var readAccessGranted = true
  nonisolated(unsafe) var readAuthorizationStateOverride: EventKitReadAuthorizationState = .authorized
  private(set) var requestAccessCount = 0
  private(set) var fetchCalendarFilters: [EventKitCalendarFilter] = []
  private(set) var fetchWindowEndDays: [String] = []
  private(set) var writes: [(key: String?, title: String, lorvexID: String)] = []
  private(set) var writeRecurrences: [String?] = []
  private(set) var writeTargets: [EventKitWriteTarget] = []
  private(set) var futureSeriesReplacements: [FakeEventKitFutureSeriesReplacement] = []
  private(set) var calendarIDLookups: [String] = []
  private(set) var eventSourceLookups: [String] = []
  private(set) var deletes: [String] = []
  private(set) var occurrenceRemovals: [(lorvexID: String, occurrenceDate: Date)] = []
  private(set) var futureSeriesRemovals: [(lorvexID: String, occurrenceDate: Date)] = []
  private var upsertError: EventKitAccessError?
  private var futureSeriesReplacementError: EventKitAccessError?
  private var nextKey = 0

  init(fetchResult: [EventKitFetchedEvent] = []) { self.fetchResult = fetchResult }

  func requestAccess() async throws -> Bool {
    requestAccessCount += 1
    return readAccessGranted
  }
  nonisolated func isReadAuthorized() -> Bool { readAuthorizationState().canRead }
  nonisolated func readAuthorizationState() -> EventKitReadAuthorizationState {
    readAuthorizationStateOverride
  }

  func availableCalendars() async throws -> [EventKitCalendarDescriptor] {
    guard readAccessGranted else { throw EventKitAccessError.readAccessDenied }
    return availableCalendarResult
  }

  func writableCalendars() async throws -> [EventKitCalendarDescriptor] {
    guard readAccessGranted else { throw EventKitAccessError.readAccessDenied }
    return writableCalendarResult
  }

  func lorvexEventCalendarID(lorvexEventID: String) async -> String? {
    guard readAccessGranted else { return nil }
    calendarIDLookups.append(lorvexEventID)
    return lorvexEventCalendarIDResult
  }

  func eventSource(forEventKey key: String, dayHint: String?) async -> EventKitEventSource? {
    guard readAccessGranted else { return nil }
    eventSourceLookups.append(key)
    return eventSourceResult
  }

  func setEventSourceResult(_ source: EventKitEventSource?) { eventSourceResult = source }

  func fetchEvents(
    start: Date, end: Date, windowEndDay: String,
    calendarFilter: EventKitCalendarFilter
  ) async throws -> [EventKitFetchedEvent] {
    guard readAccessGranted else { throw EventKitAccessError.readAccessDenied }
    fetchCalendarFilters.append(calendarFilter)
    fetchWindowEndDays.append(windowEndDay)
    return fetchResult
  }

  func upsertLorvexEvent(
    existingKey: String?, title: String, start: Date, end: Date,
    isAllDay: Bool, location: String?, notesPatch: EventKitNotesPatch,
    recurrence: String?, lorvexEventID: String,
    target: EventKitWriteTarget = .lorvexDefault
  ) async throws -> EventKitWriteResult {
    if let upsertError { throw upsertError }
    writes.append((key: existingKey, title: title, lorvexID: lorvexEventID))
    writeRecurrences.append(recurrence)
    writeTargets.append(target)
    let key = existingKey ?? { nextKey += 1; return "ek-key-\(nextKey)" }()
    return EventKitWriteResult(providerEventKey: key)
  }

  func replaceFutureLorvexEventSeries(
    originalLorvexEventID: String,
    occurrenceDate: Date,
    replacement: CalendarEventExport,
    replacementLorvexEventID: String,
    target: EventKitWriteTarget = .lorvexDefault
  ) async throws -> EventKitWriteResult {
    futureSeriesReplacements.append(
      FakeEventKitFutureSeriesReplacement(
        originalLorvexEventID: originalLorvexEventID,
        occurrenceDate: occurrenceDate,
        replacement: replacement,
        replacementLorvexEventID: replacementLorvexEventID,
        target: target))
    if let futureSeriesReplacementError { throw futureSeriesReplacementError }
    nextKey += 1
    return EventKitWriteResult(providerEventKey: "ek-key-\(nextKey)")
  }

  func deleteLorvexEvent(providerEventKey: String) async throws { deletes.append(providerEventKey) }
  func deleteLorvexEvent(lorvexEventID: String) async throws { deletes.append(lorvexEventID) }
  func removeLorvexEventOccurrence(lorvexEventID: String, occurrenceDate: Date) async throws {
    occurrenceRemovals.append((lorvexID: lorvexEventID, occurrenceDate: occurrenceDate))
  }
  func removeFutureLorvexEventSeries(
    lorvexEventID: String, occurrenceDate: Date
  ) async throws {
    futureSeriesRemovals.append((lorvexID: lorvexEventID, occurrenceDate: occurrenceDate))
  }

  func recordedWrites() -> [(key: String?, title: String, lorvexID: String)] { writes }
  func recordedWriteRecurrences() -> [String?] { writeRecurrences }
  func recordedFutureSeriesReplacements() -> [FakeEventKitFutureSeriesReplacement] {
    futureSeriesReplacements
  }
  func recordedCalendarIDLookups() -> [String] { calendarIDLookups }
  func recordedEventSourceLookups() -> [String] { eventSourceLookups }
  func recordedDeletes() -> [String] { deletes }
  func recordedOccurrenceRemovals() -> [(lorvexID: String, occurrenceDate: Date)] {
    occurrenceRemovals
  }
  func recordedFutureSeriesRemovals() -> [(lorvexID: String, occurrenceDate: Date)] {
    futureSeriesRemovals
  }
  func recordedRequestAccessCount() -> Int { requestAccessCount }
  func recordedFetchWindowEndDays() -> [String] { fetchWindowEndDays }
  func setReadAccessGranted(_ granted: Bool) {
    readAccessGranted = granted
    readAuthorizationStateOverride = granted ? .authorized : .unavailable
  }
  func setReadAuthorizationState(_ state: EventKitReadAuthorizationState) {
    readAuthorizationStateOverride = state
    readAccessGranted = state.canRead
  }
  func setAvailableCalendars(_ calendars: [EventKitCalendarDescriptor]) {
    availableCalendarResult = calendars
  }
  func setWritableCalendars(_ calendars: [EventKitCalendarDescriptor]) {
    writableCalendarResult = calendars
  }
  func setLorvexEventCalendarID(_ id: String?) { lorvexEventCalendarIDResult = id }
  func setUpsertError(_ error: EventKitAccessError?) { upsertError = error }
  func setFutureSeriesReplacementError(_ error: EventKitAccessError?) {
    futureSeriesReplacementError = error
  }
  func recordedWriteTargets() -> [EventKitWriteTarget] { writeTargets }
}

/// In-memory `EventKitProviderServicing` recording the provider-mirror calls
/// the coordinator makes (no SQLite).
final class FakeEventKitProvider: EventKitProviderServicing, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var ingestedBatches: [[ProviderEventData]] = []
  private(set) var ingestedBuildModes: [CalendarAiAccessMode] = []
  private(set) var ingestedWindows: [(start: String, end: String)] = []
  private(set) var links: [(taskID: String, key: String)] = []
  private(set) var scopeEnabled: Bool?
  private(set) var clearCount = 0
  var eventKitLinksForTaskError: Error?

  func ingestEventKitEvents(
    _ events: [ProviderEventData], builtAtMode: CalendarAiAccessMode,
    windowStart: String, windowEnd: String
  ) throws -> Int {
    lock.withLock {
      ingestedBatches.append(events)
      ingestedBuildModes.append(builtAtMode)
      ingestedWindows.append((windowStart, windowEnd))
    }
    return events.count
  }
  func setEventKitScopeEnabled(_ enabled: Bool) throws { lock.withLock { scopeEnabled = enabled } }
  func clearEventKitMirror() throws -> Int { lock.withLock { clearCount += 1 }; return 0 }
  func linkTaskToEventKitEvent(taskID: String, providerEventKey: String) throws
    -> TaskProviderEventLink
  {
    lock.withLock { links.append((taskID: taskID, key: providerEventKey)) }
    let now = SyncTimestamp.now()
    return TaskProviderEventLink(
      taskId: taskID, providerKind: ProviderKind.eventkit, providerScope: "device",
      providerEventKey: providerEventKey, createdAt: now, updatedAt: now)
  }
  func unlinkTaskFromEventKitEvent(taskID: String, providerEventKey: String) throws
    -> ProviderEventLinkDeleteResult
  {
    lock.withLock { links.removeAll { $0.taskID == taskID && $0.key == providerEventKey } }
    return ProviderEventLinkDeleteResult(deleted: true, before: nil, remainingLinks: [])
  }
  func eventKitLinksForTask(taskID: String) throws -> [ProviderEventLinkWithResolution] {
    if let eventKitLinksForTaskError {
      throw eventKitLinksForTaskError
    }
    let row = lock.withLock { links.first { $0.taskID == taskID } }
    guard let row else { return [] }
    let now = SyncTimestamp.now()
    return [
      ProviderEventLinkWithResolution(
        taskId: row.taskID, providerKind: ProviderKind.eventkit, providerScope: "device",
        providerEventKey: row.key, createdAt: now, updatedAt: now, eventTitle: nil,
        eventStartDate: nil, eventStartTime: nil, resolutionState: .resolved)
    ]
  }

  func recordedLinks() -> [(taskID: String, key: String)] { lock.withLock { links } }
}
