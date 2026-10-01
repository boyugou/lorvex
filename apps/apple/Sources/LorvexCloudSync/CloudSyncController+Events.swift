@preconcurrency import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync

/// `CKSyncEngineDelegate`: translate engine events into the controller's
/// handlers. Events from an engine the controller already replaced are
/// ignored, so a torn-down engine can never persist state or apply records.
extension CloudSyncController {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard let engine, engine.wraps(syncEngine) else { return }
    switch event {
    case .stateUpdate(let update):
      handleStateUpdate(try? JSONEncoder().encode(update.stateSerialization))
    case .accountChange(let change):
      let isSignIn: Bool
      if case .signIn = change.changeType { isSignIn = true } else { isSignIn = false }
      await handleEngineAccountChange(isSignIn: isSignIn)
    case .fetchedDatabaseChanges(let changes):
      await handleFetchedDatabaseChanges(
        modifiedZoneIDs: changes.modifications.map(\.zoneID),
        deletions: changes.deletions.map { ($0.zoneID, $0.reason) })
    case .fetchedRecordZoneChanges(let changes):
      await handleFetchedRecords(changes.modifications.map(\.record))
    case .sentDatabaseChanges(let sent):
      await handleSentDatabaseChanges(
        savedZoneIDs: sent.savedZones.map(\.zoneID),
        failedZoneSaves: sent.failedZoneSaves.map { ($0.zone.zoneID, $0.error) },
        deletedZoneIDs: sent.deletedZoneIDs,
        failedZoneDeletes: sent.failedZoneDeletes)
    case .sentRecordZoneChanges(let sent):
      await handleSentRecords(
        saved: sent.savedRecords,
        failed: sent.failedRecordSaves.map { ($0.record, $0.error) })
    case .didFetchChanges:
      handleDidFetchChanges()
    case .didSendChanges:
      if explicitSyncs == 0 { publish(takePendingReport()) }
    case .didFetchRecordZoneChanges(let fetched):
      await handleDidFetchRecordZoneChanges(zoneID: fetched.zoneID, error: fetched.error)
    case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges:
      break
    @unknown default:
      break
    }
  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    guard let engine, engine.wraps(syncEngine), acceptsSyncTraffic else { return nil }
    let records = await nextBatch(scope: context.options.scope)
    guard !records.isEmpty else { return nil }
    return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records)
  }

  /// Only Lorvex's zone is ever fetched; zones of the retired transport are
  /// deleted, not downloaded.
  public func nextFetchChangesOptions(
    _ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.FetchChangesOptions {
    var options = context.options
    options.scope = .zoneIDs([zoneID])
    return options
  }

  // MARK: - State

  /// Whether the current engine may apply, send, or persist anything: only
  /// while sync runs. An engine borrowed to delete iCloud data while sync is
  /// off or paused only deletes.
  var acceptsSyncTraffic: Bool {
    state == .running && !isDeletingCloudData
  }

  func handleStateUpdate(_ serialization: Data?) {
    guard acceptsSyncTraffic, !inboundApplyFailed, let serialization else { return }
    do {
      try store.setCloudSyncEngineCheckpoint(
        .engineState, value: serialization.base64EncodedString())
    } catch {
      Self.log.error("Persisting engine state failed: \(String(describing: error), privacy: .public)")
    }
  }

  func handleDidFetchChanges() {
    if inboundApplyFailed {
      Task { await self.setEngineAsideAfterInboundFailure() }
    } else if acceptsSyncTraffic {
      engineRebuildAttempts = 0
    }
    if explicitSyncs == 0 { publish(takePendingReport()) }
  }

  // MARK: - Database changes

  func handleFetchedDatabaseChanges(
    modifiedZoneIDs: [CKRecordZone.ID],
    deletions: [(CKRecordZone.ID, CKDatabase.DatabaseChange.Deletion.Reason)]
  ) async {
    if modifiedZoneIDs.contains(zoneID) { markZoneEstablished() }
    let legacy = modifiedZoneIDs.filter { $0.zoneName.hasPrefix(Self.legacyZonePrefix) }
    if !legacy.isEmpty { engine?.add(pendingDatabaseChanges: legacy.map { .deleteZone($0) }) }
    guard let deletion = deletions.first(where: { $0.0 == zoneID }), !isDeletingCloudData else {
      return
    }
    await handleZoneGone(encryptedDataReset: deletion.1 == .encryptedDataReset)
  }

  /// A zone fetch reported that Lorvex's established zone no longer exists:
  /// it was deleted from another device or from iCloud settings. A device that
  /// only reads would otherwise learn this only at its next save.
  func handleDidFetchRecordZoneChanges(zoneID fetchedZoneID: CKRecordZone.ID, error: CKError?)
    async
  {
    guard fetchedZoneID == zoneID, let error, !isDeletingCloudData, acceptsSyncTraffic,
      error.code == .zoneNotFound || error.code == .userDeletedZone,
      (try? store.cloudSyncEngineCheckpoint(.zoneEstablished)) == "1"
    else { return }
    await handleZoneGone(encryptedDataReset: false)
  }

  func handleSentDatabaseChanges(
    savedZoneIDs: [CKRecordZone.ID],
    failedZoneSaves: [(CKRecordZone.ID, CKError)],
    deletedZoneIDs: [CKRecordZone.ID],
    failedZoneDeletes: [CKRecordZone.ID: CKError]
  ) async {
    if savedZoneIDs.contains(zoneID) { markZoneEstablished() }
    if deletedZoneIDs.contains(zoneID) || failedZoneDeletes[zoneID]?.code == .zoneNotFound {
      cloudDeletionConfirmed = true
    }
    for (zone, error) in failedZoneSaves where zone == zoneID {
      Self.log.error("Creating the Lorvex zone failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Lorvex's zone is gone. A key reset lost the data, so it is uploaded
  /// again at once; any other deletion was the user's choice and pauses sync
  /// until they turn it back on.
  func handleZoneGone(encryptedDataReset: Bool) async {
    if encryptedDataReset {
      supersedeEvaluation()
      await tearDownEngine(waitForCancellation: false)
      do {
        try await resetZoneState()
      } catch {
        state = .failed(String(describing: error))
        return
      }
      Task { await self.start() }
    } else {
      do {
        try await enterUserDeletedZonePause(waitForCancellation: false)
      } catch {
        state = .failed(String(describing: error))
      }
    }
  }

  // MARK: - Inbound records

  /// Applies one fetched batch in a single Core transaction, then caches the
  /// batch's system fields so the next local edit of those records saves
  /// against the current server version. A failed apply sets
  /// `inboundApplyFailed`: no later engine state is persisted, and the engine
  /// is rebuilt from the last persisted state so the batch is fetched again.
  func handleFetchedRecords(_ records: [CKRecord]) async {
    guard acceptsSyncTraffic, !inboundApplyFailed else { return }
    var envelopes: [SyncEnvelope] = []
    var raws: [RawEnvelopeFields] = []
    var undecodable = 0
    var fetched = 0
    for record in records where record.recordID.zoneID == zoneID {
      fetched += 1
      switch CloudSyncEnvelopeRecord.decode(record) {
      case .decoded(let envelope):
        if envelope.entityType != .aiChangelog { envelopes.append(envelope) }
      case .unknownEntityType(let raw):
        if raw.entityType != EntityName.aiChangelog { raws.append(raw) }
      case .corrupt:
        undecodable += 1
      case .foreign:
        break
      }
    }
    guard fetched > 0 else { return }
    markZoneEstablished()
    pendingReport.fetchedRecordCount += fetched
    guard !envelopes.isEmpty || !raws.isEmpty || undecodable > 0 else { return }
    do {
      let report = try store.applyFetchedRecords(envelopes, parking: raws, undecodable: undecodable)
      pendingReport.inbound.merge(report)
      if let accountID {
        await cacheSystemFields(of: records, accountID: accountID)
      }
    } catch {
      inboundApplyFailed = true
      Self.log.error("Applying fetched records failed: \(String(describing: error), privacy: .public)")
      // Set the engine aside now rather than waiting for `.didFetchChanges`,
      // which a cancelled or failed fetch may never deliver.
      Task { await self.setEngineAsideAfterInboundFailure() }
    }
  }
}

extension InboundApplyReport {
  mutating func merge(_ other: InboundApplyReport) {
    applied += other.applied
    skipped += other.skipped
    deferred += other.deferred
    remapped += other.remapped
    drainReplayed += other.drainReplayed
    undecodable += other.undecodable
    deferredUnknownType += other.deferredUnknownType
    appliedEntityTypes.formUnion(other.appliedEntityTypes)
    reconciledCollisionOutboxIds.formUnion(other.reconciledCollisionOutboxIds)
  }
}
