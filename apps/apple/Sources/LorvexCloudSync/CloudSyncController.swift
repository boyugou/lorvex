@preconcurrency import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync
import os

/// Where the CloudKit transport stands.
public enum CloudSyncControllerState: Equatable, Sendable {
  /// Not started, or stopped because sync was turned off.
  case stopped
  /// iCloud is not usable right now (signed out, restricted, or its status is
  /// unknown). Local data is untouched; an account change re-evaluates.
  case unavailable(CloudKitAccountAvailability)
  /// Waiting for the user: a different iCloud account, or Lorvex's iCloud data
  /// was deleted.
  case paused(CloudSyncPauseReason)
  /// Local sync state could not be read, so the transport refuses to run.
  case failed(String)
  /// The engine is running and syncing.
  case running
}

/// The `LorvexEntity` records of one outbox entity that went out in a batch.
///
/// Several unsynced rows can exist for one entity. Only the newest is sent;
/// once CloudKit holds it, every older row is superseded and confirmed with it.
struct CloudSyncOutboundGroup: Equatable {
  var envelope: SyncEnvelope
  var sentOutboxId: Int64
  var outboxIds: [Int64]

  init(_ item: PendingOutboundEnvelope) {
    envelope = item.envelope
    sentOutboxId = item.outboxId
    outboxIds = [item.outboxId]
  }

  mutating func absorb(_ item: PendingOutboundEnvelope) {
    outboxIds.append(item.outboxId)
    if item.envelope.version > envelope.version {
      envelope = item.envelope
      sentOutboxId = item.outboxId
    }
  }

  /// Every row except the one that carried the sent envelope.
  var supersededOutboxIds: [Int64] { outboxIds.filter { $0 != sentOutboxId } }
}

/// The CloudKit transport: one `CKSyncEngine` on the private database,
/// mirroring the local outbox into the `Lorvex` zone and applying fetched
/// records through Core's HLC merge.
///
/// Only the macOS and iOS main apps construct a controller. Everything else
/// writes through `LorvexCoreServicing`, whose mutations enqueue outbox rows;
/// the app calls ``noteLocalChanges()`` when its database changes so the
/// engine picks them up.
///
/// **Lifecycle.** ``start()`` checks the iCloud account, the durable pause
/// reason, and the account fingerprint the local data last synced with, and
/// creates the engine only when all three allow it. A different account pauses
/// with `accountChanged` until ``adoptCurrentAccount()``; deleted iCloud data
/// pauses with `userDeletedZone` until ``reenableAfterCloudDeletion()``. Local
/// data is never deleted by the transport.
///
/// **First upload.** The `zoneEstablished` checkpoint is absent until this
/// device has queued its whole database for the current zone, `"0"` once that
/// backfill is queued, and `"1"` once the zone is known to exist. A zone that
/// disappears while the checkpoint is `"1"` is a deletion, never a silent
/// re-upload.
///
/// **Engine state.** The engine's state serialization is persisted on every
/// `stateUpdate`. Fetched records are applied before the state that covers
/// them is delivered, so a crash between the two only refetches records the
/// HLC merge treats as replays. If an apply fails, no later state from that
/// engine is persisted and the engine is set aside; a new one is built from
/// the last persisted state on the next explicit sync or after a backoff, so
/// no fetched record is ever skipped.
///
/// **Account changes.** When the engine reports that the iCloud account
/// changed, it is set aside at once: none of its later callbacks can apply,
/// send, or persist anything, so no data crosses between accounts before the
/// account is checked again.
public actor CloudSyncController: CKSyncEngineDelegate {
  public static let zoneName = "Lorvex"
  /// The database subscription the engine creates for its pushes.
  public static let engineSubscriptionID = "lorvex-sync-engine"
  /// Zones of the retired generation-based transport. They are deleted when
  /// seen, since every device also holds their data locally.
  static let legacyZonePrefix = "LorvexGeneration-"
  /// Push subscriptions the retired transport registered. Server-side
  /// subscriptions outlive the app that created them, so they are deleted
  /// once per account instead of pushing on every change forever.
  static let legacySubscriptionIDs = [
    "lorvex-private-custom-zone-changes", "lorvex-generation-control-changes",
  ]
  static let maxBatchRecords = 200
  static let maxBatchBytes = 768 * 1024
  static let log = Logger(subsystem: "com.lorvex.apple", category: "cloudsync")

  let zoneID = CKRecordZone.ID(zoneName: CloudSyncController.zoneName, ownerName: CKCurrentUserDefaultName)
  private(set) var store: any CloudSyncEngineStore
  let accountChecker: any CloudKitAccountStatusChecking
  let accountIdentifier: any CloudKitAccountIdentifying
  let accountIdentityStore: any CloudSyncAccountIdentityStoring
  let pauseStore: any CloudSyncPauseStateStoring
  let systemFieldsStore: any CloudSyncRecordSystemFieldsStoring
  let makeEngine: CloudSyncEngineFactory

  public internal(set) var state: CloudSyncControllerState = .stopped
  var engine: (any CloudSyncEngineDriving)?
  /// The account fingerprint the running engine syncs with.
  var accountID: String?
  var inFlight: [String: CloudSyncOutboundGroup] = [:]
  var inboundApplyFailed = false
  var isDeletingCloudData = false
  var cloudDeletionConfirmed = false
  var explicitSyncs = 0
  /// The engine was set aside after a failed apply and must be rebuilt from
  /// the last persisted state before the next sync.
  var needsEngineRebuild = false
  /// Consecutive rebuilds after failed applies, for the retry backoff.
  var engineRebuildAttempts = 0
  var pendingReport = CloudSyncCycleReport.empty
  var reportHandler: (@Sendable (CloudSyncCycleReport) async -> Void)?
  private var evaluation: Task<CloudSyncControllerState, Never>?
  /// Advanced by ``stop()`` and by every path that pauses sync or resets the
  /// zone. An evaluation that started under an older value was superseded
  /// while it awaited the network, and must not start the engine or publish a
  /// state.
  private(set) var lifecycleGeneration: UInt64 = 0

  public init(
    store: any CloudSyncEngineStore,
    accountChecker: any CloudKitAccountStatusChecking,
    accountIdentifier: any CloudKitAccountIdentifying,
    accountIdentityStore: any CloudSyncAccountIdentityStoring,
    pauseStore: any CloudSyncPauseStateStoring,
    systemFieldsStore: any CloudSyncRecordSystemFieldsStoring,
    makeEngine: @escaping CloudSyncEngineFactory
  ) {
    self.store = store
    self.accountChecker = accountChecker
    self.accountIdentifier = accountIdentifier
    self.accountIdentityStore = accountIdentityStore
    self.pauseStore = pauseStore
    self.systemFieldsStore = systemFieldsStore
    self.makeEngine = makeEngine
  }

  /// Receives a report after every fetch or send the engine runs on its own
  /// (a push notification, the system scheduler, a retry). Reports of
  /// ``syncNow()`` are returned to its caller instead.
  public func setReportHandler(_ handler: @escaping @Sendable (CloudSyncCycleReport) async -> Void) {
    reportHandler = handler
  }

  // MARK: - Lifecycle

  /// Evaluates the account and pause state and starts the engine when both
  /// allow it. Concurrent calls share one evaluation.
  @discardableResult
  public func start() async -> CloudSyncControllerState {
    if let evaluation { return await evaluation.value }
    let generation = lifecycleGeneration
    let task = Task { await self.evaluate(generation: generation) }
    evaluation = task
    let result = await task.value
    if lifecycleGeneration == generation { evaluation = nil }
    return result
  }

  /// Stops syncing (sync turned off). Local data, the outbox, and the persisted
  /// engine state stay, so turning sync back on resumes where it left off. An
  /// evaluation still awaiting the network is superseded and returns
  /// `.stopped` without starting the engine.
  public func stop() async {
    supersedeEvaluation()
    needsEngineRebuild = false
    await tearDownEngine()
    state = .stopped
  }

  /// Points the transport at a new local store after the database was
  /// replaced (a factory reset). Sync stops first; the caller starts it again
  /// if it should run.
  public func replaceStore(_ store: any CloudSyncEngineStore) async {
    await stop()
    self.store = store
  }

  /// Invalidates any evaluation still awaiting the network, so it cannot start
  /// an engine over a state that changed under it.
  func supersedeEvaluation() {
    lifecycleGeneration &+= 1
    evaluation = nil
  }

  /// Forgets the cached CloudKit record versions after the local database was
  /// erased. The erased database took the engine state and zone checkpoints
  /// with it, so the next start fetches the whole zone from scratch. Call only
  /// while stopped.
  public func forgetCachedRecordState() async {
    await systemFieldsStore.removeAll()
    inFlight = [:]
  }

  /// Re-evaluates after `CKAccountChanged`. A running engine is set aside
  /// first, so nothing crosses between accounts while the account is checked.
  @discardableResult
  public func handleAccountChange() async -> CloudSyncControllerState {
    if state == .running {
      supersedeEvaluation()
      await tearDownEngine()
      state = .stopped
    }
    return await start()
  }

  public func accountAvailability() async -> CloudKitAccountAvailability {
    (try? await accountChecker.checkAccountStatus()) ?? .couldNotDetermine
  }

  public func currentPauseReason() async -> CloudSyncPauseReason? {
    try? await pauseStore.loadPauseReason()
  }

  /// Syncs with the account now signed in after an `accountChanged` pause:
  /// the local database is uploaded into that account and merged with what it
  /// already holds.
  @discardableResult
  public func adoptCurrentAccount() async throws -> CloudSyncControllerState {
    guard let current = await accountIdentifier.currentAccountIdentifier() else {
      return await start()
    }
    supersedeEvaluation()
    await tearDownEngine()
    try await resetZoneState()
    try await accountIdentityStore.saveLastAccountIdentifier(current)
    try await pauseStore.clearPauseReason()
    return await start()
  }

  /// Turns sync back on after Lorvex's iCloud data was deleted: the local
  /// database is uploaded into a new zone.
  @discardableResult
  public func reenableAfterCloudDeletion() async throws -> CloudSyncControllerState {
    supersedeEvaluation()
    await tearDownEngine()
    try await resetZoneState()
    try await pauseStore.clearPauseReason()
    return await start()
  }

  private func evaluate(generation: UInt64) async -> CloudSyncControllerState {
    // An engine borrowed to delete iCloud data must not be adopted as the sync
    // engine; the deletion settles the state when it finishes.
    guard !isDeletingCloudData else { return state }
    let availability: CloudKitAccountAvailability
    do {
      availability = try await accountChecker.checkAccountStatus()
    } catch {
      availability = .couldNotDetermine
    }
    let current =
      availability == .available ? await accountIdentifier.currentAccountIdentifier() : nil
    guard generation == lifecycleGeneration else { return .stopped }
    guard availability == .available, let current else {
      await tearDownEngine()
      state = .unavailable(availability == .available ? .couldNotDetermine : availability)
      return state
    }
    do {
      let stored = try await accountIdentityStore.loadLastAccountIdentifier()
      let pauseReason = try await pauseStore.loadPauseReason()
      guard generation == lifecycleGeneration else { return .stopped }
      switch pauseReason {
      case .userDeletedZone:
        await tearDownEngine()
        state = .paused(.userDeletedZone)
        return state
      case .accountChanged where stored != current:
        await tearDownEngine()
        state = .paused(.accountChanged)
        return state
      case .accountChanged:
        // Back on the bound account: the pause no longer applies.
        try await pauseStore.clearPauseReason()
      case nil:
        break
      }
      if let stored, stored != current {
        try await pauseStore.savePauseReason(.accountChanged)
        await tearDownEngine()
        state = .paused(.accountChanged)
        return state
      }
      if stored == nil {
        try await accountIdentityStore.saveLastAccountIdentifier(current)
      }
      guard generation == lifecycleGeneration else { return .stopped }
      accountID = current
      if engine == nil { try startEngine() }
    } catch {
      guard generation == lifecycleGeneration else { return .stopped }
      await tearDownEngine()
      state = .failed(String(describing: error))
      return state
    }
    state = .running
    await noteLocalChanges()
    await cleanUpLegacyTransportIfNeeded()
    return state
  }

  /// Removes the retired transport's push subscriptions and zones from the
  /// current account, once. A failure leaves the checkpoint unset so the next
  /// start tries again.
  func cleanUpLegacyTransportIfNeeded() async {
    guard let engine, state == .running,
      (try? store.cloudSyncEngineCheckpoint(.legacyCleanup)) != "1"
    else { return }
    do {
      try await engine.deleteSubscriptions(Self.legacySubscriptionIDs)
      let legacyZones = try await engine.allZoneIDs().filter {
        $0.zoneName.hasPrefix(Self.legacyZonePrefix)
      }
      if !legacyZones.isEmpty {
        engine.add(pendingDatabaseChanges: legacyZones.map { .deleteZone($0) })
      }
      try store.setCloudSyncEngineCheckpoint(.legacyCleanup, value: "1")
    } catch {
      Self.log.error("Removing the retired transport failed: \(String(describing: error), privacy: .public)")
    }
  }

  private func startEngine() throws {
    let checkpoint = try store.cloudSyncEngineCheckpoint(.zoneEstablished)
    if checkpoint == nil {
      try store.enqueueFullResyncBackfill()
      try store.setCloudSyncEngineCheckpoint(.zoneEstablished, value: "0")
    } else {
      try reseedIfRequired()
    }
    try discardEngineStateIfRefetchRequired()
    let persisted = try store.cloudSyncEngineCheckpoint(.engineState)
      .flatMap { Data(base64Encoded: $0) }
    inboundApplyFailed = false
    needsEngineRebuild = false
    inFlight = [:]
    let engine = makeEngine(persisted, true, self)
    self.engine = engine
    if checkpoint != "1" { ensureZoneSaveQueued(on: engine) }
  }

  /// Queues the whole database again when Core flagged that outbox rows were
  /// lost (dropped at the outbox cap, or skipped by an earlier backfill). The
  /// backfill clears the flag once it re-queued every row.
  func reseedIfRequired() throws {
    guard try store.cloudSyncEngineCheckpoint(.reseedRequired) == "true" else { return }
    try store.enqueueFullResyncBackfill()
  }

  /// Whether Core recorded that it dropped inbound records the zone still
  /// holds. An incremental fetch never delivers an unchanged record again, so
  /// only an engine built without saved state can fetch them.
  func isRefetchRequired() throws -> Bool {
    try store.cloudSyncEngineCheckpoint(.refetchRequired) == "true"
  }

  /// Discards the saved engine state when a refetch is required, so the next
  /// engine fetches the whole zone, and clears the one-shot request. The state
  /// goes first: a crash in between only repeats the discard.
  func discardEngineStateIfRefetchRequired() throws {
    guard try isRefetchRequired() else { return }
    try store.setCloudSyncEngineCheckpoint(.engineState, value: nil)
    try store.setCloudSyncEngineCheckpoint(.refetchRequired, value: nil)
  }

  /// Takes the engine out of service. Nothing it reports afterwards is acted
  /// on, since every callback checks that it comes from the current engine.
  /// Inside one of that engine's own callbacks, pass `waitForCancellation:
  /// false`: the cancellation then runs outside the callback, which the engine
  /// may be waiting on.
  func tearDownEngine(waitForCancellation: Bool = true) async {
    guard let engine else { return }
    self.engine = nil
    inFlight = [:]
    if waitForCancellation {
      await engine.cancelOperations()
    } else {
      Task.detached { await engine.cancelOperations() }
    }
  }

  /// Forget everything tied to the current zone, so the next engine starts
  /// from scratch and this device uploads its whole database again.
  func resetZoneState() async throws {
    try store.setCloudSyncEngineCheckpoint(.engineState, value: nil)
    try store.setCloudSyncEngineCheckpoint(.zoneEstablished, value: nil)
    try store.setCloudSyncEngineCheckpoint(.legacyCleanup, value: nil)
    await systemFieldsStore.removeAll()
    inFlight = [:]
  }

  /// After an apply failure: set the engine aside, so it stops fetching
  /// batches that cannot be applied, and rebuild it from the last persisted
  /// state on the next explicit sync or after a backoff that doubles with
  /// every consecutive failure, from 30 seconds up to 10 minutes.
  func setEngineAsideAfterInboundFailure() async {
    guard inboundApplyFailed, state == .running, engine != nil else { return }
    await tearDownEngine(waitForCancellation: false)
    needsEngineRebuild = true
    let delay = min(30 * pow(2, Double(engineRebuildAttempts)), 600)
    engineRebuildAttempts += 1
    let generation = lifecycleGeneration
    Task {
      try? await Task.sleep(for: .seconds(delay))
      await self.rebuildEngineIfNeeded(generation: generation)
    }
  }

  /// Rebuilds an engine set aside after a failed apply, unless sync stopped
  /// or paused since, or `generation` was superseded. The rebuilt engine
  /// resumes from state saved before the failure, so every record with outbox
  /// work is added to it again.
  func rebuildEngineIfNeeded(generation: UInt64? = nil) async {
    guard needsEngineRebuild, state == .running, engine == nil else { return }
    if let generation, generation != lifecycleGeneration { return }
    do {
      try startEngine()
    } catch {
      state = .failed(String(describing: error))
      return
    }
    await noteLocalChanges()
  }

  /// The engine's account changed under it. It is set aside before anything
  /// else runs, then the account is evaluated again, which resumes, pauses, or
  /// reports iCloud unavailable. An engine borrowed to delete iCloud data
  /// while sync is off is only set aside.
  ///
  /// A sign-in is the exception: an engine started without saved state reports
  /// the signed-in account as a sign-in, so a sign-in to the account sync is
  /// already bound to, or one arriving while iCloud data is being deleted,
  /// keeps the engine. Tearing it down would start a replacement that again
  /// has no saved state and reports the same sign-in.
  func handleEngineAccountChange(isSignIn: Bool = false) async {
    if isSignIn {
      if isDeletingCloudData { return }
      if state == .running, let accountID,
        await accountIdentifier.currentAccountIdentifier() == accountID
      {
        return
      }
    }
    let wasRunning = state == .running
    await tearDownEngine(waitForCancellation: false)
    guard wasRunning else { return }
    supersedeEvaluation()
    state = .stopped
    let generation = lifecycleGeneration
    Task {
      guard self.lifecycleGeneration == generation else { return }
      await self.start()
    }
  }

  // MARK: - Local changes and explicit sync

  /// Adds a pending save for every record name with outbox work, so the
  /// engine sends it. Call whenever the local database changes.
  public func noteLocalChanges() async {
    guard let engine, state == .running, !isDeletingCloudData else { return }
    let names: Set<String>
    do {
      names = try store.unsyncedOutboundRecordNames()
    } catch {
      Self.log.error("Reading the outbox failed: \(String(describing: error), privacy: .public)")
      return
    }
    guard !names.isEmpty else { return }
    if (try? store.cloudSyncEngineCheckpoint(.zoneEstablished)) != "1" {
      ensureZoneSaveQueued(on: engine)
    }
    engine.add(pendingRecordZoneChanges: names.map { .saveRecord(recordID($0)) })
  }

  /// Fetches, then sends, and returns what that pass did. Returns nil when
  /// the transport is not running.
  ///
  /// A failed fetch does not skip the send: local changes still go out, and
  /// the fetch error is thrown afterwards. A failed apply does skip it, since
  /// the engine is being rebuilt.
  public func syncNow() async throws -> CloudSyncCycleReport? {
    guard state == .running else { return nil }
    if engine == nil { await rebuildEngineIfNeeded() }
    if engine != nil, (try? isRefetchRequired()) == true {
      // The running engine resumes from its saved state; replace it with one
      // that fetches the whole zone.
      await tearDownEngine()
      guard state == .running else { return nil }
      do {
        try startEngine()
      } catch {
        state = .failed(String(describing: error))
      }
    }
    guard state == .running, let engine else { return nil }
    try? reseedIfRequired()
    await noteLocalChanges()
    explicitSyncs += 1
    defer { explicitSyncs -= 1 }
    do {
      var fetchError: (any Error)?
      do {
        try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
      } catch {
        fetchError = error
      }
      if inboundApplyFailed {
        await setEngineAsideAfterInboundFailure()
        throw CloudSyncInboundApplyFailure()
      }
      try await engine.sendChanges(.init())
      if let fetchError { throw fetchError }
    } catch {
      publish(takePendingReport())
      throw error
    }
    return takePendingReport()
  }

  // MARK: - Deleting iCloud data

  /// Deletes Lorvex's zone, and any zone left by the retired transport, from
  /// the user's private database. Afterwards sync is paused with
  /// `userDeletedZone` on this and every other device until the user turns it
  /// back on. Local data is kept.
  public func deleteAllCloudData() async throws {
    let engine: any CloudSyncEngineDriving
    let borrowedEngine = self.engine == nil
    if let running = self.engine {
      engine = running
    } else {
      // Sync is off or paused: run the deletion on a temporary engine that
      // syncs nothing on its own, and take it down again if the deletion
      // fails.
      let persisted = try store.cloudSyncEngineCheckpoint(.engineState)
        .flatMap { Data(base64Encoded: $0) }
      engine = makeEngine(persisted, false, self)
      self.engine = engine
    }
    isDeletingCloudData = true
    cloudDeletionConfirmed = false
    defer { isDeletingCloudData = false }
    do {
      let zones = try await engine.allZoneIDs().filter {
        $0 == zoneID || $0.zoneName.hasPrefix(Self.legacyZonePrefix)
      }
      if zones.contains(zoneID) {
        engine.add(pendingDatabaseChanges: zones.map { .deleteZone($0) })
        try await engine.sendChanges(.init())
        guard cloudDeletionConfirmed else { throw CloudSyncCloudDeletionIncomplete() }
      } else if !zones.isEmpty {
        engine.add(pendingDatabaseChanges: zones.map { .deleteZone($0) })
        try await engine.sendChanges(.init())
      }
    } catch {
      if borrowedEngine { await tearDownEngine() }
      throw error
    }
    try await enterUserDeletedZonePause()
  }

  func enterUserDeletedZonePause(waitForCancellation: Bool = true) async throws {
    supersedeEvaluation()
    needsEngineRebuild = false
    await tearDownEngine(waitForCancellation: waitForCancellation)
    try await resetZoneState()
    try await pauseStore.savePauseReason(.userDeletedZone)
    state = .paused(.userDeletedZone)
  }

  // MARK: - Helpers

  func recordID(_ recordName: String) -> CKRecord.ID {
    CKRecord.ID(recordName: recordName, zoneID: zoneID)
  }

  func ensureZoneSaveQueued(on engine: any CloudSyncEngineDriving) {
    let queued = engine.pendingDatabaseChanges.contains {
      if case .saveZone(let zone) = $0 { return zone.zoneID == zoneID }
      return false
    }
    if !queued { engine.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))]) }
  }

  func markZoneEstablished() {
    guard (try? store.cloudSyncEngineCheckpoint(.zoneEstablished)) != "1" else { return }
    try? store.setCloudSyncEngineCheckpoint(.zoneEstablished, value: "1")
  }

  func takePendingReport() -> CloudSyncCycleReport {
    let report = pendingReport
    pendingReport = .empty
    return report
  }

  func publish(_ report: CloudSyncCycleReport) {
    guard report != .empty, let reportHandler else { return }
    Task { await reportHandler(report) }
  }
}

/// A fetched batch could not be applied (for example because iOS suspended the
/// database). The engine is rebuilt from its last persisted state and fetches
/// the batch again.
public struct CloudSyncInboundApplyFailure: Error, Equatable {}

/// CloudKit did not confirm that Lorvex's zone was deleted.
public struct CloudSyncCloudDeletionIncomplete: Error, Equatable {}

extension CloudSyncController {
  /// Test hook: simulate a fetched batch whose apply threw.
  func markInboundApplyFailedForTesting() {
    inboundApplyFailed = true
  }
}
