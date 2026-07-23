@preconcurrency import CloudKit
import LorvexDomain
import LorvexStore
import LorvexSync
import Testing

@testable import LorvexCloudSync

/// Regression coverage for multi-master push and system-fields-cache safety:
///
/// - DEFECT 3: the server-wins conflict path must NOT cache the server's change
///   tag before the server envelope is durably applied and the outbox confirmed,
///   or a crash / batch-fatal apply in that window lets the next cycle re-push
///   the local OLDER version under the cached tag and REGRESS the server.
/// - DEFECT 2: a per-record `unknownItem` must drop that record's stale cached
///   tag so the immediate retry creates it fresh.
struct CloudSyncPushConflictSafetyTests {

  private static let zoneID = cloudSyncTestDescriptor.zoneID

  private func record(
    entityId: String, version: String, name: String = "x"
  ) -> CKRecord {
    let payload = try! SyncCanonicalize.canonicalizeJSON(.object([
      "ai_notes": .null,
      "archived_at": .null,
      "color": .null,
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "description": .null,
      "icon": .null,
      "id": .string(entityId),
      "name": .string(name),
      "position": .int(0),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "version": .string(version),
    ]))
    let envelope = SyncEnvelope(
      entityType: .list, entityId: entityId, operation: .upsert,
      version: try! Hlc.parse(version), payloadSchemaVersion: 1,
      payload: payload, deviceId: "device-001")
    return CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: Self.zoneID)
  }

  private func deleteEnvelope(
    entityType: EntityKind, entityId: String, version: Hlc, deviceId: String
  ) throws -> SyncEnvelope {
    SyncEnvelope(
      entityType: entityType, entityId: entityId, operation: .delete,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object([
        "version": .string(version.description)
      ])),
      deviceId: deviceId)
  }

  private func calendarBaseEnvelope(
    entityId: String, title: String, startDate: String,
    contentVersion: Hlc, topologyVersion: Hlc, rowVersion: Hlc,
    deviceId: String
  ) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "all_day": .bool(false),
      "attendees": .null,
      "color": .null,
      "content_version": .string(contentVersion.description),
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "description": .null,
      "end_date": .string(startDate),
      "end_time": .string("10:00"),
      "event_type": .string("event"),
      "id": .string(entityId),
      "location": .null,
      "occurrence_state": .null,
      "person_name": .null,
      "recurrence": .null,
      "recurrence_generation": .null,
      "recurrence_instance_date": .null,
      "recurrence_topology_version": .string(topologyVersion.description),
      "series_cutover_id": .null,
      "series_id": .null,
      "start_date": .string(startDate),
      "start_time": .string("09:00"),
      "timezone": .string("America/Los_Angeles"),
      "title": .string(title),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "url": .null,
      "version": .string(rowVersion.description),
    ]))
    return SyncEnvelope(
      entityType: .calendarEvent, entityId: entityId, operation: .upsert,
      version: rowVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private func taskEnvelope(
    entityId: String, title: String, dueDate: String?,
    contentVersion: Hlc, scheduleVersion: Hlc, rowVersion: Hlc,
    deviceId: String, payloadSchemaVersion: UInt32 = LorvexVersion.payloadSchemaVersion
  ) throws -> SyncEnvelope {
    let unchangedVersion = min(contentVersion, scheduleVersion)
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "ai_notes": .null,
      "archive_version": .string(unchangedVersion.description),
      "archived_at": .null,
      "available_from": .null,
      "body": .null,
      "canonical_occurrence_date": .null,
      "completed_at": .null,
      "content_version": .string(contentVersion.description),
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "defer_count": .int(0),
      "due_date": dueDate.map(JSONValue.string) ?? .null,
      "estimated_minutes": .null,
      "id": .string(entityId),
      "last_defer_reason": .null,
      "last_deferred_at": .null,
      "lifecycle_version": .string(unchangedVersion.description),
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
      "schedule_version": .string(scheduleVersion.description),
      "spawned_from": .null,
      "spawned_from_version": .null,
      "status": .string("open"),
      "title": .string(title),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "version": .string(rowVersion.description),
    ]))
    return SyncEnvelope(
      entityType: .task, entityId: entityId, operation: .upsert,
      version: rowVersion, payloadSchemaVersion: payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private func cutoverEnvelope(
    lineageRootId: String, date: String,
    state: CalendarSeriesCutoverState, version: Hlc,
    deviceId: String
  ) throws -> SyncEnvelope {
    let id = CalendarSeriesCutoverID.make(
      lineageRootId: lineageRootId, cutoverDate: date)
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "cutover_date": .string(date),
      "id": .string(id),
      "lineage_root_id": .string(lineageRootId),
      "state": .string(state.rawValue),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "version": .string(version.description),
    ]))
    return SyncEnvelope(
      entityType: .calendarSeriesCutover, entityId: id, operation: .upsert,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private func redirectEnvelope(
    sourceId: String, targetId: String, version: Hlc,
    operation: SyncOperation = .upsert, deviceId: String
  ) throws -> SyncEnvelope {
    let wireId = EntityRedirect.wireEntityId(sourceType: .tag, sourceId: sourceId)
    let payload: String
    if operation == .upsert {
      payload = try SyncCanonicalize.canonicalizeJSON(.object([
        "source_id": .string(sourceId),
        "source_type": .string(EntityKind.tag.asString),
        "target_id": .string(targetId),
        "version": .string(version.description),
      ]))
    } else {
      payload = "{}"
    }
    return SyncEnvelope(
      entityType: .entityRedirect, entityId: wireId, operation: operation,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private func forwardCompatibleClient(_ source: SyncEnvelope) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(source.payload) else {
      throw ForwardCompatibleClientFixtureError.invalidPayload
    }
    object["future_probe"] = .string("preserve-me")
    return SyncEnvelope(
      entityType: source.entityType, entityId: source.entityId,
      operation: source.operation, version: source.version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: source.deviceId)
  }

  private enum ForwardCompatibleClientFixtureError: Error {
    case invalidPayload
  }

  private func archivedSystemFields(_ record: CKRecord) -> Data {
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: archiver)
    archiver.finishEncoding()
    return archiver.encodedData
  }

  // MARK: - Fakes

  /// Models `.ifServerRecordUnchanged` with a pre-seeded server version. A push
  /// is accepted (overwriting the server) only when the client "holds the current
  /// tag" — modeled, as elsewhere, as "has a cached system-fields entry". A
  /// client with no entry gets `serverRecordChanged` carrying the seeded server
  /// record so the HLC backstop resolves it.
  private actor SeededIfUnchangedDatabase: CloudKitDatabaseModifying {
    let systemFieldsStore: InMemoryCloudSyncRecordSystemFieldsStore
    private var serverRecords: [String: CKRecord] = [:]

    init(systemFieldsStore: InMemoryCloudSyncRecordSystemFieldsStore) {
      self.systemFieldsStore = systemFieldsStore
    }

    func seed(_ record: CKRecord) { serverRecords[record.recordID.recordName] = record }
    func serverVersion(_ name: String) -> String? {
      serverRecords[name].flatMap { CloudSyncEnvelopeRecord.versionString(from: $0) }
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

  /// Returns `unknownItem` for any record the client presents WITH a cached tag
  /// (a stale tag from a vanished zone). A tag-less push creates the record.
  private actor UnknownItemOnStaleTagDatabase: CloudKitDatabaseModifying {
    let systemFieldsStore: InMemoryCloudSyncRecordSystemFieldsStore
    private var serverRecords: [String: CKRecord] = [:]

    init(systemFieldsStore: InMemoryCloudSyncRecordSystemFieldsStore) {
      self.systemFieldsStore = systemFieldsStore
    }

    func hasServerRecord(_ name: String) -> Bool { serverRecords[name] != nil }

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
        let clientHoldsTag = await systemFieldsStore.systemFields(forRecordName: name) != nil
        if clientHoldsTag {
          results[record.recordID] = .failure(CKError(CKError.Code.unknownItem))
        } else {
          serverRecords[name] = record
          results[record.recordID] = .success(record)
        }
      }
      return (results, [:])
    }
  }

  /// Models `.ifServerRecordUnchanged` for a single seeded server record so a
  /// local-wins RECLAIM can succeed. A fresh client push (a DIFFERENT CKRecord
  /// object that does not hold the live change tag) is rejected with
  /// `serverRecordChanged` carrying the seeded record. The local-wins re-save
  /// re-stamps the client's fields ONTO the seeded server-record instance (which
  /// carries the live tag) and re-saves THAT object, so a save whose record IS the
  /// seeded instance is accepted — modeling the server accepting the reclaim.
  private actor ReclaimableServerDatabase: CloudKitDatabaseModifying {
    private var server: CKRecord
    private var modifyCallCount = 0
    init(seed: CKRecord) { server = seed }
    func serverVersion() -> String? { CloudSyncEnvelopeRecord.versionString(from: server) }
    func serverPayload() -> String? {
      server.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] as? String
    }
    func recordModifyCallCount() -> Int { modifyCallCount }

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
      modifyCallCount += 1
      var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
      for record in recordsToSave {
        if record === server {
          // A re-save onto the server's current record instance (holds the live
          // tag): accept it, and it becomes the new server record.
          results[record.recordID] = .success(record)
        } else {
          // A fresh push without the live tag: reject with the current server.
          results[record.recordID] = .failure(
            CKError(
              CKError.Code.serverRecordChanged,
              userInfo: [
                CKRecordChangedErrorServerRecordKey: server,
                CKRecordChangedErrorClientRecordKey: record,
              ]))
        }
      }
      return (results, [:])
    }
  }

  /// The first save conflicts with `initial`; the local-wins retry then
  /// conflicts with `moved`. This models another device changing the slot
  /// between CloudKit's first conflict response and the bounded re-save.
  private actor MovingConflictDatabase: CloudKitDatabaseModifying {
    private let initial: CKRecord
    private let moved: CKRecord
    private var modifyCallCount = 0

    init(initial: CKRecord, moved: CKRecord) {
      self.initial = initial
      self.moved = moved
    }

    func recordModifyCallCount() -> Int { modifyCallCount }
    func movedVersion() -> String? { CloudSyncEnvelopeRecord.versionString(from: moved) }
    func movedPayload() -> String? {
      moved.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] as? String
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
      modifyCallCount += 1
      let server = modifyCallCount == 1 ? initial : moved
      var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
      for record in recordsToSave {
        results[record.recordID] = .failure(
          CKError(
            CKError.Code.serverRecordChanged,
            userInfo: [
              CKRecordChangedErrorServerRecordKey: server,
              CKRecordChangedErrorClientRecordKey: record,
            ]))
      }
      return (results, [:])
    }
  }

  // MARK: - SYNC18-MED-2: undecodable server-wins record must not wedge outbound push

  @Test
  func equalVersionDifferentPayloadRequiresSuccessorWithoutResavingOldHlc() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-000000000005"
    let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
    let serverRecord = record(
      entityId: entityId, version: version, name: "divergent-server")
    let serverPayload = try #require(
      serverRecord.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] as? String)
    let client = record(entityId: entityId, version: version)
    let db = ReclaimableServerDatabase(seed: serverRecord)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(try await pusher.pushInTestGeneration([client]).first)

    #expect(!result.succeeded)
    guard case .equalVersion(let returnedServer)? = result.collision else {
      Issue.record("equal-HLC semantic mismatch must be returned as a typed collision")
      return
    }
    #expect(returnedServer.payload == serverPayload)
    #expect(result.systemFieldsReceipt != nil)
    #expect(
      await db.serverPayload() == serverPayload,
      "transport must never re-save one contender under the collided HLC")
  }

  @Test(arguments: [true, false])
  func baseCalendarRegisterConflictNeverUsesOuterRowLww(
    localHasWinningContent: Bool
  ) async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000ca21"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let contentVersion = try Hlc.parse("1711234567200_0000_a1b2c3d4a1b2c3d4")
    let topologyVersion = try Hlc.parse("1711234567300_0000_b1c2d3e4b1c2d3e4")
    let contentWinner = try calendarBaseEnvelope(
      entityId: entityId, title: "Winning content", startDate: "2026-07-20",
      contentVersion: contentVersion, topologyVersion: base,
      rowVersion: contentVersion, deviceId: "content-device")
    let topologyWinner = try calendarBaseEnvelope(
      entityId: entityId, title: "Stale content", startDate: "2026-08-20",
      contentVersion: base, topologyVersion: topologyVersion,
      rowVersion: topologyVersion, deviceId: "topology-device")
    let clientEnvelope = localHasWinningContent ? contentWinner : topologyWinner
    let serverEnvelope = localHasWinningContent ? topologyWinner : contentWinner
    let serverRecord = CloudSyncEnvelopeRecord.makeRecord(serverEnvelope, zoneID: Self.zoneID)
    let clientRecord = CloudSyncEnvelopeRecord.makeRecord(clientEnvelope, zoneID: Self.zoneID)
    let db = ReclaimableServerDatabase(seed: serverRecord)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(try await pusher.pushInTestGeneration([clientRecord]).first)

    #expect(!result.succeeded)
    guard case .semanticMerge(.calendarBaseRegisters, let returnedServer)? = result.collision else {
      Issue.record("base calendar contenders must be joined by core, not outer-row LWW")
      return
    }
    #expect(returnedServer == serverEnvelope)
    #expect(result.systemFieldsReceipt != nil)
    #expect(await db.serverVersion() == serverEnvelope.version.description)
    #expect(
      await db.recordModifyCallCount() == 1,
      "a valid base/base pair must be intercepted before the local-wins re-save loop")
    #expect(
      await db.serverPayload() == serverEnvelope.payload,
      "transport must leave both register contenders untouched until core authors a successor")
  }

  @Test(arguments: [true, false])
  func taskRegisterConflictNeverUsesOuterRowLww(localHasWinningContent: Bool) async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000ca22"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let contentVersion = try Hlc.parse("1711234567200_0000_a1b2c3d4a1b2c3d4")
    let scheduleVersion = try Hlc.parse("1711234567300_0000_b1c2d3e4b1c2d3e4")
    let contentWinner = try taskEnvelope(
      entityId: entityId, title: "Winning content", dueDate: nil,
      contentVersion: contentVersion, scheduleVersion: base,
      rowVersion: contentVersion, deviceId: "content-device")
    let scheduleWinner = try taskEnvelope(
      entityId: entityId, title: "Stale content", dueDate: "2026-08-21",
      contentVersion: base, scheduleVersion: scheduleVersion,
      rowVersion: scheduleVersion, deviceId: "schedule-device")
    let clientEnvelope = localHasWinningContent ? contentWinner : scheduleWinner
    let serverEnvelope = localHasWinningContent ? scheduleWinner : contentWinner
    let serverRecord = CloudSyncEnvelopeRecord.makeRecord(serverEnvelope, zoneID: Self.zoneID)
    let clientRecord = CloudSyncEnvelopeRecord.makeRecord(clientEnvelope, zoneID: Self.zoneID)
    let db = ReclaimableServerDatabase(seed: serverRecord)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(try await pusher.pushInTestGeneration([clientRecord]).first)

    #expect(!result.succeeded)
    guard case .semanticMerge(.taskRegisters, let returnedServer)? = result.collision else {
      Issue.record("task contenders must be joined by core, not outer-row LWW")
      return
    }
    #expect(returnedServer == serverEnvelope)
    #expect(result.systemFieldsReceipt != nil)
    #expect(await db.serverVersion() == serverEnvelope.version.description)
    #expect(await db.recordModifyCallCount() == 1)
    #expect(await db.serverPayload() == serverEnvelope.payload)
  }

  @Test
  func forwardCompatibleTaskClientStillRoutesCurrentServerThroughRegisterJoin() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000ca26"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let serverVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let clientVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let server = try taskEnvelope(
      entityId: entityId, title: "Stale server content", dueDate: "2026-08-21",
      contentVersion: base, scheduleVersion: serverVersion,
      rowVersion: serverVersion, deviceId: "server-schedule-device")
    let client = try forwardCompatibleClient(taskEnvelope(
      entityId: entityId, title: "Local future content", dueDate: nil,
      contentVersion: clientVersion, scheduleVersion: base,
      rowVersion: clientVersion, deviceId: "future-client-device"))
    let db = ReclaimableServerDatabase(
      seed: CloudSyncEnvelopeRecord.makeRecord(server, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(try await pusher.pushInTestGeneration([
      CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
    ]).first)

    #expect(!result.succeeded)
    guard case .semanticMerge(.taskRegisters, let returnedServer)? = result.collision else {
      Issue.record("a forward-compatible task client must not outer-LWW over a current server")
      return
    }
    #expect(returnedServer == server)
    #expect(await db.recordModifyCallCount() == 1)
    #expect(await db.serverPayload() == server.payload)
  }

  @Test
  func forwardCompatibleCalendarClientStillRoutesCurrentServerThroughRegisterJoin() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000ca27"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let topologyVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let contentVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let server = try calendarBaseEnvelope(
      entityId: entityId, title: "Stale server content", startDate: "2026-08-20",
      contentVersion: base, topologyVersion: topologyVersion,
      rowVersion: topologyVersion, deviceId: "server-topology-device")
    let client = try forwardCompatibleClient(calendarBaseEnvelope(
      entityId: entityId, title: "Local future content", startDate: "2026-07-20",
      contentVersion: contentVersion, topologyVersion: base,
      rowVersion: contentVersion, deviceId: "future-client-device"))
    let db = ReclaimableServerDatabase(
      seed: CloudSyncEnvelopeRecord.makeRecord(server, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(try await pusher.pushInTestGeneration([
      CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
    ]).first)

    #expect(!result.succeeded)
    guard case .semanticMerge(.calendarBaseRegisters, let returnedServer)? = result.collision else {
      Issue.record("a forward-compatible calendar client must preserve a current topology winner")
      return
    }
    #expect(returnedServer == server)
    #expect(await db.recordModifyCallCount() == 1)
    #expect(await db.serverPayload() == server.payload)
  }

  @Test
  func forwardCompatibleCutoverClientStillRoutesCurrentServerThroughRemoveWinsJoin() async throws {
    let root = "01966a3f-7c8b-7d4e-8f3a-00000000ca28"
    let serverVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let clientVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let server = try cutoverEnvelope(
      lineageRootId: root, date: "2026-08-22", state: .deleted,
      version: serverVersion, deviceId: "server-delete-device")
    let client = try forwardCompatibleClient(cutoverEnvelope(
      lineageRootId: root, date: "2026-08-22", state: .active,
      version: clientVersion, deviceId: "future-client-device"))
    let db = ReclaimableServerDatabase(
      seed: CloudSyncEnvelopeRecord.makeRecord(server, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(try await pusher.pushInTestGeneration([
      CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
    ]).first)

    #expect(!result.succeeded)
    guard case .semanticMerge(.calendarSeriesCutover, let returnedServer)? = result.collision else {
      Issue.record("a forward-compatible active cutover must not overwrite current deleted state")
      return
    }
    #expect(returnedServer == server)
    #expect(await db.recordModifyCallCount() == 1)
    #expect(await db.serverPayload() == server.payload)
  }

  @Test
  func deletedCutoverCannotBeOverwrittenByNewerOuterActiveSnapshot() async throws {
    let root = "01966a3f-7c8b-7d4e-8f3a-00000000ca23"
    let remoteVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let localVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let server = try cutoverEnvelope(
      lineageRootId: root, date: "2026-08-22", state: .deleted,
      version: remoteVersion, deviceId: "delete-device")
    let client = try cutoverEnvelope(
      lineageRootId: root, date: "2026-08-22", state: .active,
      version: localVersion, deviceId: "active-device")
    let db = ReclaimableServerDatabase(
      seed: CloudSyncEnvelopeRecord.makeRecord(server, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
      ]).first)

    #expect(!result.succeeded)
    guard case .semanticMerge(.calendarSeriesCutover, let returnedServer)? = result.collision else {
      Issue.record("cutover state must use its remove-wins join")
      return
    }
    #expect(returnedServer == server)
    #expect(await db.serverVersion() == remoteVersion.description)
    #expect(await db.recordModifyCallCount() == 1)
  }

  @Test
  func competingRedirectTargetsCannotBeOverwrittenByOuterHlc() async throws {
    let source = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let targetA = "00000000-0000-7000-8000-000000000001"
    let targetB = "22222222-2222-7222-8222-222222222222"
    let serverVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let clientVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let server = try redirectEnvelope(
      sourceId: source, targetId: targetA, version: serverVersion,
      deviceId: "target-a-device")
    let client = try redirectEnvelope(
      sourceId: source, targetId: targetB, version: clientVersion,
      deviceId: "target-b-device")
    let db = ReclaimableServerDatabase(
      seed: CloudSyncEnvelopeRecord.makeRecord(server, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
      ]).first)

    #expect(!result.succeeded)
    guard case .semanticMerge(.entityRedirect, let returnedServer)? = result.collision else {
      Issue.record("redirect targets must use the permanent min-terminal union")
      return
    }
    #expect(returnedServer == server)
    #expect(await db.serverVersion() == serverVersion.description)
    #expect(await db.recordModifyCallCount() == 1)
  }

  @Test
  func currentSchemaRedirectDeleteRequiresCanonicalReassertion() async throws {
    let source = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let target = "00000000-0000-7000-8000-000000000001"
    let serverVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let clientVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let server = try redirectEnvelope(
      sourceId: source, targetId: target, version: serverVersion,
      operation: .delete, deviceId: "invalid-delete-device")
    let client = try redirectEnvelope(
      sourceId: source, targetId: target, version: clientVersion,
      deviceId: "canonical-upsert-device")
    let db = ReclaimableServerDatabase(
      seed: CloudSyncEnvelopeRecord.makeRecord(server, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
      ]).first)

    #expect(!result.succeeded)
    guard case .entityRedirectDelete(let returnedServer)? = result.collision else {
      Issue.record("a logical redirect Delete must request a strict-successor reassertion")
      return
    }
    #expect(returnedServer == server)
    #expect(await db.serverVersion() == serverVersion.description)
    #expect(await db.recordModifyCallCount() == 1)
  }

  @Test
  func knownFutureSchemaServerRecordIsParkedBeforeLocalWinsRestamp() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000ca24"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let serverVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let clientVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let server = try taskEnvelope(
      entityId: entityId, title: "Future server", dueDate: nil,
      contentVersion: serverVersion, scheduleVersion: base,
      rowVersion: serverVersion, deviceId: "future-device",
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1)
    let client = try taskEnvelope(
      entityId: entityId, title: "Current client", dueDate: nil,
      contentVersion: clientVersion, scheduleVersion: base,
      rowVersion: clientVersion, deviceId: "current-device")
    let db = ReclaimableServerDatabase(
      seed: CloudSyncEnvelopeRecord.makeRecord(server, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
      ]).first)

    #expect(!result.succeeded)
    #expect(result.isTransient)
    #expect(result.serverRawToDefer?.entityType == EntityKind.task.asString)
    #expect(result.serverRawToDefer?.payloadSchemaVersion == LorvexVersion.payloadSchemaVersion + 1)
    #expect(await db.serverVersion() == serverVersion.description)
    #expect(await db.serverPayload() == server.payload)
    #expect(await db.recordModifyCallCount() == 1)
  }

  @Test
  func malformedCurrentServerWinnerRequiresRepairAtItsHlcFloor() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000cb01"
    let localVersion = "1711234567100_0000_a1b2c3d4a1b2c3d4"
    let serverVersion = "1711234567200_0000_b1c2d3e4b1c2d3e4"
    let server = record(entityId: entityId, version: serverVersion)
    server.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] = "{}"
    guard case .decoded = CloudSyncEnvelopeRecord.decode(server) else {
      Issue.record("the malformed payload must remain structurally decodable")
      return
    }
    let db = ReclaimableServerDatabase(seed: server)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        record(entityId: entityId, version: localVersion)
      ]).first)

    #expect(!result.succeeded)
    guard case .corruptServerSlot(let floor)? = result.collision else {
      Issue.record("a contract-invalid current server winner must request repair")
      return
    }
    #expect(floor?.description == serverVersion)
    #expect(result.serverEnvelopeToApply == nil)
    #expect(result.systemFieldsReceipt != nil)
    #expect(await db.recordModifyCallCount() == 1)
  }

  @Test
  func malformedOlderServerCannotBeOverwrittenWithoutStrictSuccessor() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000cb02"
    let serverVersion = "1711234567100_0000_b1c2d3e4b1c2d3e4"
    let localVersion = "1711234567200_0000_a1b2c3d4a1b2c3d4"
    let server = record(entityId: entityId, version: serverVersion)
    server.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] = "{}"
    let db = ReclaimableServerDatabase(seed: server)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        record(entityId: entityId, version: localVersion)
      ]).first)

    #expect(!result.succeeded)
    guard case .corruptServerSlot(let floor)? = result.collision else {
      Issue.record("a malformed older slot must be repaired, not directly restamped")
      return
    }
    #expect(floor?.description == serverVersion)
    #expect(await db.recordModifyCallCount() == 1)
    #expect(await db.serverPayload() == "{}")
  }

  @Test
  func malformedKnownFutureSchemaFailsCurrentContractFloorInsteadOfParking() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000cb03"
    let base = try Hlc.parse("1711234567000_0000_c1c2d3e4c1c2d3e4")
    let serverVersion = try Hlc.parse("1711234567100_0000_b1c2d3e4b1c2d3e4")
    let localVersion = try Hlc.parse("1711234567200_0000_a1b2c3d4a1b2c3d4")
    let serverEnvelope = try taskEnvelope(
      entityId: entityId, title: "Future malformed", dueDate: nil,
      contentVersion: serverVersion, scheduleVersion: base,
      rowVersion: serverVersion, deviceId: "future-device",
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1)
    let server = CloudSyncEnvelopeRecord.makeRecord(serverEnvelope, zoneID: Self.zoneID)
    server.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] = try SyncCanonicalize
      .canonicalizeJSON(.object([
        "id": .string(entityId),
        "version": .string(serverVersion.description),
        "future_field": .string("opaque"),
      ]))
    let client = try taskEnvelope(
      entityId: entityId, title: "Current local", dueDate: nil,
      contentVersion: localVersion, scheduleVersion: base,
      rowVersion: localVersion, deviceId: "local-device")
    let db = ReclaimableServerDatabase(seed: server)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
      ]).first)

    #expect(!result.succeeded)
    #expect(!result.isTransient)
    #expect(result.serverRawToDefer == nil)
    guard case .corruptServerSlot(let floor)? = result.collision else {
      Issue.record("future known-kind data must satisfy the complete current floor")
      return
    }
    #expect(floor == serverVersion)
    #expect(await db.recordModifyCallCount() == 1)
  }

  @Test
  func localWinsRetryReclassifiesSlotThatMovesToMalformedKnownPayload() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000cb04"
    let initialVersion = try Hlc.parse("1711234567000_0000_c1c2d3e4c1c2d3e4")
    let movedVersion = "1711234567100_0000_b1c2d3e4b1c2d3e4"
    let localVersion = "1711234567200_0000_a1b2c3d4a1b2c3d4"
    let initial = try deleteEnvelope(
      entityType: .list, entityId: entityId, version: initialVersion,
      deviceId: "initial-delete-device")
    let moved = record(entityId: entityId, version: movedVersion)
    moved.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] = "{}"
    let db = MovingConflictDatabase(
      initial: CloudSyncEnvelopeRecord.makeRecord(initial, zoneID: Self.zoneID),
      moved: moved)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        record(entityId: entityId, version: localVersion)
      ]).first)

    #expect(!result.succeeded)
    guard case .corruptServerSlot(let floor)? = result.collision else {
      Issue.record("every local-wins retry must validate the fresh server payload")
      return
    }
    #expect(floor?.description == movedVersion)
    #expect(await db.recordModifyCallCount() == 2)
    #expect(await db.movedPayload() == "{}")
  }

  @Test
  func localWinsRetryReclassifiesSlotThatMovesToTaskRegisterConflict() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000ca25"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let initialVersion = try Hlc.parse("1711234567150_0000_c1c2d3e4c1c2d3e4")
    let movedVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let clientVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let initial = try deleteEnvelope(
      entityType: .task, entityId: entityId, version: initialVersion,
      deviceId: "initial-delete-device")
    let moved = try taskEnvelope(
      entityId: entityId, title: "Stale content", dueDate: "2026-08-25",
      contentVersion: base, scheduleVersion: movedVersion,
      rowVersion: movedVersion, deviceId: "moving-schedule-device")
    let client = try taskEnvelope(
      entityId: entityId, title: "Local content", dueDate: nil,
      contentVersion: clientVersion, scheduleVersion: base,
      rowVersion: clientVersion, deviceId: "local-content-device")
    let db = MovingConflictDatabase(
      initial: CloudSyncEnvelopeRecord.makeRecord(initial, zoneID: Self.zoneID),
      moved: CloudSyncEnvelopeRecord.makeRecord(moved, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
      ]).first)

    #expect(!result.succeeded)
    guard case .semanticMerge(.taskRegisters, let returnedServer)? = result.collision else {
      Issue.record("every retry must re-run typed semantic classification")
      return
    }
    #expect(returnedServer == moved)
    #expect(await db.recordModifyCallCount() == 2)
    #expect(await db.movedVersion() == movedVersion.description)
    #expect(await db.movedPayload() == moved.payload)
  }

  @Test
  func localWinsRetryRoutesForwardCompatibleTaskClientToCurrentRegisterJoin() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000ca29"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let initialVersion = try Hlc.parse("1711234567150_0000_c1c2d3e4c1c2d3e4")
    let movedVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let clientVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let initial = try deleteEnvelope(
      entityType: .task, entityId: entityId, version: initialVersion,
      deviceId: "initial-delete-device")
    let moved = try taskEnvelope(
      entityId: entityId, title: "Stale content", dueDate: "2026-08-25",
      contentVersion: base, scheduleVersion: movedVersion,
      rowVersion: movedVersion, deviceId: "moving-schedule-device")
    let client = try forwardCompatibleClient(taskEnvelope(
      entityId: entityId, title: "Local future content", dueDate: nil,
      contentVersion: clientVersion, scheduleVersion: base,
      rowVersion: clientVersion, deviceId: "future-client-device"))
    let db = MovingConflictDatabase(
      initial: CloudSyncEnvelopeRecord.makeRecord(initial, zoneID: Self.zoneID),
      moved: CloudSyncEnvelopeRecord.makeRecord(moved, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
      ]).first)

    #expect(!result.succeeded)
    guard case .semanticMerge(.taskRegisters, let returnedServer)? = result.collision else {
      Issue.record("bounded retry must reclassify a future task client semantically")
      return
    }
    #expect(returnedServer == moved)
    #expect(await db.recordModifyCallCount() == 2)
    #expect(await db.movedVersion() == movedVersion.description)
    #expect(await db.movedPayload() == moved.payload)
  }

  @Test
  func localWinsRetryParksSlotThatMovesToKnownFutureSchema() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000ca26"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let initialVersion = try Hlc.parse("1711234567150_0000_c1c2d3e4c1c2d3e4")
    let movedVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let clientVersion = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let initial = try deleteEnvelope(
      entityType: .task, entityId: entityId, version: initialVersion,
      deviceId: "initial-delete-device")
    let moved = try taskEnvelope(
      entityId: entityId, title: "Future content", dueDate: nil,
      contentVersion: movedVersion, scheduleVersion: base,
      rowVersion: movedVersion, deviceId: "future-device",
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1)
    let client = try taskEnvelope(
      entityId: entityId, title: "Local content", dueDate: nil,
      contentVersion: clientVersion, scheduleVersion: base,
      rowVersion: clientVersion, deviceId: "local-content-device")
    let db = MovingConflictDatabase(
      initial: CloudSyncEnvelopeRecord.makeRecord(initial, zoneID: Self.zoneID),
      moved: CloudSyncEnvelopeRecord.makeRecord(moved, zoneID: Self.zoneID))
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        CloudSyncEnvelopeRecord.makeRecord(client, zoneID: Self.zoneID)
      ]).first)

    #expect(!result.succeeded)
    #expect(result.isTransient)
    #expect(result.serverRawToDefer?.payloadSchemaVersion == LorvexVersion.payloadSchemaVersion + 1)
    #expect(await db.recordModifyCallCount() == 2)
    #expect(await db.movedVersion() == movedVersion.description)
    #expect(await db.movedPayload() == moved.payload)
  }

  @Test
  func localWinsRetryParksSlotThatMovesToUnknownFutureOperation() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000ca27"
    let initialVersion = try Hlc.parse("1711234567150_0000_c1c2d3e4c1c2d3e4")
    let movedVersion = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let clientVersion = "1711234567300_0000_a1b2c3d4a1b2c3d4"
    let initial = try deleteEnvelope(
      entityType: .list, entityId: entityId, version: initialVersion,
      deviceId: "initial-delete-device")
    let recordName = CloudSyncEnvelopeRecord.recordName(
      entityType: "list", entityId: entityId)
    let moved = CKRecord(
      recordType: CloudSyncEnvelopeRecord.recordType,
      recordID: CKRecord.ID(recordName: recordName, zoneID: Self.zoneID))
    moved.encryptedValues["entity_type"] = "list"
    moved.encryptedValues["entity_id"] = entityId
    moved.encryptedValues["operation"] = "archive"
    moved.encryptedValues["version"] = movedVersion.description
    moved.encryptedValues["payload"] = #"{"q":1}"#
    moved.encryptedValues["device_id"] = "future-operation-device"
    moved.encryptedValues["payload_schema_version"] =
      String(LorvexVersion.payloadSchemaVersion + 1)
    guard case .unknownEntityType = CloudSyncEnvelopeRecord.decode(moved) else {
      Issue.record("the moved server slot must be a future record")
      return
    }
    let db = MovingConflictDatabase(
      initial: CloudSyncEnvelopeRecord.makeRecord(initial, zoneID: Self.zoneID),
      moved: moved)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        record(entityId: entityId, version: clientVersion)
      ]).first)

    #expect(!result.succeeded)
    #expect(result.isTransient)
    #expect(result.serverRawToDefer?.operation == "archive")
    #expect(await db.recordModifyCallCount() == 2)
    #expect(await db.movedVersion() == movedVersion.description)
    #expect(await db.movedPayload() == #"{"q":1}"#)
  }

  @Test(arguments: [nil, "1711234567890_0_a1b2c3d4a1b2c3d4"])
  func missingOrNoncanonicalServerVersionRequiresFreshSuccessor(
    serverVersion: String?
  ) async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-000000000015"
    let localVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
    let serverRecord = record(entityId: entityId, version: localVersion)
    serverRecord.encryptedValues[CloudSyncEnvelopeRecord.Field.version] = serverVersion
    let db = ReclaimableServerDatabase(seed: serverRecord)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        record(entityId: entityId, version: localVersion)
      ]).first)

    #expect(!result.succeeded)
    guard case .corruptServerSlot(let floor)? = result.collision else {
      Issue.record("an exact Lorvex slot without a canonical HLC must request core repair")
      return
    }
    #expect(floor == nil)
    #expect(result.systemFieldsReceipt != nil)
    #expect(await db.serverVersion() == serverVersion)
  }

  @Test
  func embeddedIdentityMismatchFailsClosedWithoutRepairingForeignContent() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-000000000016"
    let foreignId = "01966a3f-7c8b-7d4e-8f3a-000000000017"
    let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
    let serverRecord = record(entityId: entityId, version: version)
    serverRecord.encryptedValues[CloudSyncEnvelopeRecord.Field.entityId] = foreignId
    let db = ReclaimableServerDatabase(seed: serverRecord)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(
      try await pusher.pushInTestGeneration([
        record(entityId: entityId, version: version)
      ]).first)

    #expect(!result.succeeded)
    #expect(result.collision == nil)
    #expect(result.errorMessage?.contains("foreign embedded entity identity") == true)
    #expect(
      await db.serverPayload()
        == (serverRecord.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] as? String))
  }

  @Test
  func localNewerVersionNeverRestampsOntoForeignRecordType() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-000000000006"
    let local = record(
      entityId: entityId, version: "1711234567891_0000_a1b2c3d4a1b2c3d4")
    let olderLorvex = record(
      entityId: entityId, version: "1711234567890_0000_a1b2c3d4a1b2c3d4")
    let foreign = CKRecord(recordType: "ForeignRecord", recordID: olderLorvex.recordID)
    CloudSyncEnvelopeRecord.restamp(from: olderLorvex, onto: foreign)
    let db = ReclaimableServerDatabase(seed: foreign)
    let pusher = CloudKitRecordPusher(database: db)

    let result = try #require(try await pusher.pushInTestGeneration([local]).first)

    #expect(!result.succeeded)
    #expect(result.errorMessage?.contains("foreign or mismatched") == true)
  }

  /// A canonical server HLC far ahead of this device's wall clock is still a
  /// valid ordered mutation. Rejecting it at decode would poison every traversal
  /// cursor forever; conflict resolution must therefore surface it as the server
  /// winner and let the detached local-edit lane handle any later override.
  @Test
  func canonicalFutureServerRecordRemainsAnApplicableWinner() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-000000000003"
    let future = try #require(
      try? Hlc(
        physicalMs: Hlc.maxPhysicalMs, counter: 0,
        deviceSuffix: "a1b2c3d4a1b2c3d4")
    ).description
    let clientVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"

    let serverRecord = record(entityId: entityId, version: future)
    guard case .decoded = CloudSyncEnvelopeRecord.decode(serverRecord) else {
      Issue.record("canonical future record must decode")
      return
    }

    let store = InMemoryCloudSyncRecordSystemFieldsStore()
    let db = ReclaimableServerDatabase(seed: serverRecord)
    let pusher = CloudKitRecordPusher(database: db, zoneID: Self.zoneID, systemFieldsStore: store)

    let client = record(entityId: entityId, version: clientVersion)
    let result = try #require(try await pusher.pushInTestGeneration([client]).first)

    #expect(result.succeeded)
    #expect(result.serverEnvelopeToApply?.version.description == future)
    #expect(await db.serverVersion() == future)
  }

  /// A `serverRecordChanged` whose server record is honest forward-compat from a
  /// NEWER build: the same `list` record slot carries a future operation on a
  /// schema-ahead record, so `decode` PARKS it (`.unknownEntityType`) rather than
  /// dropping it. This build cannot apply it, but it is not corruption. Pre-fix
  /// the nil-collapsing decode failed it NON-transiently, escalating toward
  /// quarantine; the fix fails it TRANSIENT so the outbox row waits for a build
  /// that understands the operation instead of being reaped.
  @Test
  func forwardCompatUnknownTypeServerRecordWaitsTransientWithoutEscalation() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-000000000004"
    let clientRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: "list", entityId: entityId)
    // Newer than the client, so the HLC compare resolves server-wins; a future
    // operation with a known entity_type and schema-ahead marker parks as
    // `.unknownEntityType`.
    let serverRecord = CKRecord(
      recordType: CloudSyncEnvelopeRecord.recordType,
      recordID: CKRecord.ID(recordName: clientRecordName, zoneID: Self.zoneID))
    let nowMs = UInt64(Date().timeIntervalSince1970 * 1_000)
    let serverVersion = try Hlc(
      physicalMs: nowMs + 1_000, counter: 0,
      deviceSuffix: "b1b2c3d4b1b2c3d4").description
    let clientVersion = try Hlc(
      physicalMs: nowMs, counter: 0,
      deviceSuffix: "a1b2c3d4a1b2c3d4").description
    serverRecord.encryptedValues["entity_type"] = "list"
    serverRecord.encryptedValues["entity_id"] = entityId
    serverRecord.encryptedValues["operation"] = "archive"
    serverRecord.encryptedValues["version"] = serverVersion
    serverRecord.encryptedValues["payload"] = #"{"q":1}"#
    serverRecord.encryptedValues["device_id"] = "device-newer"
    serverRecord.encryptedValues["payload_schema_version"] = String(LorvexVersion.payloadSchemaVersion + 1)
    guard case .unknownEntityType = CloudSyncEnvelopeRecord.decode(serverRecord) else {
      Issue.record("the server record must decode as .unknownEntityType (forward-compat)")
      return
    }

    let store = InMemoryCloudSyncRecordSystemFieldsStore()
    let db = SeededIfUnchangedDatabase(systemFieldsStore: store)
    await db.seed(serverRecord)
    let pusher = CloudKitRecordPusher(database: db, zoneID: Self.zoneID, systemFieldsStore: store)

    let client = record(entityId: entityId, version: clientVersion)
    let result = try #require(try await pusher.pushInTestGeneration([client]).first)

    #expect(result.succeeded == false, "this build cannot apply a future-type record")
    #expect(
      result.isTransient == true,
      "a forward-compat server record must WAIT transiently, not escalate to quarantine")
    #expect(
      result.serverRawToDefer?.operation == "archive",
      "the raw future server record must be carried so the coordinator can park it durably")
    #expect(result.serverRawToDefer?.entityId == entityId)
  }

  @Test
  func localHlcCannotOverwriteUnknownFutureOperation() async throws {
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000f004"
    let recordName = CloudSyncEnvelopeRecord.recordName(
      entityType: "list", entityId: entityId)
    let serverRecord = CKRecord(
      recordType: CloudSyncEnvelopeRecord.recordType,
      recordID: CKRecord.ID(recordName: recordName, zoneID: Self.zoneID))
    let serverVersion = "1711234567890_0000_b1b2c3d4b1b2c3d4"
    let clientVersion = "1711234567990_0000_a1b2c3d4a1b2c3d4"
    serverRecord.encryptedValues["entity_type"] = "list"
    serverRecord.encryptedValues["entity_id"] = entityId
    serverRecord.encryptedValues["operation"] = "archive"
    serverRecord.encryptedValues["version"] = serverVersion
    serverRecord.encryptedValues["payload"] = #"{"q":1}"#
    serverRecord.encryptedValues["device_id"] = "device-newer-build"
    serverRecord.encryptedValues["payload_schema_version"] =
      String(LorvexVersion.payloadSchemaVersion + 1)
    guard case .unknownEntityType = CloudSyncEnvelopeRecord.decode(serverRecord) else {
      Issue.record("the schema-ahead operation must decode as a future record")
      return
    }

    let db = ReclaimableServerDatabase(seed: serverRecord)
    let pusher = CloudKitRecordPusher(database: db)
    let client = record(entityId: entityId, version: clientVersion)

    let result = try #require(try await pusher.pushInTestGeneration([client]).first)

    #expect(!result.succeeded)
    #expect(result.isTransient)
    #expect(result.serverRawToDefer?.operation == "archive")
    #expect(await db.serverVersion() == serverVersion)
    #expect(await db.recordModifyCallCount() == 1)
  }

  // MARK: - DEFECT 3

  @Test
  func serverWinsRetryDoesNotRegressServerAfterCrashBeforeConfirm() async throws {
    let recordName = CloudSyncEnvelopeRecord.recordName(
      entityType: "list", entityId: "01966a3f-7c8b-7d4e-8f3a-000000000001")
    let store = InMemoryCloudSyncRecordSystemFieldsStore()
    let db = SeededIfUnchangedDatabase(systemFieldsStore: store)
    let pusher = CloudKitRecordPusher(database: db, zoneID: Self.zoneID, systemFieldsStore: store)

    let older = "1711234567890_0000_a1b2c3d4a1b2c3d4"
    let newer = "1711234567899_0000_a1b2c3d4a1b2c3d4"
    // The server already holds a STRICTLY NEWER version (a peer won).
    await db.seed(record(entityId: "01966a3f-7c8b-7d4e-8f3a-000000000001", version: newer))

    // This device pushes its OLDER version: the conflict resolves server-wins.
    let local = record(entityId: "01966a3f-7c8b-7d4e-8f3a-000000000001", version: older)
    let first = try await pusher.pushInTestGeneration([local])
    #expect(first.first?.succeeded == true)
    #expect(first.first?.serverEnvelopeToApply != nil)

    // Simulate a crash / batch-fatal apply BEFORE the server envelope was applied
    // and the outbox row confirmed: the result is dropped, the row stays pending.
    // The next cycle re-pushes the SAME local older record.
    _ = try await pusher.pushInTestGeneration([local])

    // The server MUST NOT have regressed to the older version.
    #expect(await db.serverVersion(recordName) == newer)
  }

  // MARK: - DEFECT 2 (per-record unknownItem)

  @Test
  func unknownItemDropsStaleCacheEntryAndRetryCreatesFresh() async throws {
    let store = InMemoryCloudSyncRecordSystemFieldsStore()
    let db = UnknownItemOnStaleTagDatabase(systemFieldsStore: store)
    let pusher = CloudKitRecordPusher(database: db, zoneID: Self.zoneID, systemFieldsStore: store)

    let rec = record(entityId: "01966a3f-7c8b-7d4e-8f3a-000000000002", version:
      "1711234567890_0000_a1b2c3d4a1b2c3d4")
    let name = rec.recordID.recordName
    // A stale cached tag survives from the previous zone (post account adopt).
    await store.store(archivedSystemFields(rec), forRecordName: name)
    #expect(await store.cachedRecordCount() == 1)

    // The re-hydrated record presents the stale tag → unknownItem.
    let first = try await pusher.pushInTestGeneration([rec])
    #expect(first.first?.succeeded == false)
    #expect(first.first?.isTransient == true)
    #expect(await store.cachedRecordCount() == 0, "the stale cache entry is dropped for a fresh retry")
    #expect(await db.hasServerRecord(name) == false)

    // Retry: no cache → a tag-less record CREATES fresh in the new zone.
    let second = try await pusher.pushInTestGeneration([rec])
    #expect(second.first?.succeeded == true)
    #expect(await db.hasServerRecord(name) == true)
  }
}
