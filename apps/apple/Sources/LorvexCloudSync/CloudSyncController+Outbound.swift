@preconcurrency import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync

/// Outbound: build record batches from the outbox and commit what CloudKit
/// did with them.
extension CloudSyncController {
  /// The next records to save: the newest envelope of each outbox entity whose
  /// record name the engine has pending, up to the batch limits.
  ///
  /// Only pending record names are sent. A record that failed permanently is
  /// removed from the engine's pending set and is not re-added, so one send
  /// pass cannot retry it in a loop; it is re-added when the local database
  /// next changes or the app next syncs, subject to the outbox retry policy.
  /// Device-local `ai_changelog` rows found on the way are confirmed without
  /// being sent, and pending names that no longer have outbox work are
  /// dropped from the engine.
  func nextBatch(scope: CKSyncEngine.SendChangesOptions.Scope) async -> [CKRecord] {
    guard state == .running, !isDeletingCloudData, let engine, let accountID else { return [] }
    var pendingNames = Set<String>()
    for change in engine.pendingRecordZoneChanges where scope.contains(change) {
      if case .saveRecord(let id) = change, id.zoneID == zoneID {
        pendingNames.insert(id.recordName)
      }
    }
    guard !pendingNames.isEmpty else { return [] }

    var groups: [String: CloudSyncOutboundGroup] = [:]
    var order: [String] = []
    var bytes = 0
    var localOnly: [Int64] = []
    var cursor: Int64?
    var scannedEverything = false
    let now = SyncTimestampFormat.syncTimestampNow()
    scan: while true {
      let page: PendingOutboundPage
      do {
        page = try store.pendingOutboundPage(afterOutboxId: cursor, now: now)
      } catch {
        Self.log.error("Reading the outbox failed: \(String(describing: error), privacy: .public)")
        break
      }
      for item in page.envelopes {
        if item.envelope.entityType == .aiChangelog {
          localOnly.append(item.outboxId)
          continue
        }
        let name = SyncRecordName.opaque(
          entityType: item.envelope.entityType.asString, entityId: item.envelope.entityId)
        guard pendingNames.contains(name) else { continue }
        if groups[name] != nil {
          groups[name]?.absorb(item)
          continue
        }
        if order.count >= Self.maxBatchRecords || bytes >= Self.maxBatchBytes { break scan }
        groups[name] = CloudSyncOutboundGroup(item)
        order.append(name)
        bytes += item.envelope.payload.utf8.count + 512
      }
      guard let last = page.lastScannedOutboxId else {
        scannedEverything = true
        break
      }
      cursor = last
    }

    if !localOnly.isEmpty {
      _ = try? store.reconcileOutbound(OutboundReconciliationRequest(confirmedOutboxIds: localOnly))
    }
    if scannedEverything {
      let unsynced = (try? store.unsyncedOutboundRecordNames()) ?? pendingNames
      let stale = pendingNames.subtracting(groups.keys).subtracting(unsynced)
      if !stale.isEmpty {
        engine.remove(pendingRecordZoneChanges: stale.map { .saveRecord(recordID($0)) })
      }
    }

    var records: [CKRecord] = []
    records.reserveCapacity(order.count)
    for name in order {
      guard let group = groups[name] else { continue }
      records.append(await record(for: group.envelope, accountID: accountID))
      inFlight[name] = group
    }
    return records
  }

  /// A `LorvexEntity` record for `envelope`, built on the cached system fields
  /// when there are any so an unchanged server record saves without a conflict.
  func record(for envelope: SyncEnvelope, accountID: String) async -> CKRecord {
    let fresh = CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: zoneID)
    guard
      let data = await systemFieldsStore.systemFields(
        accountIdentifier: accountID, zoneName: zoneID.zoneName,
        recordName: fresh.recordID.recordName),
      let base = CloudSyncSystemFields.restore(data, expecting: fresh.recordID)
    else { return fresh }
    CloudSyncEnvelopeRecord.restamp(from: fresh, onto: base)
    return base
  }

  /// Commit one sent batch in a single `reconcileOutbound` transaction, then
  /// cache the system fields the commit made current and re-queue the records
  /// that must go out again.
  ///
  /// A record saved, or whose conflict resolved to the server's version, while
  /// an older outbox row was in flight is sent again when a newer local edit
  /// of it is still unsynced after the commit. If the
  /// engine is replaced while this runs (an account change, a stop), the batch
  /// is not committed: its rows stay unsynced and go out on the next engine.
  func handleSentRecords(saved: [CKRecord], failed: [(CKRecord, CKError)]) async {
    guard acceptsSyncTraffic, let accountID, let sendingEngine = engine else { return }
    func engineUnchanged() -> Bool {
      engine.map { ObjectIdentifier($0) == ObjectIdentifier(sendingEngine) } ?? false
    }
    var request = OutboundReconciliationRequest()
    var cacheAfterCommit: [CKRecord] = []
    var collisionServerRecords: [Int64: CKRecord] = [:]
    var collisionNames: [Int64: String] = [:]
    var cacheNow: [CKRecord] = []
    var forget = Set<String>()
    var requeue = Set<String>()
    var resolvedFailureNames = Set<String>()
    var zoneMissing = false
    var storageFull = false
    var pushed = 0

    for record in saved where record.recordID.zoneID == zoneID {
      let name = record.recordID.recordName
      cacheAfterCommit.append(record)
      guard let group = inFlight.removeValue(forKey: name) else { continue }
      if CloudSyncEnvelopeRecord.versionString(from: record) == group.envelope.version.description {
        request.confirmedOutboxIds += group.outboxIds
        pushed += 1
      }
    }

    for (record, error) in failed where record.recordID.zoneID == zoneID {
      let name = record.recordID.recordName
      let group = inFlight.removeValue(forKey: name)
      switch error.code {
      case .serverRecordChanged:
        guard let group, let server = error.serverRecord else {
          requeue.insert(name)
          continue
        }
        let client = error.clientRecord ?? record
        switch CloudSyncConflictClassifier.classify(client: client, server: server) {
        case .confirm:
          request.confirmedOutboxIds += group.outboxIds
          cacheAfterCommit.append(server)
          resolvedFailureNames.insert(name)
        case .applyServer(let envelope):
          request.serverWinnerEnvelopes.append(envelope)
          request.confirmedOutboxIds += group.outboxIds
          cacheAfterCommit.append(server)
          resolvedFailureNames.insert(name)
        case .resave:
          cacheNow.append(server)
          requeue.insert(name)
        case .collision(let kind):
          request.collisions.append(OutboundCollisionRecord(outboxId: group.sentOutboxId, kind: kind))
          request.confirmedOutboxIds += group.supersededOutboxIds
          collisionServerRecords[group.sentOutboxId] = server
          collisionNames[group.sentOutboxId] = name
        case .park(let raw):
          request.deferredUnknownTypeRecords.append(raw)
          request.failures += group.outboxIds.map {
            OutboundFailureRecord(
              outboxId: $0, error: "waiting for a build that understands a newer server record",
              kind: .transient)
          }
        case .fail(let message):
          request.failures += group.outboxIds.map {
            OutboundFailureRecord(outboxId: $0, error: message, kind: .perRecord)
          }
        }
      case .zoneNotFound, .userDeletedZone:
        if (try? store.cloudSyncEngineCheckpoint(.zoneEstablished)) == "1"
          || error.code == .userDeletedZone
        {
          zoneMissing = true
        } else {
          forget.insert(name)
          requeue.insert(name)
        }
      case .unknownItem:
        forget.insert(name)
        requeue.insert(name)
      case .quotaExceeded:
        storageFull = true
      case .batchRequestFailed, .limitExceeded:
        requeue.insert(name)
      case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
        .requestRateLimited, .notAuthenticated, .operationCancelled,
        .accountTemporarilyUnavailable:
        // The engine keeps these pending and retries them itself.
        break
      default:
        if let group {
          request.failures += group.outboxIds.map {
            OutboundFailureRecord(outboxId: $0, error: error.localizedDescription, kind: .perRecord)
          }
        }
      }
    }

    if zoneMissing, !isDeletingCloudData {
      await handleZoneGone(encryptedDataReset: false)
      return
    }

    if !cacheNow.isEmpty { await cacheSystemFields(of: cacheNow, accountID: accountID) }
    if !forget.isEmpty {
      await systemFieldsStore.remove(
        recordNames: forget, accountIdentifier: accountID, zoneName: zoneID.zoneName)
    }
    guard engineUnchanged(), acceptsSyncTraffic else { return }

    if request != OutboundReconciliationRequest() {
      do {
        let report = try store.reconcileOutbound(request)
        pendingReport.inbound.merge(report.inbound)
        // A reconciled collision queued a successor row, sent against the
        // server's system fields. One Core could not reconcile, or held for a
        // server record it cannot apply yet, waits for the retry policy like
        // any other failed save.
        for (outboxId, server) in collisionServerRecords
        where report.reconciledCollisionOutboxIds.contains(outboxId) {
          cacheAfterCommit.append(server)
          if let name = collisionNames[outboxId] { requeue.insert(name) }
        }
        pendingReport.pushedRecordCount += pushed
        pendingReport.failedPushCount += request.failures.count
        // A record saved, or whose failure resolved to the server's version,
        // while a newer local edit of it was queued still has outbox work.
        let settledNames = Set(saved.map(\.recordID.recordName)).union(resolvedFailureNames)
        if let unsynced = try? store.unsyncedOutboundRecordNames() {
          requeue.formUnion(settledNames.intersection(unsynced))
        }
      } catch {
        // Nothing committed: every row is still unsynced. Send them again.
        Self.log.error("Reconciling a sent batch failed: \(String(describing: error), privacy: .public)")
        requeue.formUnion(saved.map(\.recordID.recordName))
        requeue.formUnion(failed.map(\.0.recordID.recordName))
        requeue.formUnion(collisionNames.values)
        cacheAfterCommit = saved
      }
    }
    if !cacheAfterCommit.isEmpty { await cacheSystemFields(of: cacheAfterCommit, accountID: accountID) }
    if storageFull { pendingReport.iCloudStorageFull = true }
    if !requeue.isEmpty, engineUnchanged(), let engine {
      if !forget.isEmpty, (try? store.cloudSyncEngineCheckpoint(.zoneEstablished)) != "1" {
        ensureZoneSaveQueued(on: engine)
      }
      engine.add(pendingRecordZoneChanges: requeue.map { .saveRecord(recordID($0)) })
    }
  }

  func cacheSystemFields(of records: [CKRecord], accountID: String) async {
    var entries: [String: Data] = [:]
    for record in records where record.recordID.zoneID == zoneID {
      entries[record.recordID.recordName] = CloudSyncSystemFields.archive(record)
    }
    await systemFieldsStore.storeAll(
      entries, accountIdentifier: accountID, zoneName: zoneID.zoneName)
  }
}
