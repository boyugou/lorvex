@preconcurrency import CloudKit
import LorvexDomain
import LorvexSync
import Testing

@testable import LorvexCloudSync

/// SY10: after an entity's first push, subsequent pushes of an unchanged-on-server
/// record must satisfy `.ifServerRecordUnchanged` from the cached CKRecord system
/// fields, NOT fall into per-record `serverRecordChanged` conflict resolution
/// (which serializes one re-save per record and feeds `requestRateLimited`).
struct CloudSyncRecordPusherSystemFieldsTests {

  private static let zoneID = cloudSyncTestDescriptor.zoneID

  private func envelopeRecord(entityId: String = "01966a3f-7c8b-7d4e-8f3a-000000000001") -> CKRecord {
    let version = try! Hlc.parse("1711234567890_0007_a1b2c3d4a1b2c3d4")
    let payload = try! SyncCanonicalize.canonicalizeJSON(.object([
      "ai_notes": .null,
      "archive_version": .string(version.description),
      "archived_at": .null,
      "available_from": .null,
      "body": .null,
      "canonical_occurrence_date": .null,
      "completed_at": .null,
      "content_version": .string(version.description),
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "defer_count": .int(0),
      "due_date": .null,
      "estimated_minutes": .null,
      "id": .string(entityId),
      "last_defer_reason": .null,
      "last_deferred_at": .null,
      "lifecycle_version": .string(version.description),
      "list_id": .string("00000000-0000-7000-8000-000000000001"),
      "planned_date": .null,
      "priority": .null,
      "raw_input": .null,
      "recurrence": .null,
      "recurrence_exceptions": .null,
      "recurrence_group_id": .null,
      "recurrence_instance_key": .null,
      "recurrence_rollover_state": .string("none"),
      "recurrence_successor_id": .null,
      "schedule_version": .string(version.description),
      "spawned_from": .null,
      "spawned_from_version": .null,
      "status": .string("open"),
      "title": .string("x"),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "version": .string(version.description),
    ]))
    let envelope = SyncEnvelope(
      entityType: .task,
      entityId: entityId,
      operation: .upsert,
      version: version,
      payloadSchemaVersion: 1,
      payload: payload,
      deviceId: "device-001")
    return CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: Self.zoneID)
  }

  /// Fake `CKDatabase` seam modeling `.ifServerRecordUnchanged`: a record already
  /// on the server saves only if the CLIENT holds the server's current change tag.
  /// We model "holds the current tag" as "has a persisted system-fields entry for
  /// the record" — exactly what the SY10 cache carries and re-hydrates the
  /// outgoing record from. A client without that entry sends a tag-less record and
  /// gets `serverRecordChanged`.
  private actor IfUnchangedDatabase: CloudKitDatabaseModifying {
    let systemFieldsStore: InMemoryCloudSyncRecordSystemFieldsStore
    private var serverRecords: [String: CKRecord] = [:]
    private(set) var serverRecordChangedCount = 0

    init(systemFieldsStore: InMemoryCloudSyncRecordSystemFieldsStore) {
      self.systemFieldsStore = systemFieldsStore
    }

    func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord? {
      recordID == CloudSyncZoneEpochRecord.recordID()
        ? makeCloudSyncTestControlRecord() : nil
    }

    func modifyRecordZones(
      saving recordZonesToSave: [CKRecordZone], deleting recordZoneIDsToDelete: [CKRecordZone.ID]
    ) async throws -> (
      saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
      deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
    ) {
      var saved: [CKRecordZone.ID: Result<CKRecordZone, any Error>] = [:]
      for zone in recordZonesToSave { saved[zone.zoneID] = .success(zone) }
      return (saved, [:])
    }

    func modifyRecords(
      saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID],
      savePolicy: CKModifyRecordsOperation.RecordSavePolicy, atomically: Bool
    ) async throws -> (
      saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
      deleteResults: [CKRecord.ID: Result<Void, any Error>]
    ) {
      var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
      for record in recordsToSave {
        let name = record.recordID.recordName
        if let existing = serverRecords[name] {
          let clientHoldsTag = await systemFieldsStore.systemFields(forRecordName: name) != nil
          if clientHoldsTag {
            serverRecords[name] = record
            results[record.recordID] = .success(record)
          } else {
            serverRecordChangedCount += 1
            results[record.recordID] = .failure(
              CKError(
                CKError.Code.serverRecordChanged,
                userInfo: [
                  CKRecordChangedErrorServerRecordKey: existing,
                  CKRecordChangedErrorClientRecordKey: record,
                ]))
          }
        } else {
          serverRecords[name] = record
          results[record.recordID] = .success(record)
        }
      }
      return (results, [:])
    }
  }

  @Test
  func secondPushOfCachedRecordSkipsConflictPath() async throws {
    let store = InMemoryCloudSyncRecordSystemFieldsStore()
    let db = IfUnchangedDatabase(systemFieldsStore: store)
    let pusher = CloudKitRecordPusher(database: db, zoneID: Self.zoneID, systemFieldsStore: store)

    // First push creates the record and caches its system fields.
    let first = try await pusher.pushInTestGeneration([envelopeRecord()])
    #expect(first.allSatisfy { $0.succeeded })
    #expect(await store.cachedRecordCount() == 1)
    #expect(await db.serverRecordChangedCount == 0)

    // Second push of the (unchanged-on-server) record: the pusher re-hydrates it
    // from the cached tag, so the save matches `.ifServerRecordUnchanged` and the
    // conflict path is NOT taken.
    let second = try await pusher.pushInTestGeneration([envelopeRecord()])
    #expect(second.allSatisfy { $0.succeeded })
    #expect(await db.serverRecordChangedCount == 0)
  }

  @Test
  func withoutCachedTagSecondPushIsForcedThroughConflictPath() async throws {
    // Control: with the cache lost, the same second push is forced through
    // `serverRecordChanged` (the pre-fix behavior) — proving the cache is what
    // avoids the per-record conflict path. HLC still resolves it (equal version).
    let store = InMemoryCloudSyncRecordSystemFieldsStore()
    let db = IfUnchangedDatabase(systemFieldsStore: store)
    let pusher = CloudKitRecordPusher(database: db, zoneID: Self.zoneID, systemFieldsStore: store)

    _ = try await pusher.pushInTestGeneration([envelopeRecord()])
    await store.clear()

    let second = try await pusher.pushInTestGeneration([envelopeRecord()])

    #expect(second.allSatisfy { $0.succeeded })
    #expect(await db.serverRecordChangedCount == 1)
  }
}
