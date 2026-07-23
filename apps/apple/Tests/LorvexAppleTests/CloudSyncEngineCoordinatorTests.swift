@preconcurrency import CloudKit
import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import Testing

@testable import LorvexCloudSync
@testable import LorvexCore

private struct GenerationReadbackCrash: Error {}

private let authoritativeRemoteVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"

/// Build a complete current-contract list payload for coordinator transport
/// fixtures. These tests exercise traversal behavior, but their records still
/// have to cross the same production manifest boundary as a real peer record.
private func coordinatorListPayload(
  id: String, name: String, version: String, timestamp: String
) throws -> String {
  try canonicalizeJSON(
    .object([
      "ai_notes": .null,
      "archived_at": .null,
      "color": .null,
      "created_at": .string(timestamp),
      "description": .null,
      "icon": .null,
      "id": .string(id),
      "name": .string(name),
      "position": .int(0),
      "updated_at": .string(timestamp),
      "version": .string(version),
    ]))
}

/// Build a complete current-contract task payload for the same traversal
/// fixtures. Keeping every required field explicit makes future manifest
/// additions fail at this test boundary instead of silently weakening runtime
/// validation.
private func coordinatorTaskPayload(
  id: String, title: String, version: String, timestamp: String,
  listID: String = "inbox"
) throws -> String {
  try canonicalizeJSON(
    .object([
      "ai_notes": .null,
      "archive_version": .string(version),
      "archived_at": .null,
      "available_from": .null,
      "body": .null,
      "canonical_occurrence_date": .null,
      "completed_at": .null,
      "content_version": .string(version),
      "created_at": .string(timestamp),
      "defer_count": .int(0),
      "due_date": .null,
      "estimated_minutes": .null,
      "id": .string(id),
      "last_defer_reason": .null,
      "last_deferred_at": .null,
      "lifecycle_version": .string(version),
      "list_id": .string(listID),
      "planned_date": .null,
      "priority": .null,
      "raw_input": .null,
      "recurrence": .null,
      "recurrence_exceptions": .null,
      "recurrence_group_id": .null,
      "recurrence_instance_key": .null,
      "recurrence_rollover_state": .string("none"),
      "recurrence_successor_id": .null,
      "schedule_version": .string(version),
      "spawned_from": .null,
      "spawned_from_version": .null,
      "status": .string("open"),
      "title": .string(title),
      "updated_at": .string(timestamp),
      "version": .string(version),
    ]))
}

private func coordinatorFixtureID(_ ordinal: Int) -> String {
  let suffix = String(ordinal, radix: 16)
  let paddedSuffix = String(repeating: "0", count: 12 - suffix.count) + suffix
  return "01966a3f-7c8b-7d4e-8f3a-\(paddedSuffix)"
}

private func coordinatorTaskEnvelope(
  id: String, title: String, listID: String,
  version: String = authoritativeRemoteVersion
) throws -> SyncEnvelope {
  SyncEnvelope(
    entityType: .task, entityId: id, operation: .upsert,
    version: try Hlc.parse(version),
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: try coordinatorTaskPayload(
      id: id, title: title, version: version,
      timestamp: "2026-07-14T00:00:00.000Z", listID: listID),
    deviceId: "remote-device")
}

private func coordinatorTaskRegisterEnvelope(
  id: String, title: String, dueDate: String?, contentVersion: Hlc,
  scheduleVersion: Hlc, rowVersion: Hlc, deviceId: String,
  payloadSchemaVersion: UInt32 = LorvexVersion.payloadSchemaVersion,
  futureProbe: String? = nil
) throws -> SyncEnvelope {
  let timestamp = "2026-07-14T00:00:00.000Z"
  guard case .object(var object)? = JSONValue.parse(try coordinatorTaskPayload(
    id: id, title: title, version: rowVersion.description, timestamp: timestamp
  )) else {
    throw CoordinatorRecoveryProbeError.unexpectedFetch
  }
  object["content_version"] = .string(contentVersion.description)
  object["schedule_version"] = .string(scheduleVersion.description)
  object["due_date"] = dueDate.map(JSONValue.string) ?? .null
  if let futureProbe { object["future_probe"] = .string(futureProbe) }
  return SyncEnvelope(
    entityType: .task, entityId: id, operation: .upsert,
    version: rowVersion, payloadSchemaVersion: payloadSchemaVersion,
    payload: try canonicalizeJSON(.object(object)), deviceId: deviceId)
}

private func coordinatorListRecord(
  descriptor: CloudSyncGenerationDescriptor,
  id: String, name: String,
  version: String = authoritativeRemoteVersion
) throws -> CKRecord {
  let envelope = SyncEnvelope(
    entityType: .list, entityId: id, operation: .upsert,
    version: try Hlc.parse(version),
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: try coordinatorListPayload(
      id: id, name: name, version: version,
      timestamp: "2026-07-14T00:00:00.000Z"),
    deviceId: "remote-device")
  return CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: descriptor.zoneID)
}

private func coordinatorCalendarBaseEnvelope(
  id: String, title: String, startDate: String,
  contentVersion: Hlc, topologyVersion: Hlc, rowVersion: Hlc,
  deviceId: String
) throws -> SyncEnvelope {
  let payload = try canonicalizeJSON(.object([
    "all_day": .bool(false),
    "attendees": .null,
    "color": .null,
    "content_version": .string(contentVersion.description),
    "created_at": .string("2026-07-15T00:00:00.000Z"),
    "description": .null,
    "end_date": .string(startDate),
    "end_time": .string("10:00"),
    "event_type": .string("event"),
    "id": .string(id),
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
    entityType: .calendarEvent, entityId: id, operation: .upsert,
    version: rowVersion,
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: payload, deviceId: deviceId)
}

/// Seed an outbox row for coordinator bookkeeping tests without exposing a
/// non-manifest-validated enqueue surface from the production sync module.
private func seedOutboxEnvelope(_ db: Database, _ envelope: SyncEnvelope) throws {
  try db.execute(
    sql: """
      INSERT INTO sync_outbox
        (entity_type, entity_id, operation, version, payload_schema_version,
         payload, device_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
    arguments: [
      envelope.entityType.asString, envelope.entityId, envelope.operation.asString,
      envelope.version.description, envelope.payloadSchemaVersion, envelope.payload,
      envelope.deviceId, SyncTimestampFormat.syncTimestampNow(),
    ])
}

private func seedCloudSyncCorruption<T>(
  _ db: Database, _ body: () throws -> T
) throws -> T {
  try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
  do {
    let result = try body()
    try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
    return result
  } catch {
    try? db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
    throw error
  }
}

private func authoritativeInboxRecord(
  descriptor: CloudSyncGenerationDescriptor
) throws -> CKRecord {
  let payload = try coordinatorListPayload(
    id: "inbox", name: "Inbox", version: authoritativeRemoteVersion,
    timestamp: "2026-07-14T00:00:00.000Z")
  let envelope = SyncEnvelope(
    entityType: .list, entityId: "inbox", operation: .upsert,
    version: try Hlc.parse(authoritativeRemoteVersion),
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: payload, deviceId: "remote-device")
  return CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: descriptor.zoneID)
}

private func partialRemoteListRecord(
  descriptor: CloudSyncGenerationDescriptor
) throws -> CKRecord {
  let listID = "01966a3f-7c8b-7d4e-8f3a-00000000c701"
  let version = "1761234567890_0000_d1e2f3a4d1e2f3a4"
  let payload = try coordinatorListPayload(
    id: listID, name: "Committed before retry", version: version,
    timestamp: "2025-10-24T00:00:00.000Z")
  let envelope = SyncEnvelope(
    entityType: .list, entityId: listID, operation: .upsert,
    version: try Hlc.parse(version),
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: payload, deviceId: "remote-device")
  return CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: descriptor.zoneID)
}

private func remoteListTombstoneRecord(
  descriptor: CloudSyncGenerationDescriptor,
  listID: String
) throws -> CKRecord {
  CloudSyncEnvelopeRecord.makeRecord(
    try remoteListTombstoneEnvelope(listID: listID), zoneID: descriptor.zoneID)
}

private func remoteListTombstoneEnvelope(listID: String) throws -> SyncEnvelope {
  let version = "1761234567890_0000_d1e2f3a4d1e2f3a4"
  let payload = try coordinatorListPayload(
    id: listID, name: "Deleted remotely", version: version,
    timestamp: "2025-10-24T00:00:00.000Z")
  return SyncEnvelope(
    entityType: .list, entityId: listID, operation: .delete,
    version: try Hlc.parse(version),
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: payload, deviceId: "remote-device")
}

private func partialRemoteTaskRecord(
  descriptor: CloudSyncGenerationDescriptor
) throws -> CKRecord {
  let taskID = "01966a3f-7c8b-7d4e-8f3a-00000000c702"
  let version = "1761234567891_0000_d1e2f3a4d1e2f3a4"
  let payload = try coordinatorTaskPayload(
    id: taskID, title: "Committed terminal page", version: version,
    timestamp: "2025-10-24T00:00:01.000Z")
  let envelope = SyncEnvelope(
    entityType: .task, entityId: taskID, operation: .upsert,
    version: try Hlc.parse(version),
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: payload, deviceId: "remote-device")
  return CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: descriptor.zoneID)
}

private func authoritativeFutureRecord(
  descriptor: CloudSyncGenerationDescriptor
) -> CKRecord {
  let entityType = "future_entity"
  let entityID = "future-record"
  let record = CKRecord(
    recordType: CloudSyncEnvelopeRecord.recordType,
    recordID: CKRecord.ID(
      recordName: CloudSyncEnvelopeRecord.recordName(
        entityType: entityType, entityId: entityID),
      zoneID: descriptor.zoneID))
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.entityType] = entityType
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.entityId] = entityID
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.operation] = SyncOperation.upsert.asString
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.version] = authoritativeRemoteVersion
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] =
    String(LorvexVersion.payloadSchemaVersion)
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] = #"{"future":true}"#
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.deviceId] = "future-device"
  return record
}

private func corruptEntityRecord(
  descriptor: CloudSyncGenerationDescriptor
) -> CKRecord {
  let entityType = EntityKind.task.asString
  let entityID = "01966a3f-7c8b-7d4e-8f3a-00000000c001"
  let record = CKRecord(
    recordType: CloudSyncEnvelopeRecord.recordType,
    recordID: CKRecord.ID(
      recordName: CloudSyncEnvelopeRecord.recordName(
        entityType: entityType, entityId: entityID),
      zoneID: descriptor.zoneID))
  // Deliberately omit every required encrypted field. This is a poison entity,
  // not a foreign record and not a forward-compatible record.
  return record
}

private func foreignRecordOccupyingEntitySlot(
  descriptor: CloudSyncGenerationDescriptor,
  entityType: String,
  entityID: String
) -> CKRecord {
  CKRecord(
    recordType: "ForeignRecord",
    recordID: CKRecord.ID(
      recordName: CloudSyncEnvelopeRecord.recordName(
        entityType: entityType, entityId: entityID),
      zoneID: descriptor.zoneID))
}

private func validReplacementForCorruptEntity(
  descriptor: CloudSyncGenerationDescriptor
) throws -> CKRecord {
  let entityID = "01966a3f-7c8b-7d4e-8f3a-00000000c001"
  let payload = try coordinatorTaskPayload(
    id: entityID, title: "Recovered remote task",
    version: authoritativeRemoteVersion,
    timestamp: "2026-07-14T00:00:00.000Z")
  let envelope = SyncEnvelope(
    entityType: .task, entityId: entityID, operation: .upsert,
    version: try Hlc.parse(authoritativeRemoteVersion),
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: payload, deviceId: "remote-device")
  return CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: descriptor.zoneID)
}

private actor TwoPageAuthoritativeSnapshotFetcher: CloudSyncRemoteChangeFetching {
  let inbox: CKRecord
  private(set) var checkpoints: [CloudSyncChangeCursor?] = []
  private(set) var traversalIdentifiers: [String?] = []

  init(inbox: CKRecord) { self.inbox = inbox }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    checkpoints.append(checkpoint)
    traversalIdentifiers.append(traversalWitnessIdentifier)
    if checkpoints.count == 1 {
      return CloudSyncRemoteChangeBatch(
        records: [inbox], serverChangeTokenData: Data([0x31]),
        moreComing: true,
        observedGenerationRoot: true,
        observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    }
    return CloudSyncRemoteChangeBatch(
      records: [], serverChangeTokenData: Data([0x32]),
      moreComing: false)
  }
}

private actor CrashAfterFirstCandidateReadbackPageFetcher:
  CloudSyncRemoteChangeFetching
{
  let pusher: RecordingRecordPusher
  private var candidateCallCount = 0

  init(pusher: RecordingRecordPusher) { self.pusher = pusher }

  func fetchChanges(
    after _: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    guard context.readyWitness == nil else {
      return CloudSyncRemoteChangeBatch(
        records: [], serverChangeTokenData: Data([9]),
        moreComing: false,
        observedGenerationRoot: true,
        observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    }

    candidateCallCount += 1
    let records = await Array(pusher.pushedRecordsByName.values)
      .sorted { $0.recordID.recordName < $1.recordID.recordName }
    let split = max(1, records.count / 2)
    switch candidateCallCount {
    case 1:
      return CloudSyncRemoteChangeBatch(
        records: Array(records.prefix(split)), serverChangeTokenData: Data([1]),
        moreComing: true,
        observedGenerationRoot: true,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    case 2:
      throw GenerationReadbackCrash()
    default:
      return CloudSyncRemoteChangeBatch(
        records: Array(records.dropFirst(split)), serverChangeTokenData: Data([2]),
        moreComing: false,
        observedGenerationRoot: true,
        observedTraversalWitnessIdentifiers: [])
    }
  }
}

private actor MutatingCandidateReadbackFetcher: CloudSyncRemoteChangeFetching {
  let pusher: RecordingRecordPusher
  let core: SwiftLorvexCoreService
  private(set) var createdTaskID: String?

  init(pusher: RecordingRecordPusher, core: SwiftLorvexCoreService) {
    self.pusher = pusher
    self.core = core
  }

  func fetchChanges(
    after _: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    guard context.readyWitness == nil else {
      return CloudSyncRemoteChangeBatch(
        records: [], serverChangeTokenData: Data([8]),
        moreComing: false,
        observedGenerationRoot: true,
        observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    }
    if createdTaskID == nil {
      createdTaskID =
        try await core.createTask(
          title: "Written after immutable capture", notes: ""
        ).id
    }
    let records = await Array(pusher.pushedRecordsByName.values)
    return CloudSyncRemoteChangeBatch(
      records: records, serverChangeTokenData: Data([1]),
      moreComing: false,
      observedGenerationRoot: true,
      observedTraversalWitnessIdentifiers:
        traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

private actor RecordingTerminalChangeFetcher: CloudSyncRemoteChangeFetching {
  private(set) var checkpoints: [CloudSyncChangeCursor?] = []
  private(set) var traversalIdentifiers: [String?] = []
  let terminalToken: Data

  init(terminalToken: Data) { self.terminalToken = terminalToken }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    checkpoints.append(checkpoint)
    traversalIdentifiers.append(traversalWitnessIdentifier)
    return CloudSyncRemoteChangeBatch(
      records: [], serverChangeTokenData: terminalToken,
      moreComing: false,
      observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers:
        traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

private actor NilThenValidTerminalChangeFetcher: CloudSyncRemoteChangeFetching {
  private(set) var checkpoints: [CloudSyncChangeCursor?] = []
  private(set) var traversalIdentifiers: [String?] = []

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    checkpoints.append(checkpoint)
    traversalIdentifiers.append(traversalWitnessIdentifier)
    guard checkpoints.count <= 2 else {
      throw CoordinatorRecoveryProbeError.unexpectedFetch
    }
    return CloudSyncRemoteChangeBatch(
      records: [],
      serverChangeTokenData: checkpoints.count == 1 ? nil : Data([0x24]),
      moreComing: false,
      observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers:
        traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

private actor ExpiringMidBaselineFetcher: CloudSyncRemoteChangeFetching {
  let firstPageRecords: [CKRecord]
  private(set) var checkpoints: [CloudSyncChangeCursor?] = []
  private(set) var traversalIdentifiers: [String?] = []

  init(firstPageRecords: [CKRecord] = []) {
    self.firstPageRecords = firstPageRecords
  }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    checkpoints.append(checkpoint)
    traversalIdentifiers.append(traversalWitnessIdentifier)
    switch checkpoints.count {
    case 1:
      return CloudSyncRemoteChangeBatch(
        records: firstPageRecords, serverChangeTokenData: Data([0x31]),
        moreComing: true,
        observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    case 2:
      throw CKError(.changeTokenExpired)
    default:
      return CloudSyncRemoteChangeBatch(
        records: [], serverChangeTokenData: Data([0x32]),
        moreComing: false,
        observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    }
  }
}

private actor PerRecordFailureFetcher: CloudSyncRemoteChangeFetching {
  let failure: CloudSyncPerRecordFetchFailure
  let records: [CKRecord]
  private(set) var callCount = 0

  init(failure: CloudSyncPerRecordFetchFailure, records: [CKRecord] = []) {
    self.failure = failure
    self.records = records
  }

  func fetchChanges(
    after _: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    callCount += 1
    return CloudSyncRemoteChangeBatch(
      records: records, serverChangeTokenData: nil, perRecordFailure: failure,
      moreComing: false,
      observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers:
        traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

private actor ExpiringCandidateReadbackFetcher: CloudSyncRemoteChangeFetching {
  let pusher: RecordingRecordPusher
  private(set) var candidateCheckpoints: [CloudSyncChangeCursor?] = []
  private(set) var candidateTraversalIdentifiers: [String?] = []

  init(pusher: RecordingRecordPusher) { self.pusher = pusher }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    guard context.readyWitness == nil else {
      return CloudSyncRemoteChangeBatch(
        records: [], serverChangeTokenData: Data([0x40]),
        moreComing: false,
        observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    }
    candidateCheckpoints.append(checkpoint)
    candidateTraversalIdentifiers.append(traversalWitnessIdentifier)
    let records = await Array(pusher.pushedRecordsByName.values)
      .sorted { $0.recordID.recordName < $1.recordID.recordName }
    let split = max(1, records.count / 2)
    switch candidateCheckpoints.count {
    case 1:
      return CloudSyncRemoteChangeBatch(
        records: Array(records.prefix(split)), serverChangeTokenData: Data([0x41]),
        moreComing: true,
        observedGenerationRoot: true,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    case 2:
      throw CKError(.changeTokenExpired)
    default:
      // Readback was reset to nil, so the recovered terminal page must describe
      // the complete candidate inventory rather than only the old page suffix.
      return CloudSyncRemoteChangeBatch(
        records: records, serverChangeTokenData: Data([0x42]),
        moreComing: false,
        observedGenerationRoot: true,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    }
  }
}

private actor ExpiringAuthoritativeSnapshotFetcher: CloudSyncRemoteChangeFetching {
  let completeInventory: [CKRecord]
  private(set) var checkpoints: [CloudSyncChangeCursor?] = []
  private(set) var traversalIdentifiers: [String?] = []

  init(completeInventory: [CKRecord]) { self.completeInventory = completeInventory }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    checkpoints.append(checkpoint)
    traversalIdentifiers.append(traversalWitnessIdentifier)
    switch checkpoints.count {
    case 1:
      return CloudSyncRemoteChangeBatch(
        records: completeInventory, serverChangeTokenData: Data([0x51]),
        moreComing: true,
        observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    case 2:
      throw CKError(.changeTokenExpired)
    default:
      return CloudSyncRemoteChangeBatch(
        records: completeInventory, serverChangeTokenData: Data([0x52]),
        moreComing: false,
        observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    }
  }
}

private actor ExpiringPredecessorFetcher: CloudSyncRemoteChangeFetching {
  let previousZoneName: String
  let pusher: RecordingRecordPusher
  private(set) var previousCheckpoints: [CloudSyncChangeCursor?] = []
  private(set) var previousTraversalIdentifiers: [String?] = []
  private(set) var events: [String] = []

  init(previousZoneName: String, pusher: RecordingRecordPusher) {
    self.previousZoneName = previousZoneName
    self.pusher = pusher
  }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    if context.zoneName == previousZoneName {
      previousCheckpoints.append(checkpoint)
      previousTraversalIdentifiers.append(traversalWitnessIdentifier)
      events.append("previous-\(previousCheckpoints.count)")
      switch previousCheckpoints.count {
      case 1:
        return CloudSyncRemoteChangeBatch(
          records: [], serverChangeTokenData: Data([0x61]),
          moreComing: true,
          observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
          observedTraversalWitnessIdentifiers:
            traversalWitnessIdentifier.map { [$0] } ?? [])
      case 2:
        throw CKError(.changeTokenExpired)
      case 3:
        return CloudSyncRemoteChangeBatch(
          records: [], serverChangeTokenData: Data([0x62]),
          moreComing: false,
          observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
          observedTraversalWitnessIdentifiers:
            traversalWitnessIdentifier.map { [$0] } ?? [])
      default:
        return CloudSyncRemoteChangeBatch(
          records: [], serverChangeTokenData: Data([0x63]),
          moreComing: false,
          observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
          observedTraversalWitnessIdentifiers:
            traversalWitnessIdentifier.map { [$0] } ?? [])
      }
    }

    events.append("candidate")
    let records = await Array(pusher.pushedRecordsByName.values)
    return CloudSyncRemoteChangeBatch(
      records: records, serverChangeTokenData: Data([0x64]),
      moreComing: false,
      observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers:
        traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

/// Drives predecessor-rebuild recovery while exposing every predecessor
/// checkpoint. Candidate/readied generations are reflected from the recording
/// pusher so their immutable readback remains an independent transport pass.
private actor ScriptedPredecessorRecoveryFetcher: CloudSyncRemoteChangeFetching {
  struct Page: Sendable {
    let records: [CKRecord]
    let token: Data
  }

  let previousZoneName: String
  let pusher: RecordingRecordPusher
  let previousPages: [Page]
  private(set) var previousCheckpoints: [CloudSyncChangeCursor?] = []

  init(
    previousZoneName: String, pusher: RecordingRecordPusher,
    previousPages: [Page]
  ) {
    self.previousZoneName = previousZoneName
    self.pusher = pusher
    self.previousPages = previousPages
  }

  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    if context.zoneName == previousZoneName {
      previousCheckpoints.append(checkpoint)
      let index = previousCheckpoints.count - 1
      let page = index < previousPages.count
        ? previousPages[index]
        : Page(records: [], token: Data([0x7F]))
      return CloudSyncRemoteChangeBatch(
        records: page.records, serverChangeTokenData: page.token,
        moreComing: false, observedGenerationRoot: true,
        observedReadyWitness: context.readyWitness,
        observedTraversalWitnessIdentifiers:
          traversalWitnessIdentifier.map { [$0] } ?? [])
    }

    let records = await Array(pusher.pushedRecordsByName.values)
      .filter { $0.recordID.zoneID == context.zoneID }
      .sorted { $0.recordID.recordName < $1.recordID.recordName }
    return CloudSyncRemoteChangeBatch(
      records: records, serverChangeTokenData: Data([0x7E]),
      moreComing: false, observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers:
        traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

private actor MissingPredecessorFetcher: CloudSyncRemoteChangeFetching {
  let previousZoneName: String
  let pusher: RecordingRecordPusher
  let invalidateBoundaryBeforeError: Bool
  private(set) var previousFetchCount = 0
  private(set) var candidateFetchCount = 0

  init(
    previousZoneName: String, pusher: RecordingRecordPusher,
    invalidateBoundaryBeforeError: Bool = false
  ) {
    self.previousZoneName = previousZoneName
    self.pusher = pusher
    self.invalidateBoundaryBeforeError = invalidateBoundaryBeforeError
  }

  func fetchChanges(
    after _: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    if context.zoneName == previousZoneName {
      previousFetchCount += 1
      if invalidateBoundaryBeforeError {
        await pusher.setGenerationState(
          .deleted(
            deletionGeneration: context.epoch + 1,
            retiredZoneNames: [previousZoneName], modifiedAt: nil))
      }
      throw CKError(.zoneNotFound)
    }

    candidateFetchCount += 1
    let records = await Array(pusher.pushedRecordsByName.values)
      .filter { $0.recordID.zoneID == context.zoneID }
      .sorted { $0.recordID.recordName < $1.recordID.recordName }
    return CloudSyncRemoteChangeBatch(
      records: records, serverChangeTokenData: Data([0x65]), moreComing: false,
      observedGenerationRoot: true, observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers:
        traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

private enum CoordinatorRecoveryProbeError: Error, Equatable {
  case publish
  case delete
  case postCommit
  case unexpectedFetch
}

private actor WitnessRecoveryPusher: CloudSyncRecordPushing {
  private var publishFailuresRemaining: Int
  private var deleteFailuresRemaining: Int
  private let failRetentionReadAt: Int?
  private(set) var publishedTraversalIdentifiers: [String] = []
  private(set) var deletedTraversalIdentifiers: [String] = []
  private(set) var retentionReadCount = 0

  init(
    publishFailures: Int = 0, deleteFailures: Int = 0,
    failRetentionReadAt: Int? = nil
  ) {
    self.publishFailuresRemaining = publishFailures
    self.deleteFailuresRemaining = deleteFailures
    self.failRetentionReadAt = failRetentionReadAt
  }

  func publishTraversalWitness(
    context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    traversalIdentifier: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {
    publishedTraversalIdentifiers.append(traversalIdentifier)
    if publishFailuresRemaining > 0 {
      publishFailuresRemaining -= 1
      throw CoordinatorRecoveryProbeError.publish
    }
  }

  func deleteTraversalWitness(
    context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    traversalIdentifier: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {
    deletedTraversalIdentifiers.append(traversalIdentifier)
    if deleteFailuresRemaining > 0 {
      deleteFailuresRemaining -= 1
      throw CoordinatorRecoveryProbeError.delete
    }
  }

  func readAuditRetentionMetadata(
    context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncAuditRetentionMetadata? {
    retentionReadCount += 1
    if retentionReadCount == failRetentionReadAt {
      throw CoordinatorRecoveryProbeError.postCommit
    }
    return .initial
  }
}

/// Models the two transport passes around a grouped-register collision. The
/// first pass returns the server contender without mutating it; after core has
/// durably replaced the old outbox row, the second pass accepts that successor
/// as the new server record.
private actor SemanticRegisterRetryPusher: CloudSyncRecordPushing {
  private let kind: SemanticPushConflictKind
  private var serverEnvelope: SyncEnvelope
  private var pushCount = 0

  init(kind: SemanticPushConflictKind, serverEnvelope: SyncEnvelope) {
    self.kind = kind
    self.serverEnvelope = serverEnvelope
  }

  func push(
    _ records: [CKRecord], context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    return records.map { record in
      guard case .decoded(let client) = CloudSyncEnvelopeRecord.decode(record) else {
        return CloudSyncPushResult(
          recordName: record.recordID.recordName, succeeded: false,
          errorMessage: "semantic retry fake received an undecodable record")
      }
      pushCount += 1
      if pushCount == 1 {
        return CloudSyncPushResult(
          recordName: record.recordID.recordName, succeeded: false,
          collision: .semanticMerge(kind: kind, serverEnvelope: serverEnvelope))
      }
      serverEnvelope = client
      return CloudSyncPushResult(recordName: record.recordID.recordName, succeeded: true)
    }
  }

  func currentServerEnvelope() -> SyncEnvelope { serverEnvelope }
  func recordPushCount() -> Int { pushCount }
}

/// Returns one scripted collision, then accepts the replacement row. This
/// models CloudKit's next compare-and-save after a concurrent local write made
/// the first collision capability stale.
private actor OneShotCollisionPusher: CloudSyncRecordPushing {
  private let recordName: String
  private let collision: CloudSyncPushCollision
  private let receipt: CloudSyncSystemFieldsReceipt?
  private let firstPushHook: @Sendable () async throws -> Void
  private var didReturnCollision = false
  private var targetAttemptEnvelopes: [SyncEnvelope] = []
  private var acceptedTargetEnvelopes: [SyncEnvelope] = []
  private(set) var reconciledConflictReceiptBatches: [[CloudSyncSystemFieldsReceipt]] = []

  init(
    recordName: String,
    collision: CloudSyncPushCollision,
    receipt: CloudSyncSystemFieldsReceipt? = nil,
    firstPushHook: @escaping @Sendable () async throws -> Void
  ) {
    self.recordName = recordName
    self.collision = collision
    self.receipt = receipt
    self.firstPushHook = firstPushHook
  }

  func push(
    _ records: [CKRecord], context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    guard await boundaryGuard?() ?? true else { throw CloudSyncAccountBoundaryCrossed() }
    for record in records where record.recordID.recordName == recordName {
      if case .decoded(let envelope) = CloudSyncEnvelopeRecord.decode(record) {
        targetAttemptEnvelopes.append(envelope)
      }
    }
    if !didReturnCollision,
      records.contains(where: { $0.recordID.recordName == recordName })
    {
      didReturnCollision = true
      try await firstPushHook()
      return records.map {
        guard $0.recordID.recordName == recordName else {
          return CloudSyncPushResult(
            recordName: $0.recordID.recordName, succeeded: true)
        }
        return CloudSyncPushResult(
          recordName: $0.recordID.recordName, succeeded: false,
          collision: collision, systemFieldsReceipt: receipt)
      }
    }
    return records.map { record in
      if record.recordID.recordName == recordName,
        case .decoded(let envelope) = CloudSyncEnvelopeRecord.decode(record)
      {
        acceptedTargetEnvelopes.append(envelope)
      }
      return CloudSyncPushResult(recordName: record.recordID.recordName, succeeded: true)
    }
  }

  func attemptedTargetEnvelopes() -> [SyncEnvelope] { targetAttemptEnvelopes }
  func acceptedTargetRecords() -> [SyncEnvelope] { acceptedTargetEnvelopes }

  func commitReconciledConflictSystemFields(
    _ receipts: [CloudSyncSystemFieldsReceipt], context _: CloudSyncGenerationContext,
    expectation _: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {
    reconciledConflictReceiptBatches.append(receipts)
  }
}

private struct ScriptedInboundPage {
  var records: [CKRecord]
  var token: Data
  var moreComing: Bool
}

private actor ScriptedInboundFetcher: CloudSyncRemoteChangeFetching {
  private let pages: [ScriptedInboundPage]
  private(set) var callCount = 0
  private(set) var traversalIdentifiers: [String?] = []

  init(pages: [ScriptedInboundPage]) { self.pages = pages }

  func fetchChanges(
    after _: CloudSyncChangeCursor?, context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    guard callCount < pages.count else {
      throw CoordinatorRecoveryProbeError.unexpectedFetch
    }
    let page = pages[callCount]
    callCount += 1
    traversalIdentifiers.append(traversalWitnessIdentifier)
    return CloudSyncRemoteChangeBatch(
      records: page.records, serverChangeTokenData: page.token,
      moreComing: page.moreComing, observedGenerationRoot: true,
      observedReadyWitness: context.readyWitness,
      observedTraversalWitnessIdentifiers:
        traversalWitnessIdentifier.map { [$0] } ?? [])
  }
}

private actor TerminalOperationInvocationProbe {
  private var count = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func record() {
    count += 1
    let pending = waiters
    waiters.removeAll()
    for waiter in pending { waiter.resume() }
  }

  func waitUntilRecorded() async {
    if count > 0 { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func recordedCount() -> Int { count }
}

private actor BlockingTerminalOperation {
  private var entered = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { entryWaiters.append($0) }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }

  func run() async -> String {
    entered = true
    let pending = entryWaiters
    entryWaiters.removeAll()
    for waiter in pending { waiter.resume() }
    await withCheckedContinuation { releaseContinuation = $0 }
    return "completed"
  }
}

private actor MutableActiveOutboxCapPolicy {
  private var includeActiveOutboxCap: Bool
  private var readCount = 0

  init(includeActiveOutboxCap: Bool) {
    self.includeActiveOutboxCap = includeActiveOutboxCap
  }

  func setIncludeActiveOutboxCap(_ value: Bool) {
    includeActiveOutboxCap = value
  }

  func read() -> Bool {
    readCount += 1
    return includeActiveOutboxCap
  }

  func reads() -> Int { readCount }
}

private final class RecordingRetentionSync: @unchecked Sendable, EnvelopeSyncServicing {
  private let lock = NSLock()
  private var recordedPolicies: [Bool] = []

  var policies: [Bool] {
    lock.lock()
    defer { lock.unlock() }
    return recordedPolicies
  }

  func runLocalRetentionMaintenance(includeActiveOutboxCap: Bool) throws {
    lock.lock()
    recordedPolicies.append(includeActiveOutboxCap)
    lock.unlock()
  }

  func pendingOutbound() throws -> [PendingOutboundEnvelope] { [] }
  func markOutboundSynced(outboxIds _: [Int64]) throws {}
  func recordOutboundFailure(
    outboxId _: Int64, error _: String, kind _: OutboundFailureKind
  ) throws {}
  func applyInbound(
    _ envelopes: [SyncEnvelope], undecodable: Int
  ) throws -> InboundApplyReport {
    InboundApplyReport(undecodable: undecodable)
  }
  func deferUnknownTypeRecords(_ raws: [RawEnvelopeFields]) throws {}
  func enqueueFullResyncBackfill() throws -> FullResyncBackfillReport {
    FullResyncBackfillReport()
  }
  func enrolledZoneEpoch(forAccountIdentifier _: String) throws -> Int? { nil }
}

@Suite(.serialized)
struct CloudSyncEngineCoordinatorTests {
  private func coordinator(
    pusher: any CloudSyncRecordPushing,
    fetcher: any CloudSyncRemoteChangeFetching = StubRemoteChangeFetcher(records: []),
    accountAvailability: CloudKitAccountAvailability = .available
  ) -> CloudSyncEngineCoordinator {
    CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(availability: accountAvailability),
      pusher: pusher,
      fetcher: fetcher,
      accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
      accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"),
      accountPauseStore: RecordingCloudSyncPauseStore())
  }

  private func seedCompletedBaseline(
    core: SwiftLorvexCoreService,
    descriptor: CloudSyncGenerationDescriptor
  ) throws {
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let boundary = try CloudTraversalBoundary(
      accountIdentifier: "account-A", zoneIdentifier: descriptor.zoneName,
      generation: descriptor.epoch,
      generationIdentifier: descriptor.generationID,
      readyWitness: descriptor.readyWitness,
      tombstoneCompactionCutoff: descriptor.tombstoneCompactionCutoff)
    let traversal = "seeded-baseline-traversal"
    _ = try core.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: traversal, start: .baseline)
    let page = try CloudTraversalPageCommit(
      pageIndex: 0, continuationToken: Data([0x20]), moreComing: false,
      observation: try CloudTraversalPageObservation(
        generationRootIdentifier: descriptor.generationID,
        readyWitness: descriptor.readyWitness,
        traversalWitnessIdentifier: traversal))
    _ = try core.applyInboundTraversalPage(
      [], deferredUnknownTypeRecords: [], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: traversal, page: page,
      inboundObservation: CloudInboundPageObservation())
  }

  @Test
  func terminalOperationDrainsEveryInboundPageBeforeItRuns() async throws {
    let core = try makeInMemoryCore()
    let fetcher = ScriptedMoreComingFetcher(
      moreComingScript: [true, false], tokenData: Data([0x81]))
    let subject = coordinator(pusher: RecordingRecordPusher(), fetcher: fetcher)

    let result = try await subject.withTerminalInboundDrain(core: core) {
      await fetcher.callCount
    }

    #expect(result.value == 2)
    #expect(result.drainReport.moreInboundComing == false)
    #expect(await fetcher.callCount == 2)
  }

  @Test
  func terminalOperationDrainsPendingInboxPastTheSinglePassLimitBeforeItRuns() async throws {
    let core = try makeInMemoryCore()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let parentListID = coordinatorFixtureID(10_000)
    let childCount = 501
    let childRecords = try (1...childCount).map { ordinal in
      let envelope = try coordinatorTaskEnvelope(
        id: coordinatorFixtureID(ordinal), title: "Deferred child \(ordinal)",
        listID: parentListID)
      return CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: descriptor.zoneID)
    }
    let parentRecord = try coordinatorListRecord(
      descriptor: descriptor, id: parentListID, name: "Late parent")
    let fetcher = ScriptedInboundFetcher(pages: [
      ScriptedInboundPage(
        records: childRecords, token: Data([0x8E]), moreComing: true),
      ScriptedInboundPage(
        records: [parentRecord], token: Data([0x8F]), moreComing: false),
    ])
    let subject = coordinator(pusher: RecordingRecordPusher(), fetcher: fetcher)

    let result = try await subject.withTerminalInboundDrain(core: core) {
      try core.unresolvedInboundRecordCount()
    }

    #expect(result.value == 0)
    #expect(result.drainReport.inbound.deferred == childCount)
    #expect(result.drainReport.inbound.drainReplayed == childCount)
    #expect(try core.unresolvedInboundRecordCount() == 0)
    let appliedChildren = try core.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tasks WHERE list_id = ?",
        arguments: [parentListID]) ?? 0
    }
    #expect(appliedChildren == childCount)
    #expect(await fetcher.callCount == 2)
  }

  @Test
  func terminalOperationRejectsTheNonterminalDrainCapWithoutRunning() async throws {
    let core = try makeInMemoryCore()
    let fetcher = ScriptedMoreComingFetcher(
      moreComingScript: Array(repeating: true, count: CloudSyncEngineCoordinator.maxDrainIterations),
      tokenData: Data([0x82]))
    let subject = coordinator(pusher: RecordingRecordPusher(), fetcher: fetcher)
    let probe = TerminalOperationInvocationProbe()

    do {
      _ = try await subject.withTerminalInboundDrain(core: core) {
        await probe.record()
      }
      Issue.record("a capped nonterminal traversal must not authorize the operation")
    } catch let error as CloudSyncTerminalInboundDrainError {
      guard case .terminalBoundaryNotReached(let report) = error else {
        Issue.record("expected a nonterminal-drain error, got \(error)")
        return
      }
      #expect(report.moreInboundComing)
    }

    #expect(await fetcher.callCount == CloudSyncEngineCoordinator.maxDrainIterations)
    #expect(await probe.recordedCount() == 0)
  }

  @Test
  func terminalOperationRejectsAnUnavailableAccountWithoutRunning() async throws {
    let core = try makeInMemoryCore()
    let subject = coordinator(
      pusher: RecordingRecordPusher(), accountAvailability: .noAccount)
    let probe = TerminalOperationInvocationProbe()

    do {
      _ = try await subject.withTerminalInboundDrain(core: core) {
        await probe.record()
      }
      Issue.record("an unavailable account must defer the operation")
    } catch let error as CloudSyncTerminalInboundDrainError {
      #expect(error == .accountUnavailable(.noAccount))
    }

    #expect(await probe.recordedCount() == 0)
  }

  @Test
  func terminalOperationRejectsDeletedZoneEmptyReportWithoutRunning() async throws {
    let core = try makeInMemoryCore()
    let pusher = RecordingRecordPusher(ensureZoneErrorCode: .userDeletedZone)
    let subject = coordinator(pusher: pusher)
    let probe = TerminalOperationInvocationProbe()

    do {
      _ = try await subject.withTerminalInboundDrain(core: core) {
        await probe.record()
      }
      Issue.record("a deleted-zone empty report is not terminal inbound proof")
    } catch let error as CloudSyncTerminalInboundDrainError {
      #expect(error == .syncPaused(.userDeletedZone))
    }

    #expect(await probe.recordedCount() == 0)
    #expect(await subject.currentPauseReason() == .userDeletedZone)
  }

  @Test
  func terminalOperationCanRunAfterATerminalPagePostWorkFailure() async throws {
    let core = try makeInMemoryCore()
    let pusher = WitnessRecoveryPusher(failRetentionReadAt: 2)
    let fetcher = ScriptedInboundFetcher(
      pages: [
        ScriptedInboundPage(
          records: [try partialRemoteListRecord(descriptor: cloudSyncTestDescriptor)],
          token: Data([0x85]), moreComing: false)
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)
    let probe = TerminalOperationInvocationProbe()

    let result = try await subject.withTerminalInboundDrain(core: core) {
      await probe.record()
    }

    #expect(result.drainReport.fetchedRecordCount == 1)
    #expect(result.postTerminalSyncFailure != nil)
    #expect(await probe.recordedCount() == 1)
    let committedName = try core.read { db in
      try String.fetchOne(
        db, sql: "SELECT name FROM lists WHERE id = ?",
        arguments: ["01966a3f-7c8b-7d4e-8f3a-00000000c701"])
    }
    #expect(committedName == "Committed before retry")
  }

  @Test
  func terminalOperationRejectsAnIncompleteReseedEvenAfterTerminalInbound() async throws {
    let core = try makeInMemoryCore()
    try core.write { db in
      try seedCloudSyncCorruption(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
            VALUES ('task', 'poison-import-reseed-task', 'tainted-version',
                    '2026-07-14T00:00:00.000Z')
            """)
      }
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }
    let subject = coordinator(
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(
        records: [], serverChangeTokenData: Data([0x86])))
    let probe = TerminalOperationInvocationProbe()

    do {
      _ = try await subject.withTerminalInboundDrain(core: core) {
        await probe.record()
      }
      Issue.record("a partial full-resync backfill must defer the operation")
    } catch let error as CloudSyncTerminalInboundDrainError {
      #expect(error == .runtimeNotReady)
    }

    #expect(try core.isReseedRequired())
    #expect(await probe.recordedCount() == 0)
  }

  @Test
  func terminalOperationRejectsReseedRaisedByTheFixedPointTail() async throws {
    let core = try makeInMemoryCore()
    let missingParentID = coordinatorFixtureID(20_000)
    let taskID = coordinatorFixtureID(20_001)
    let deferred = try coordinatorTaskEnvelope(
      id: taskID, title: "Expires after the terminal witness",
      listID: missingParentID)
    try core.write { db in
      try PendingInboxDrain.enqueuePending(
        db, envelope: deferred, reason: "missing list dependency",
        missingEntityType: EntityName.list, missingEntityID: missingParentID)
      // The first page apply runs retention before it commits the terminal
      // witness. Backdate only after that witness insert so the row is lost by
      // the subsequent local fixed-point apply, reproducing the exact window
      // that used to turn completeness into a misleading 0/0 success.
      try db.execute(
        sql: """
          CREATE TEMP TRIGGER expire_pending_after_terminal_witness
          AFTER INSERT ON sync_cloudkit_traversal_witness
          BEGIN
            UPDATE sync_pending_inbox
            SET first_attempted_at = '2000-01-01T00:00:00.000Z'
            WHERE envelope_entity_type = 'task'
              AND envelope_entity_id = '\(taskID)';
          END
          """)
    }
    let subject = coordinator(
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(
        records: [], serverChangeTokenData: Data([0x88])))
    let probe = TerminalOperationInvocationProbe()

    do {
      _ = try await subject.withTerminalInboundDrain(core: core) {
        await probe.record()
      }
      Issue.record("reseed raised by the fixed-point tail must defer the operation")
    } catch let error as CloudSyncTerminalInboundDrainError {
      #expect(error == .runtimeNotReady)
    }

    #expect(try core.isReseedRequired())
    #expect(try core.unresolvedInboundRecordCount() == 0)
    #expect(await probe.recordedCount() == 0)
  }

  @Test
  func terminalOperationRejectsWhenGenerationRootProofChangesAfterThePull() async throws {
    let core = try makeInMemoryCore()
    let pusher = RecordingRecordPusher(
      generationRootValidationResults: [true, false])
    let subject = coordinator(
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(
        records: [], serverChangeTokenData: Data([0x87])))
    let probe = TerminalOperationInvocationProbe()

    do {
      _ = try await subject.withTerminalInboundDrain(core: core) {
        await probe.record()
      }
      Issue.record("a stale generation-root proof must not authorize the operation")
    } catch let error as CloudSyncTerminalInboundDrainError {
      #expect(error == .runtimeNotReady)
    }

    #expect(await probe.recordedCount() == 0)
  }

  @Test
  func terminalOperationRejectsACompletedTraversalThatDroppedCorruptState() async throws {
    let core = try makeInMemoryCore()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let subject = coordinator(
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(
        records: [corruptEntityRecord(descriptor: descriptor)],
        serverChangeTokenData: Data([0x89])))
    let probe = TerminalOperationInvocationProbe()

    do {
      _ = try await subject.withTerminalInboundDrain(core: core) {
        await probe.record()
      }
      Issue.record("a traversal that discarded remote state must not authorize an import")
    } catch let error as CloudSyncTerminalInboundDrainError {
      guard case .inboundStateIncomplete(let report, let pending, let corrupt) = error else {
        Issue.record("expected durable inbound-incomplete state, got \(error)")
        return
      }
      #expect(report.inbound.undecodable == 1)
      #expect(pending == 0)
      #expect(corrupt == 1)
    }

    #expect(await probe.recordedCount() == 0)
  }

  @Test
  func corruptDebtSurvivesAnEmptyRetryUntilAValidReplacementArrives() async throws {
    let core = try makeInMemoryCore()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let fetcher = ScriptedInboundFetcher(pages: [
      ScriptedInboundPage(
        records: [corruptEntityRecord(descriptor: descriptor)],
        token: Data([0x8B]), moreComing: false),
      ScriptedInboundPage(records: [], token: Data([0x8C]), moreComing: false),
      ScriptedInboundPage(
        records: [try validReplacementForCorruptEntity(descriptor: descriptor)],
        token: Data([0x8D]), moreComing: false),
    ])
    let subject = coordinator(pusher: RecordingRecordPusher(), fetcher: fetcher)
    let probe = TerminalOperationInvocationProbe()

    for _ in 0..<2 {
      do {
        _ = try await subject.withTerminalInboundDrain(core: core) {
          await probe.record()
        }
        Issue.record("corrupt debt must survive a clean incremental retry")
      } catch let error as CloudSyncTerminalInboundDrainError {
        guard case .inboundStateIncomplete(_, let pending, let corrupt) = error else {
          Issue.record("expected durable inbound-incomplete state, got \(error)")
          return
        }
        #expect(pending == 0)
        #expect(corrupt == 1)
      }
    }
    #expect(await probe.recordedCount() == 0)

    _ = try await subject.withTerminalInboundDrain(core: core) {
      await probe.record()
    }
    #expect(await probe.recordedCount() == 1)
    #expect(await fetcher.callCount == 3)
  }

  @Test
  func quarantinedInboundDebtCannotDisappearFromTerminalCompleteness() async throws {
    let core = try makeInMemoryCore()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let parentListID = coordinatorFixtureID(30_000)
    let taskID = coordinatorFixtureID(30_001)
    let poisoned = try coordinatorTaskEnvelope(
      id: taskID, title: "Initially deferred", listID: parentListID)
    try core.write { db in
      try PendingInboxDrain.enqueuePending(
        db, envelope: poisoned, reason: "missing list dependency",
        missingEntityType: EntityName.list, missingEntityID: parentListID)
      try db.execute(
        sql: """
          UPDATE sync_pending_inbox
          SET attempt_count = ?, last_attempted_at = '2000-01-01T00:00:00.000Z'
          WHERE envelope_entity_type = ? AND envelope_entity_id = ?
          """,
        arguments: [PendingInbox.maxAttempts, EntityName.task, taskID])
    }

    let replacementVersion = "1711234567891_0000_a1b2c3d4a1b2c3d4"
    let replacement = try coordinatorTaskEnvelope(
      id: taskID, title: "Recovered by valid replacement", listID: parentListID,
      version: replacementVersion)
    let fetcher = ScriptedInboundFetcher(pages: [
      ScriptedInboundPage(records: [], token: Data([0x90]), moreComing: false),
      ScriptedInboundPage(records: [], token: Data([0x91]), moreComing: false),
      ScriptedInboundPage(
        records: [
          try coordinatorListRecord(
            descriptor: descriptor, id: parentListID, name: "Recovered parent"),
          CloudSyncEnvelopeRecord.makeRecord(replacement, zoneID: descriptor.zoneID),
        ],
        token: Data([0x92]), moreComing: false),
    ])
    let subject = coordinator(pusher: RecordingRecordPusher(), fetcher: fetcher)
    let probe = TerminalOperationInvocationProbe()

    for _ in 0..<2 {
      do {
        _ = try await subject.withTerminalInboundDrain(core: core) {
          await probe.record()
        }
        Issue.record("quarantined inbound debt must survive an empty retry")
      } catch let error as CloudSyncTerminalInboundDrainError {
        guard case .inboundStateIncomplete(_, let pending, let corrupt) = error else {
          Issue.record("expected durable quarantined inbound state, got \(error)")
          return
        }
        #expect(pending == 0)
        #expect(corrupt == 1)
      }
    }
    #expect(await probe.recordedCount() == 0)
    #expect(try core.quarantinedInboundRecordCount() == 1)

    _ = try await subject.withTerminalInboundDrain(core: core) {
      await probe.record()
    }
    #expect(await probe.recordedCount() == 1)
    #expect(try core.quarantinedInboundRecordCount() == 0)
    #expect((try await core.loadTask(id: taskID)).title == "Recovered by valid replacement")
  }

  @Test
  func terminalOperationRejectsFutureStateHeldByAnEarlierTraversal() async throws {
    let core = try makeInMemoryCore()
    try core.deferUnknownTypeRecords([
      RawEnvelopeFields(
        entityType: "future_entity",
        entityId: "future-record-from-earlier-traversal",
        operation: SyncOperation.upsert.asString,
        version: authoritativeRemoteVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: #"{"future":true}"#,
        deviceId: "future-device")
    ])
    #expect(try core.unresolvedFutureRecordCount() == 1)

    let subject = coordinator(
      pusher: RecordingRecordPusher(),
      fetcher: StubRemoteChangeFetcher(
        records: [], serverChangeTokenData: Data([0x8A])))
    let probe = TerminalOperationInvocationProbe()

    do {
      _ = try await subject.withTerminalInboundDrain(core: core) {
        await probe.record()
      }
      Issue.record("a previously parked future record must keep import fail-closed")
    } catch let error as CloudSyncTerminalInboundDrainError {
      guard case .inboundStateIncomplete(let report, let pending, let corrupt) = error else {
        Issue.record("expected durable pending inbound state, got \(error)")
        return
      }
      #expect(report.inbound.undecodable == 0)
      #expect(pending == 1)
      #expect(corrupt == 0)
    }

    #expect(await probe.recordedCount() == 0)
  }

  @Test
  func terminalOperationKeepsTheCoordinatorGateUntilItsClosureFinishes() async throws {
    let core = try makeInMemoryCore()
    let fetcher = ScriptedMoreComingFetcher(
      moreComingScript: [false, false], tokenData: Data([0x83]))
    let subject = coordinator(pusher: RecordingRecordPusher(), fetcher: fetcher)
    let blocker = BlockingTerminalOperation()

    let first = Task {
      try await subject.withTerminalInboundDrain(core: core) {
        await blocker.run()
      }
    }
    await blocker.waitUntilEntered()
    #expect(await fetcher.callCount == 1)

    let secondStarted = TerminalOperationInvocationProbe()
    let second = Task {
      await secondStarted.record()
      return try await subject.runCycle(sync: core)
    }
    await secondStarted.waitUntilRecorded()
    for _ in 0..<10 { await Task.yield() }
    #expect(await fetcher.callCount == 1)

    await blocker.release()
    let firstResult = try await first.value
    #expect(firstResult.value == "completed")
    _ = try await second.value
    #expect(await fetcher.callCount == 2)
  }

  @Test
  func localRetentionWaitsForTheCoordinatorGateThenRuns() async throws {
    let core = try makeInMemoryCore()
    try core.write { db in
      try db.execute(
        sql: """
          INSERT INTO error_logs (id, source, level, message, created_at)
          VALUES ('old-retention-probe', 'test', 'warn', 'old',
                  '2020-01-01T00:00:00.000Z')
          """)
    }
    let subject = coordinator(pusher: RecordingRecordPusher())
    let blocker = BlockingTerminalOperation()

    let heldOperation = Task {
      try await subject.withQuiescedCloudSync { await blocker.run() }
    }
    await blocker.waitUntilEntered()
    let retention = Task {
      try await subject.runLocalRetentionMaintenance(
        sync: core, activeOutboxCapPolicy: { false })
    }
    for _ in 0..<20 { await Task.yield() }

    #expect(
      try core.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM error_logs WHERE id = 'old-retention-probe'") ?? 0
      } == 1,
      "retention must not mutate sync-adjacent state while the coordinator gate is held")

    await blocker.release()
    _ = try await heldOperation.value
    try await retention.value

    #expect(
      try core.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM error_logs WHERE id = 'old-retention-probe'") ?? 0
      } == 0,
      "the queued retention sweep must run after the gate holder exits")
  }

  @Test
  func queuedRetentionReadsTheFinalActiveOutboxPolicyInsideTheCoordinatorGate() async throws {
    let sync = RecordingRetentionSync()
    let subject = coordinator(pusher: RecordingRecordPusher())
    let blocker = BlockingTerminalOperation()
    let policy = MutableActiveOutboxCapPolicy(includeActiveOutboxCap: true)
    let retentionStarted = TerminalOperationInvocationProbe()

    let heldOperation = Task {
      try await subject.withQuiescedCloudSync { await blocker.run() }
    }
    await blocker.waitUntilEntered()
    let retention = Task {
      await retentionStarted.record()
      try await subject.runLocalRetentionMaintenance(
        sync: sync,
        activeOutboxCapPolicy: { await policy.read() })
    }
    await retentionStarted.waitUntilRecorded()
    for _ in 0..<20 { await Task.yield() }

    #expect(await policy.reads() == 0)
    #expect(sync.policies.isEmpty)

    // The gate holder's temporary Off policy ends before queued maintenance
    // may run. A policy snapshot captured when the request was submitted would
    // incorrectly cap live transport debt here.
    await policy.setIncludeActiveOutboxCap(false)
    await blocker.release()
    _ = try await heldOperation.value
    try await retention.value

    #expect(await policy.reads() == 1)
    #expect(sync.policies == [false])
  }

  @Test
  func liveDataImportAppliesRemoteIdentityBeforeBackupPresenceDecision() async throws {
    let core = try makeInMemoryCore()
    let listID = "01966a3f-7c8b-7d4e-8f3a-00000000c701"
    let fetcher = ScriptedInboundFetcher(
      pages: [
        ScriptedInboundPage(
          records: [try partialRemoteListRecord(descriptor: cloudSyncTestDescriptor)],
          token: Data([0x84]), moreComing: false)
      ])
    let subject = coordinator(pusher: RecordingRecordPusher(), fetcher: fetcher)
    let plan = LorvexImportPlan(entries: [
      LorvexImportPlanEntry(category: .lists, recordCount: 1, isSupported: true)
    ])
    let decoded = LorvexDataImporter.DecodedImport(
      payload: LorvexDataExportPayload(
        lists: [ExportList(id: listID, name: "Stale backup value")]))

    let result = try await CloudSyncDataImportBoundary.apply(
      plan: plan,
      decoded: decoded,
      using: core,
      mode: .live,
      liveCoordinator: subject,
      maintenanceCoordinator: subject)

    #expect(result.summary.totalImported == 0)
    #expect(result.summary.totalSkipped == 1)
    let storedName = try core.read { db in
      try String.fetchOne(db, sql: "SELECT name FROM lists WHERE id = ?", arguments: [listID])
    }
    #expect(storedName == "Committed before retry")
  }

  @Test
  func liveDataImportCannotResurrectARemoteTombstoneFromAStaleBackup() async throws {
    let core = try makeInMemoryCore()
    let listID = "01966a3f-7c8b-7d4e-8f3a-00000000c701"
    let tombstoneEnvelope = try remoteListTombstoneEnvelope(listID: listID)
    if case .failure(let validationError) = tombstoneEnvelope.validate() {
      Issue.record("\(validationError.message)")
    }
    let tombstoneRecord = try remoteListTombstoneRecord(
      descriptor: cloudSyncTestDescriptor, listID: listID)
    #expect(CloudSyncEnvelopeRecord.envelope(from: tombstoneRecord) == tombstoneEnvelope)
    let subject = coordinator(
      pusher: RecordingRecordPusher(),
      fetcher: ScriptedInboundFetcher(
        pages: [
          ScriptedInboundPage(
            records: [tombstoneRecord], token: Data([0x88]), moreComing: false)
        ]))
    let plan = LorvexImportPlan(entries: [
      LorvexImportPlanEntry(category: .lists, recordCount: 1, isSupported: true)
    ])
    let decoded = LorvexDataImporter.DecodedImport(
      payload: LorvexDataExportPayload(
        lists: [ExportList(id: listID, name: "Stale backup list")]))

    let result = try await CloudSyncDataImportBoundary.apply(
      plan: plan, decoded: decoded, using: core, mode: .live,
      liveCoordinator: subject, maintenanceCoordinator: subject)

    #expect(result.preImportSyncReport?.fetchedRecordCount == 1)
    #expect(result.preImportSyncReport?.inbound.applied == 1)
    #expect(result.preImportSyncReport?.inbound.undecodable == 0)
    #expect(result.summary.totalImported == 0)
    #expect(result.summary.totalSkipped == 1)
    #expect(
      try core.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [listID]) ?? 0
      } == 0)
    #expect(
      try core.read { db in
        try Tombstone.getTombstone(db, entityType: EntityName.list, entityId: listID)
      } != nil)
  }

  @Test
  func nonLiveDataImportDoesNotRequireCloudRuntimeReadiness() async throws {
    let core = try makeInMemoryCore()
    let maintenance = coordinator(
      pusher: RecordingRecordPusher(), accountAvailability: .noAccount)
    let result = try await CloudSyncDataImportBoundary.apply(
      plan: LorvexImportPlan(entries: []),
      decoded: LorvexDataImporter.DecodedImport(payload: LorvexDataExportPayload()),
      using: core,
      mode: .off,
      liveCoordinator: nil,
      maintenanceCoordinator: maintenance)

    #expect(result.summary == LorvexImportSummary(results: [], errors: []))
    #expect(result.preImportSyncReport == nil)
  }

  @Test
  func nonLiveDataImportWaitsForTheMaintenanceCoordinatorGate() async throws {
    let core = try makeInMemoryCore()
    let maintenance = coordinator(pusher: RecordingRecordPusher())
    let blocker = BlockingTerminalOperation()
    let listID = "01966a3f-7c8b-7d4e-8f3a-00000000c798"
    let plan = LorvexImportPlan(entries: [
      LorvexImportPlanEntry(category: .lists, recordCount: 1, isSupported: true)
    ])
    let decoded = LorvexDataImporter.DecodedImport(
      payload: LorvexDataExportPayload(
        lists: [ExportList(id: listID, name: "Serialized import")]))

    let maintenanceTask = Task {
      try await maintenance.withQuiescedCloudSync { await blocker.run() }
    }
    await blocker.waitUntilEntered()
    let importTask = Task {
      try await CloudSyncDataImportBoundary.apply(
        plan: plan, decoded: decoded, using: core, mode: .off,
        liveCoordinator: nil, maintenanceCoordinator: maintenance)
    }
    for _ in 0..<20 { await Task.yield() }
    #expect(
      try core.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [listID]) ?? 0
      } == 0)

    await blocker.release()
    _ = try await maintenanceTask.value
    let result = try await importTask.value
    #expect(result.summary.totalImported == 1)
    #expect(
      try core.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [listID]) ?? 0
      } == 1)
  }

  @Test
  func unavailableAccountPerformsNoCloudKitWork() async throws {
    let pusher = RecordingRecordPusher()
    let coordinator = coordinator(
      pusher: pusher, accountAvailability: .noAccount)

    #expect(try await coordinator.runCycle(sync: makeInMemoryCore()) == nil)
    #expect(await pusher.ensureZoneCallCount == 0)
    #expect(await pusher.pushBatchSizes.isEmpty)
  }

  @Test
  func accountFlipDuringInitialGenerationReadCannotPersistDeletedZonePause() async throws {
    let account = MutableAccountIdentifier("account-A")
    let pause = RecordingCloudSyncPauseStore()
    let identities = RecordingAccountIdentityStore(initial: "account-A")
    let pusher = RecordingRecordPusher(
      currentZoneGenerationStateHook: { await account.set("account-B") })
    await pusher.setGenerationState(
      .deleted(
        deletionGeneration: 2,
        retiredZoneNames: [RecordingRecordPusher.readyDescriptor.zoneName],
        modifiedAt: nil))
    let subject = CloudSyncEngineCoordinator(
      accountChecker: StubAccountStatusChecker(),
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(records: []),
      accountIdentifier: account,
      accountIdentityStore: identities,
      accountPauseStore: pause)

    #expect(try await subject.runCycle(sync: makeInMemoryCore()) == nil)
    #expect(await pause.reason == .accountChanged)
    #expect(try await subject.handleAccountChange() == .suppressedDifferentAccount)
    #expect(await pause.reason != .userDeletedZone)
  }

  @Test
  func corruptEntityIsCountedWhileTraversalCursorAdvances() async throws {
    let descriptor = RecordingRecordPusher.readyDescriptor
    let pusher = RecordingRecordPusher()
    let core = try makeInMemoryCore()
    let token = Data([0x7A])
    let subject = coordinator(
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(
        records: [corruptEntityRecord(descriptor: descriptor)],
        serverChangeTokenData: token))

    let report = try #require(try await subject.runCycle(sync: core))

    #expect(report.fetchedRecordCount == 1)
    #expect(report.inbound.undecodable == 1)
    #expect(!report.moreInboundComing)
    let state = try core.cloudTraversalState(
      accountIdentifier: "account-A", zoneIdentifier: descriptor.zoneName)
    #expect(state.baselineWitness?.finalChangeToken == token)
  }

  @Test
  func serverWinnerAppliedDuringPushContributesToCycleInboundReport() async throws {
    let core = try makeInMemoryCore()
    let task = try await core.createTask(title: "Local older title", notes: "")
    let pending = try core.pendingOutbound()
    let localTask = try #require(
      pending.first(where: {
        $0.envelope.entityType == .task && $0.envelope.entityId == task.id
      }))
    let serverVersion = try Hlc.parse("9999913599990_0000_b1c2d3e4b1c2d3e4")
    let serverWinner = SyncEnvelope(
      entityType: localTask.envelope.entityType,
      entityId: localTask.envelope.entityId,
      operation: localTask.envelope.operation,
      version: serverVersion,
      payloadSchemaVersion: localTask.envelope.payloadSchemaVersion,
      payload: localTask.envelope.payload.replacingOccurrences(
        of: "Local older title", with: "Canonical server title"
      ).replacingOccurrences(
        of: localTask.envelope.version.description, with: serverVersion.description),
      deviceId: "server-peer")
    let taskRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityKind.task.asString, entityId: task.id)
    let pusher = RecordingRecordPusher(
      scriptedResultsByRecordName: [
        taskRecordName: CloudSyncPushResult(
          recordName: taskRecordName, succeeded: true,
          serverEnvelopeToApply: serverWinner)
      ])
    let subject = coordinator(pusher: pusher)

    let report = try #require(try await subject.runCycle(sync: core))

    #expect(report.fetchedRecordCount == 0)
    #expect(report.inbound.applied == 1)
    #expect(report.inbound.appliedEntityTypes == [.task])
    #expect((try await core.loadTask(id: task.id)).title == "Canonical server title")
  }

  @Test(arguments: [true, false])
  func calendarRegisterCollisionPublishesJoinedSuccessorInOneDrain(
    localHasWinningContent: Bool
  ) async throws {
    let core = try makeInMemoryCore()
    let eventId = "01966a3f-7c8b-7d4e-8f3a-00000000ca31"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let contentVersion = try Hlc.parse("1711234567200_0000_a1b2c3d4a1b2c3d4")
    let topologyVersion = try Hlc.parse("1711234567300_0000_b1c2d3e4b1c2d3e4")
    let contentWinner = try coordinatorCalendarBaseEnvelope(
      id: eventId, title: "Winning content", startDate: "2026-07-20",
      contentVersion: contentVersion, topologyVersion: base,
      rowVersion: contentVersion, deviceId: "content-device")
    let topologyWinner = try coordinatorCalendarBaseEnvelope(
      id: eventId, title: "Stale content", startDate: "2026-08-20",
      contentVersion: base, topologyVersion: topologyVersion,
      rowVersion: topologyVersion, deviceId: "topology-device")
    let local = localHasWinningContent ? contentWinner : topologyWinner
    let server = localHasWinningContent ? topologyWinner : contentWinner

    #expect(try core.applyInbound([local], undecodable: 0).applied == 1)
    try core.write { db in
      guard let payload = JSONValue.parse(local.payload) else {
        throw CoordinatorRecoveryProbeError.unexpectedFetch
      }
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: local.entityType.asString, entityId: local.entityId,
        payload: payload,
        context: OutboxWriteContext(
          version: local.version.description, deviceId: local.deviceId))
    }
    _ = try #require(
      try core.pendingOutbound().first {
        $0.envelope.entityType == .calendarEvent && $0.envelope.entityId == eventId
      })
    let pusher = SemanticRegisterRetryPusher(
      kind: .calendarBaseRegisters, serverEnvelope: server)
    let subject = coordinator(pusher: pusher)
    let descriptor = RecordingRecordPusher.readyDescriptor
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: descriptor)
    let expectation = CloudSyncGenerationExpectation.ready(descriptor)
    let authorization = AuditRetentionOutboundAuthorization(
      token: "calendar-register-test", accountIdentifier: "account-A",
      zoneName: descriptor.zoneName, frontier: .initial)

    let report = try await subject.pushOutbound(
      sync: core, context: context, expectation: expectation,
      authorization: authorization)
    #expect(report.failed == 0)
    #expect(report.pushed == 1)
    let finalServer = await pusher.currentServerEnvelope()
    guard case .object(let object)? = JSONValue.parse(finalServer.payload) else {
      Issue.record("joined calendar successor must carry an object payload")
      return
    }
    #expect(object["title"] == .string("Winning content"))
    #expect(object["start_date"] == .string("2026-08-20"))
    #expect(object["content_version"] == .string(contentVersion.description))
    #expect(object["recurrence_topology_version"] == .string(topologyVersion.description))
    #expect(finalServer.version > contentVersion)
    #expect(finalServer.version > topologyVersion)
    #expect(try core.pendingOutbound().allSatisfy { $0.envelope.entityId != eventId })

    let next = try await subject.pushOutbound(
      sync: core, context: context, expectation: expectation,
      authorization: authorization)
    #expect(next.pushed == 0)
    #expect(next.failed == 0)
    #expect(await pusher.recordPushCount() == 2)
  }

  @Test
  func forwardCompatibleTaskCollisionPublishesJoinedSuccessorInOneDrainWithoutLosingShadow()
    async throws
  {
    let core = try makeInMemoryCore()
    let taskId = "01966a3f-7c8b-7d4e-8f3a-00000000ca32"
    let base = try Hlc.parse("1711234567100_0000_c1c2d3e4c1c2d3e4")
    let serverSchedule = try Hlc.parse("1711234567200_0000_b1c2d3e4b1c2d3e4")
    let localContent = try Hlc.parse("1711234567300_0000_a1b2c3d4a1b2c3d4")
    let local = try coordinatorTaskRegisterEnvelope(
      id: taskId, title: "Local future content", dueDate: nil,
      contentVersion: localContent, scheduleVersion: base,
      rowVersion: localContent, deviceId: "future-client-device",
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      futureProbe: "preserve-me")
    let server = try coordinatorTaskRegisterEnvelope(
      id: taskId, title: "Stale server content", dueDate: "2026-08-21",
      contentVersion: base, scheduleVersion: serverSchedule,
      rowVersion: serverSchedule, deviceId: "server-schedule-device")

    #expect(try core.applyInbound([local], undecodable: 0).applied == 1)
    try core.write { db in
      guard let payload = JSONValue.parse(local.payload) else {
        throw CoordinatorRecoveryProbeError.unexpectedFetch
      }
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: local.entityType.asString, entityId: local.entityId,
        payload: payload,
        context: OutboxWriteContext(
          version: local.version.description, deviceId: local.deviceId,
          registerIntent: .task(.content)))
    }
    let old = try #require(
      try core.pendingOutbound().first {
        $0.envelope.entityType == .task && $0.envelope.entityId == taskId
      })
    #expect(old.envelope.payloadSchemaVersion == LorvexVersion.payloadSchemaVersion + 1)

    let pusher = SemanticRegisterRetryPusher(
      kind: .taskRegisters, serverEnvelope: server)
    let subject = coordinator(pusher: pusher)
    let descriptor = RecordingRecordPusher.readyDescriptor
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: descriptor)
    let expectation = CloudSyncGenerationExpectation.ready(descriptor)
    let authorization = AuditRetentionOutboundAuthorization(
      token: "future-task-register-test", accountIdentifier: "account-A",
      zoneName: descriptor.zoneName, frontier: .initial)

    let report = try await subject.pushOutbound(
      sync: core, context: context, expectation: expectation,
      authorization: authorization)
    #expect(report.failed == 0)
    #expect(report.pushed == 1)
    let finalServer = await pusher.currentServerEnvelope()
    #expect(finalServer.version > localContent)
    #expect(finalServer.payloadSchemaVersion == LorvexVersion.payloadSchemaVersion + 1)
    guard case .object(let successorObject)? = JSONValue.parse(finalServer.payload) else {
      Issue.record("joined future task successor must carry an object payload")
      return
    }
    #expect(successorObject["future_probe"] == .string("preserve-me"))
    #expect(successorObject["title"] == .string("Local future content"))
    #expect(successorObject["due_date"] == .string("2026-08-21"))
    #expect(successorObject["content_version"] == .string(localContent.description))
    #expect(successorObject["schedule_version"] == .string(serverSchedule.description))

    #expect(try core.pendingOutbound().allSatisfy { $0.envelope.entityId != taskId })

    let next = try await subject.pushOutbound(
      sync: core, context: context, expectation: expectation,
      authorization: authorization)
    #expect(next.pushed == 0)
    #expect(next.failed == 0)
    #expect(await pusher.recordPushCount() == 2)
  }

  @Test
  func generationCrossingAfterPushConsumesNoLocalResults() async throws {
    let core = try makeInMemoryCore()
    let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000b701"
    let localVersion = try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
    let serverVersion = try Hlc.parse("1811234567890_0000_b1c2d3e4b1c2d3e4")
    let local = SyncEnvelope(
      entityType: .task, entityId: entityId, operation: .upsert,
      version: localVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload:
        #"{"created_at":"2026-05-23T12:00:00.000Z","list_id":"inbox","status":"open","title":"Local pending","updated_at":"2026-05-23T12:00:00.000Z"}"#,
      deviceId: "local-device")
    let serverWinner = SyncEnvelope(
      entityType: .task, entityId: entityId, operation: .upsert,
      version: serverVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload:
        #"{"created_at":"2026-05-23T12:00:00.000Z","list_id":"inbox","status":"open","title":"Server winner","updated_at":"2026-05-23T12:00:00.000Z"}"#,
      deviceId: "server-device")
    try core.write { db in try seedOutboxEnvelope(db, local) }
    let outboxId = try #require(try core.pendingOutbound().first?.outboxId)
    let recordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityKind.task.asString, entityId: entityId)
    let pusher = RecordingRecordPusher(
      scriptedResultsByRecordName: [
        recordName: CloudSyncPushResult(
          recordName: recordName, succeeded: true,
          serverEnvelopeToApply: serverWinner)
      ],
      crossGenerationAfterPush: true)
    let subject = coordinator(pusher: pusher)
    let descriptor = RecordingRecordPusher.readyDescriptor
    let authorization = AuditRetentionOutboundAuthorization(
      token: "unused-non-audit-authorization", accountIdentifier: "account-A",
      zoneName: descriptor.zoneName, frontier: .initial)

    await #expect(throws: CloudSyncGenerationBoundaryCrossed.self) {
      try await subject.pushOutbound(
        sync: core,
        context: CloudSyncGenerationContext(
          accountIdentifier: "account-A", descriptor: descriptor),
        expectation: .ready(descriptor), authorization: authorization)
    }

    let localState = try core.read { db in
      (
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [entityId]) ?? -1,
        try Row.fetchOne(
          db,
          sql:
            "SELECT retry_count, last_retry_at, last_error, synced_at FROM sync_outbox WHERE id = ?",
          arguments: [outboxId])
      )
    }
    #expect(localState.0 == 0)
    let row = try #require(localState.1)
    #expect(row["retry_count"] as Int64 == 0)
    #expect((row["last_retry_at"] as String?) == nil)
    #expect((row["last_error"] as String?) == nil)
    #expect((row["synced_at"] as String?) == nil)
  }

  @Test
  func staleCollisionCapabilityDoesNotCacheReturnedServerChangeTag() async throws {
    let core = try makeInMemoryCore()
    let descriptor = RecordingRecordPusher.readyDescriptor
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    _ = try core.activateAuditRetentionAccount(
      accountIdentifier: "account-A", zoneName: descriptor.zoneName)
    let task = try await core.createTask(title: "In-flight old intent", notes: "")
    let old = try #require(
      try core.pendingOutbound().first { $0.envelope.entityId == task.id })
    let recordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityKind.task.asString, entityId: task.id)
    let serverFloor = try Hlc(
      physicalMs: old.envelope.version.physicalMs + 1, counter: 0,
      deviceSuffix: "eeeeeeeeeeeeeeee")
    let receipt = CloudSyncSystemFieldsReceipt(
      recordName: recordName, archivedSystemFields: Data([0x01, 0x02]))
    let pusher = OneShotCollisionPusher(
      recordName: recordName,
      collision: .corruptServerSlot(serverVersionFloor: serverFloor),
      receipt: receipt,
      firstPushHook: {
        _ = try await core.updateTask(
          id: task.id, title: "New local intent", notes: "", priority: .p2,
          estimatedMinutes: nil, dueDate: nil, plannedDate: nil,
          availableFrom: nil, tags: [], dependsOn: [])
      })
    let subject = coordinator(pusher: pusher)
    let authorization = try core.authorizeAuditRetentionOutbound(
      verifiedRemoteFrontier: .initial,
      forAccountIdentifier: "account-A", zoneName: descriptor.zoneName)

    let report = try await subject.pushOutbound(
      sync: core,
      context: CloudSyncGenerationContext(
        accountIdentifier: "account-A", descriptor: descriptor),
      expectation: .ready(descriptor), authorization: authorization)

    #expect(try core.pendingOutbound().allSatisfy { $0.envelope.entityId != task.id })
    #expect((try await core.loadTask(id: task.id)).title == "New local intent")
    #expect(report.failed == 0)
    let attempts = await pusher.attemptedTargetEnvelopes()
    let accepted = await pusher.acceptedTargetRecords()
    #expect(attempts.count == 2)
    #expect(accepted.count == 1)
    let successor = try #require(accepted.first)
    #expect(successor.entityType == .task)
    #expect(successor.entityId == task.id)
    #expect(successor.operation == .upsert)
    #expect(successor.version > old.envelope.version)
    guard case .object(let successorObject)? = JSONValue.parse(successor.payload) else {
      Issue.record("accepted concurrent task successor must carry an object payload")
      return
    }
    #expect(successorObject["title"] == .string("New local intent"))
    #expect(successorObject["version"] == .string(successor.version.description))
    #expect(report.pushed >= accepted.count)
    #expect(await pusher.reconciledConflictReceiptBatches.allSatisfy(\.isEmpty))
  }

  @Test
  func pushAggregatesServerWinnersAcrossChunksWithoutClaimingOrdinaryPushes() async throws {
    let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    var scripted: [String: CloudSyncPushResult] = [:]
    var pending: [PendingOutboundEnvelope] = []

    for index in 0...201 {
      let id = String(format: "01966a3f-7c8b-7d4e-8f3a-%012d", index)
      let localVersion = try Hlc.parse(
        String(format: "1711234%06d_0000_a1b2c3d4a1b2c3d4", index))
      let localPayload = try coordinatorTaskPayload(
        id: id, title: "Local \(index)", version: localVersion.description,
        timestamp: "2026-05-23T12:00:00.000Z")
      let local = SyncEnvelope(
        entityType: .task, entityId: id, operation: .upsert,
        version: localVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: localPayload, deviceId: "local-device")
      pending.append(PendingOutboundEnvelope(outboxId: Int64(index + 1), envelope: local))

      // Leave the final row as an ordinary confirmed push. It must contribute
      // to `pushed`, but never to the inbound apply counts or changed-kind set.
      if index < 201 {
        let recordName = CloudSyncEnvelopeRecord.recordName(
          entityType: EntityKind.task.asString, entityId: id)
        let serverVersion = try Hlc.parse(
          String(format: "1811234%06d_0000_b1c2d3e4b1c2d3e4", index))
        let serverPayload = try coordinatorTaskPayload(
          id: id, title: "Server \(index)", version: serverVersion.description,
          timestamp: "2026-05-23T12:00:00.000Z")
        let server = SyncEnvelope(
          entityType: .task, entityId: id, operation: .upsert,
          version: serverVersion,
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: serverPayload, deviceId: "server-peer")
        scripted[recordName] = CloudSyncPushResult(
          recordName: recordName, succeeded: true,
          serverEnvelopeToApply: server)
      }
    }
    core.outboxPending = pending
    let pusher = RecordingRecordPusher(scriptedResultsByRecordName: scripted)
    let descriptor = RecordingRecordPusher.readyDescriptor
    let subject = coordinator(pusher: pusher)
    let authorization = AuditRetentionOutboundAuthorization(
      token: "test-authorization", accountIdentifier: "account-A",
      zoneName: descriptor.zoneName, frontier: .initial)

    let report = try await subject.pushOutbound(
      sync: core,
      context: CloudSyncGenerationContext(
        accountIdentifier: "account-A", descriptor: descriptor),
      expectation: .ready(descriptor), authorization: authorization)

    #expect(await pusher.pushBatchSizes == [200, 2])
    #expect(report.pushed == 202)
    #expect(report.failed == 0)
    #expect(report.inbound.applied == 201)
    #expect(report.inbound.appliedEntityTypes == [.task])
    #expect(core.appliedInboundBatchCount() == 1)
  }

  @Test
  func outboundDrainPublishesTheNextCappedFifoPageInTheSameCall() async throws {
    let core = try makeInMemoryCore()
    try core.write { db in
      for index in 0...Int(Outbox.maxPendingFetch) {
        try seedOutboxEnvelope(
          db,
          try coordinatorTaskEnvelope(
            id: coordinatorFixtureID(10_000 + index),
            title: "Paged outbound \(index)", listID: "inbox"))
      }
    }
    #expect(try core.pendingOutbound().count == Int(Outbox.maxPendingFetch))

    let pusher = RecordingRecordPusher()
    let subject = coordinator(pusher: pusher)
    let descriptor = RecordingRecordPusher.readyDescriptor
    let report = try await subject.pushOutbound(
      sync: core,
      context: CloudSyncGenerationContext(
        accountIdentifier: "account-A", descriptor: descriptor),
      expectation: .ready(descriptor),
      authorization: AuditRetentionOutboundAuthorization(
        token: "paged-outbound-test", accountIdentifier: "account-A",
        zoneName: descriptor.zoneName, frontier: .initial))

    #expect(report.pushed == Int(Outbox.maxPendingFetch) + 1)
    #expect(report.failed == 0)
    #expect(await pusher.pushBatchSizes == [200, 200, 200, 200, 200, 1])
    #expect(try core.pendingOutbound().isEmpty)
  }

  @Test
  func outboundDrainCeilingReturnsSuccessfulContinuationWithoutBlockingTerminalInboundProof()
    async throws
  {
    let core = try makeInMemoryCore()
    try core.write { db in
      for index in 0...Int(Outbox.maxPendingFetch) {
        try seedOutboxEnvelope(
          db,
          try coordinatorTaskEnvelope(
            id: coordinatorFixtureID(45_000 + index),
            title: "Bounded outbound \(index)", listID: "inbox"))
      }
    }

    let pusher = RecordingRecordPusher()
    let fetcher = ScriptedMoreComingFetcher(
      moreComingScript: [false, false], tokenData: Data([0x82]))
    var subject = coordinator(pusher: pusher, fetcher: fetcher)
    subject.outboundDrainIterationLimit = 1

    let terminal = try await subject.withTerminalInboundDrain(core: core) {
      "authorized"
    }

    #expect(terminal.value == "authorized")
    #expect(terminal.postTerminalSyncFailure == nil)
    #expect(terminal.drainReport.pushedRecordCount == Int(Outbox.maxPendingFetch))
    #expect(terminal.drainReport.failedPushCount == 0)
    #expect(terminal.drainReport.moreInboundComing == false)
    #expect(terminal.drainReport.moreOutboundComing)
    #expect(terminal.drainReport.moreWorkComing)
    #expect(try core.pendingOutbound().count == 1)

    let continuation = try #require(try await subject.runCycle(sync: core))
    #expect(continuation.pushedRecordCount == 1)
    #expect(continuation.failedPushCount == 0)
    #expect(continuation.moreInboundComing == false)
    #expect(continuation.moreOutboundComing == false)
    #expect(continuation.moreWorkComing == false)
    #expect(try core.pendingOutbound().isEmpty)
    #expect(await pusher.pushBatchSizes == [200, 200, 200, 200, 200, 1])
  }

  @Test
  func outboundDrainScansPastAFullPoisonedRawPage() async throws {
    let core = try makeInMemoryCore()
    let poisonCount = Int(Outbox.maxPendingFetch)
    let healthy = try coordinatorTaskEnvelope(
      id: coordinatorFixtureID(41_500), title: "Healthy after poison", listID: "inbox")
    try core.write { db in
      try seedCloudSyncCorruption(db) {
        for index in 0..<poisonCount {
          try seedOutboxEnvelope(
            db,
            try coordinatorTaskEnvelope(
              id: coordinatorFixtureID(40_000 + index),
              title: "Poison prefix \(index)", listID: "inbox"))
          try db.execute(
            sql: "UPDATE sync_outbox SET operation = 'future_operation' WHERE id = ?",
            arguments: [db.lastInsertedRowID])
        }
      }
      try seedOutboxEnvelope(db, healthy)
    }

    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let report = try await coordinator(pusher: pusher).pushOutbound(
      sync: core,
      context: CloudSyncGenerationContext(
        accountIdentifier: "account-A", descriptor: descriptor),
      expectation: .ready(descriptor),
      authorization: AuditRetentionOutboundAuthorization(
        token: "poison-prefix-test", accountIdentifier: "account-A",
        zoneName: descriptor.zoneName, frontier: .initial))

    #expect(report.pushed == 1)
    #expect(report.failed == 0)
    #expect(await pusher.pushBatchSizes == [1])
    #expect(
      try core.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE disposition = ?",
          arguments: [Outbox.Disposition.retryWait.rawValue]) ?? 0
      } == poisonCount)
    #expect(try core.pendingOutbound().isEmpty)
  }

  @Test
  func outboundDrainScansPastAFullFutureHeldRawPage() async throws {
    let core = try makeInMemoryCore()
    let heldCount = Int(Outbox.maxPendingFetch)
    let heldVersion = "1811234567890_0000_f1e2d3c4f1e2d3c4"
    let healthy = try coordinatorTaskEnvelope(
      id: coordinatorFixtureID(43_500), title: "Healthy after holds", listID: "inbox")
    try core.write { db in
      for index in 0..<heldCount {
        let local = try coordinatorTaskEnvelope(
          id: coordinatorFixtureID(42_000 + index),
          title: "Future-held prefix \(index)", listID: "inbox")
        try seedOutboxEnvelope(db, local)

        // Normal inbound/staging paths fence atomically. Seed the durable
        // provenance without that eager fence to exercise getPending's
        // defense-in-depth recovery after an invariant-breaking older build.
        let raw = RawEnvelopeFields(
          entityType: EntityName.task, entityId: local.entityId,
          operation: "future_upsert", version: heldVersion,
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
          payload: #"{"future_shape":true}"#, deviceId: "future-peer")
        try db.execute(
          sql: """
            INSERT INTO sync_pending_inbox
              (envelope, reason, missing_entity_type, missing_entity_id,
               envelope_entity_type, envelope_entity_id, envelope_version,
               first_attempted_at, last_attempted_at, attempt_count)
            VALUES (?, 'entity_type_too_new', NULL, NULL, ?, ?, ?,
                    '2026-07-15T00:00:00.000Z',
                    '2026-07-15T00:00:00.000Z', 1)
            """,
          arguments: [
            try raw.envelopeWireJSON(), raw.entityType, raw.entityId, raw.version,
          ])
      }
      try seedOutboxEnvelope(db, healthy)
    }

    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let report = try await coordinator(pusher: pusher).pushOutbound(
      sync: core,
      context: CloudSyncGenerationContext(
        accountIdentifier: "account-A", descriptor: descriptor),
      expectation: .ready(descriptor),
      authorization: AuditRetentionOutboundAuthorization(
        token: "future-prefix-test", accountIdentifier: "account-A",
        zoneName: descriptor.zoneName, frontier: .initial))

    #expect(report.pushed == 1)
    #expect(report.failed == 0)
    #expect(await pusher.pushBatchSizes == [1])
    #expect(
      try core.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE disposition = ?",
          arguments: [Outbox.Disposition.futureRecordHold.rawValue]) ?? 0
      } == heldCount)
    #expect(try core.pendingOutbound().isEmpty)
  }

  @Test
  func outboundDrainUsesOneRetrySnapshotAcrossEveryCursorPage() async throws {
    let core = try makeInMemoryCore()
    let scanTimestamp = "2020-01-01T00:00:00.000Z"
    let due = "2020-01-01T00:00:01.000Z"
    let deferred = try coordinatorTaskEnvelope(
      id: coordinatorFixtureID(44_000), title: "Low-id deferred", listID: "inbox")
    try core.write { db in
      try seedOutboxEnvelope(db, deferred)
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = ?, disposition = ?, next_retry_at = ?,
              recovery_round = 1
          WHERE id = ?
          """,
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.retryWait.rawValue, due,
          db.lastInsertedRowID,
        ])
      for index in 0...Int(Outbox.maxPendingFetch) {
        try seedOutboxEnvelope(
          db,
          try coordinatorTaskEnvelope(
            id: coordinatorFixtureID(44_100 + index),
            title: "Later page \(index)", listID: "inbox"))
      }
    }

    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let report = try await coordinator(pusher: pusher).pushOutbound(
      sync: core,
      context: CloudSyncGenerationContext(
        accountIdentifier: "account-A", descriptor: descriptor),
      expectation: .ready(descriptor),
      authorization: AuditRetentionOutboundAuthorization(
        token: "fixed-retry-snapshot-test", accountIdentifier: "account-A",
        zoneName: descriptor.zoneName, frontier: .initial),
      outboxScanTimestamp: scanTimestamp)

    #expect(report.pushed == Int(Outbox.maxPendingFetch) + 1)
    #expect(report.failed == 0)
    #expect(await pusher.pushBatchSizes == [200, 200, 200, 200, 200, 1])
    let deferredState = try core.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT disposition, next_retry_at
          FROM sync_outbox WHERE entity_id = ? AND synced_at IS NULL
          """,
        arguments: [deferred.entityId])
    }
    #expect(
      deferredState?["disposition"] as String?
        == Outbox.Disposition.retryWait.rawValue)
    #expect(deferredState?["next_retry_at"] as String? == due)
    let expectedDue = try #require(SyncTimestamp.parse(due)).date
    let actualDue = try core.read { db in try Outbox.earliestRetryAt(db) }
    #expect(actualDue == expectedDue)
  }

  @Test
  func outboundFixedPointDoesNotRetryAFailedRowInsideTheSameDrain() async throws {
    let core = try makeInMemoryCore()
    let failedEnvelope = try coordinatorTaskEnvelope(
      id: coordinatorFixtureID(20_001), title: "Fails once", listID: "inbox")
    let successfulEnvelope = try coordinatorTaskEnvelope(
      id: coordinatorFixtureID(20_002), title: "Succeeds", listID: "inbox")
    try core.write { db in
      try seedOutboxEnvelope(db, failedEnvelope)
      try seedOutboxEnvelope(db, successfulEnvelope)
    }
    let failedRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: failedEnvelope.entityType.asString,
      entityId: failedEnvelope.entityId)
    let pusher = RecordingRecordPusher(failingRecordNames: [failedRecordName])
    let subject = coordinator(pusher: pusher)
    let descriptor = RecordingRecordPusher.readyDescriptor

    let report = try await subject.pushOutbound(
      sync: core,
      context: CloudSyncGenerationContext(
        accountIdentifier: "account-A", descriptor: descriptor),
      expectation: .ready(descriptor),
      authorization: AuditRetentionOutboundAuthorization(
        token: "failed-row-cursor-test", accountIdentifier: "account-A",
        zoneName: descriptor.zoneName, frontier: .initial))

    #expect(report.pushed == 1)
    #expect(report.failed == 1)
    #expect(await pusher.pushBatchSizes == [2])
    let remaining = try core.pendingOutbound()
    #expect(remaining.count == 1)
    #expect(remaining.first?.envelope.entityId == failedEnvelope.entityId)
  }

  @Test
  func cycleReportsTheDurableDeferredOutboxWake() async throws {
    let core = try makeInMemoryCore()
    let envelope = try coordinatorTaskEnvelope(
      id: coordinatorFixtureID(20_003), title: "Deferred retry", listID: "inbox")
    let due = "2026-08-01T01:02:03.000Z"
    try core.write { db in
      try seedOutboxEnvelope(db, envelope)
      let id = db.lastInsertedRowID
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = ?, disposition = ?, next_retry_at = ?, recovery_round = 1
          WHERE id = ?
          """,
        arguments: [Outbox.maxRetries, Outbox.Disposition.retryWait.rawValue, due, id])
    }

    let report = try #require(
      try await coordinator(pusher: RecordingRecordPusher())
        .runDrainingCycle(core: core))
    let expectedRetryAt = try #require(SyncTimestamp.parse(due)).date

    #expect(report.nextDeferredRetryAt == expectedRetryAt)
  }

  @Test
  func readyRetentionRepublishesAConcurrentLocalNewerPolicy() async throws {
    let core = try makeInMemoryCore()
    let descriptor = RecordingRecordPusher.readyDescriptor
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    _ = try core.activateAuditRetentionAccount(
      accountIdentifier: "account-A", zoneName: descriptor.zoneName)
    _ = try await core.setPreference(
      key: PreferenceKeys.prefAiChangelogRetentionPolicy,
      value: ChangelogRetentionPolicy.days(30).wireValue)
    let pusher = RecordingRecordPusher(remoteRetentionMetadata: .initial)
    let subject = coordinator(pusher: pusher)
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: descriptor)

    let prepared = try await subject.prepareReadyRetention(
      sync: core, context: context, expectation: .ready(descriptor),
      boundaryGuard: { true })

    #expect(prepared.metadata.policy == .days(30))
    #expect(prepared.authorization.frontier == prepared.metadata.frontier)
    #expect(await pusher.currentRemoteRetentionMetadata() == prepared.metadata)
    #expect((await pusher.proposedRetentionMetadata).last == prepared.metadata)
  }

  @Test
  func readyRetentionAuthorizesTheExactConcurrentRemoteMergeWinner() async throws {
    let core = try makeInMemoryCore()
    let descriptor = RecordingRecordPusher.readyDescriptor
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    _ = try core.activateAuditRetentionAccount(
      accountIdentifier: "account-A", zoneName: descriptor.zoneName)
    let remoteWinner = CloudSyncAuditRetentionMetadata(
      frontier: AuditRetentionFrontierValue(epoch: 1), policy: .off,
      policyVersion: "9999913599990_0000_b1c2d3e4b1c2d3e4",
      policyAuthorizedEpoch: 1)
    let pusher = RecordingRecordPusher(
      remoteRetentionMetadata: .initial,
      scriptedRetentionMergeResults: [remoteWinner])
    let subject = coordinator(pusher: pusher)
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: descriptor)

    let prepared = try await subject.prepareReadyRetention(
      sync: core, context: context, expectation: .ready(descriptor),
      boundaryGuard: { true })

    #expect(prepared.metadata == remoteWinner)
    #expect(prepared.authorization.frontier == remoteWinner.frontier)
    let local = try #require(
      try core.auditRetentionState(forAccountIdentifier: "account-A"))
    #expect(local.frontier == remoteWinner.frontier)
    #expect(local.confirmedFrontier == remoteWinner.frontier)
    #expect(local.policy == remoteWinner.policy)
    #expect(local.policyVersion == remoteWinner.policyVersion)
  }

  @Test
  func postReadyCandidateRetentionDriftIsPreservedAndRepublished() async throws {
    let core = try makeInMemoryCore()
    let source = RecordingRecordPusher.readyDescriptor
    let cloudBinding = try core.claimCloudTraversalAccount(
      accountIdentifier: "account-A")
    _ = try core.activateAuditRetentionAccount(
      accountIdentifier: "account-A", zoneName: source.zoneName)
    let lease = CloudSyncZoneRebuildLease(
      identifier: "post-ready-retention-drift",
      ownerIdentifier: cloudBinding.databaseInstanceIdentifier,
      epoch: source.epoch + 1, generationID: "retention-drift-generation",
      candidateZoneName: "LorvexData-e2-retention-drift-generation")
    let pusher = RecordingRecordPusher(
      completeZoneRebuildHook: {
        _ = try await core.setPreference(
          key: PreferenceKeys.prefAiChangelogRetentionPolicy,
          value: ChangelogRetentionPolicy.days(30).wireValue)
      })
    await pusher.setGenerationState(
      .rebuilding(
        lease: lease, previousActive: source, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let subject = coordinator(
      pusher: pusher,
      fetcher: RecordingPusherRemoteChangeFetcher(pusher: pusher))

    _ = try #require(try await subject.runCycle(sync: core))

    let published = try #require(
      (try await pusher.currentZoneGenerationState())?.activeDescriptor)
    let local = try #require(
      try core.auditRetentionState(forAccountIdentifier: "account-A"))
    #expect(try core.auditRetentionActiveZoneName() == published.zoneName)
    #expect(local.policy == .days(30))
    #expect(await pusher.currentRemoteRetentionMetadata().policy == .days(30))
    #expect((await pusher.proposedRetentionMetadata).last?.policy == .days(30))
  }

  @Test
  func predecessorExpiryReachesTerminalBeforeCandidateCaptureAndKeepsTheSameWitness()
    async throws
  {
    let core = try makeInMemoryCore()
    let source = RecordingRecordPusher.readyDescriptor
    let cloudBinding = try core.claimCloudTraversalAccount(
      accountIdentifier: "account-A")
    let lease = CloudSyncZoneRebuildLease(
      identifier: "predecessor-expiry-rebuild",
      ownerIdentifier: cloudBinding.databaseInstanceIdentifier,
      epoch: source.epoch + 1, generationID: "predecessor-expiry-generation",
      candidateZoneName: "LorvexData-e2-predecessor-expiry-generation")
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(
      .rebuilding(
        lease: lease, previousActive: source, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let fetcher = ExpiringPredecessorFetcher(
      previousZoneName: source.zoneName, pusher: pusher)
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await subject.runCycle(sync: core))

    let checkpoints = await fetcher.previousCheckpoints
    #expect(checkpoints.count == 4)
    #expect(checkpoints[0] == nil)
    #expect(checkpoints[1]?.serverChangeTokenData == Data([0x61]))
    #expect(checkpoints[2] == nil)
    #expect(checkpoints[3]?.serverChangeTokenData == Data([0x62]))
    let traversalIdentifiers = await fetcher.previousTraversalIdentifiers
    let recoveredWitnesses = traversalIdentifiers.prefix(3).compactMap { $0 }
    #expect(Set(recoveredWitnesses).count == 1)
    let events = await fetcher.events
    let candidateIndex = try #require(events.firstIndex(of: "candidate"))
    let predecessorTerminalIndex = try #require(events.firstIndex(of: "previous-3"))
    #expect(candidateIndex > predecessorTerminalIndex)
    guard case .ready? = try await pusher.currentZoneGenerationState() else {
      Issue.record("candidate must publish only after predecessor recovery reaches terminal")
      return
    }
  }

  @Test
  func missingPredecessorResumesAnAlreadyClaimedRebuildAfterProcessRestart() async throws {
    let core = try makeInMemoryCore()
    let source = RecordingRecordPusher.readyDescriptor
    let binding = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let localTask = try await core.createTask(title: "Recovered local seed", notes: "")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }
    let lease = CloudSyncZoneRebuildLease(
      identifier: "missing-predecessor-rebuild",
      ownerIdentifier: binding.databaseInstanceIdentifier,
      epoch: source.epoch + 1, generationID: "missing-predecessor-generation",
      candidateZoneName: "LorvexData-e2-missing-predecessor-generation")
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(
      .rebuilding(
        lease: lease, previousActive: source, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let fetcher = MissingPredecessorFetcher(
      previousZoneName: source.zoneName, pusher: pusher)
    let resumedCoordinator = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await resumedCoordinator.runCycle(sync: core))

    #expect(try core.isReseedRequired() == false)
    #expect(await fetcher.previousFetchCount == 2)
    #expect(await fetcher.candidateFetchCount == 2)
    let taskRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityName.task, entityId: localTask.id)
    #expect((await pusher.rebuildingPushedRecordNames).contains(taskRecordName))
    guard case .ready? = try await pusher.currentZoneGenerationState() else {
      Issue.record("a remotely absent predecessor must not strand a claimed rebuild")
      return
    }
  }

  @Test
  func missingCompactedPredecessorReleasesAuthoritativeFenceAndFinishesRebuild()
    async throws
  {
    let core = try makeInMemoryCore()
    var source = RecordingRecordPusher.readyDescriptor
    source.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let binding = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let localTask = try await core.createTask(title: "Only surviving seed", notes: "")
    let lease = CloudSyncZoneRebuildLease(
      identifier: "missing-compacted-predecessor-rebuild",
      ownerIdentifier: binding.databaseInstanceIdentifier,
      epoch: source.epoch + 1,
      generationID: "missing-compacted-predecessor-generation",
      candidateZoneName: "LorvexData-e2-missing-compacted-predecessor-generation")
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(
      .rebuilding(
        lease: lease, previousActive: source, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let fetcher = MissingPredecessorFetcher(
      previousZoneName: source.zoneName, pusher: pusher)
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await subject.runCycle(sync: core))

    #expect(try core.authoritativeSnapshotSession() == nil)
    let taskRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityName.task, entityId: localTask.id)
    #expect((await pusher.rebuildingPushedRecordNames).contains(taskRecordName))
    guard case .ready? = try await pusher.currentZoneGenerationState() else {
      Issue.record("a physically missing compacted predecessor must not wedge the rebuild")
      return
    }
  }

  @Test
  func missingPredecessorIsAcceptedOnlyWhileTheExactRebuildLeaseStillControls() async throws {
    let core = try makeInMemoryCore()
    let source = RecordingRecordPusher.readyDescriptor
    let binding = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let lease = CloudSyncZoneRebuildLease(
      identifier: "stale-missing-predecessor-rebuild",
      ownerIdentifier: binding.databaseInstanceIdentifier,
      epoch: source.epoch + 1, generationID: "stale-missing-predecessor-generation",
      candidateZoneName: "LorvexData-e2-stale-missing-predecessor-generation")
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(
      .rebuilding(
        lease: lease, previousActive: source, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let fetcher = MissingPredecessorFetcher(
      previousZoneName: source.zoneName, pusher: pusher,
      invalidateBoundaryBeforeError: true)
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    #expect(try await subject.runCycle(sync: core) == nil)

    #expect(await fetcher.previousFetchCount == 1)
    #expect(await fetcher.candidateFetchCount == 0)
    #expect(await pusher.ensureZoneCallCount == 0)
    guard case .deleted? = try await pusher.currentZoneGenerationState() else {
      Issue.record("the newer terminal control state must remain authoritative")
      return
    }
  }

  @Test
  func persistentPredecessorFailureResetsItsTraversalWithoutRotatingTheCandidate()
    async throws
  {
    let core = try makeInMemoryCore()
    let source = RecordingRecordPusher.readyDescriptor
    let cloudBinding = try core.claimCloudTraversalAccount(
      accountIdentifier: "account-A")
    let lease = CloudSyncZoneRebuildLease(
      identifier: "predecessor-failure-rebuild",
      ownerIdentifier: cloudBinding.databaseInstanceIdentifier,
      epoch: source.epoch + 1, generationID: "predecessor-failure-generation",
      candidateZoneName: "LorvexData-e2-predecessor-failure-generation")
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(
      .rebuilding(
        lease: lease, previousActive: source, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let failure = CloudSyncPerRecordFetchFailure(
      failedRecordCount: 1, failedRecordNames: ["poisoned-predecessor-record"],
      kind: .persistent, checkpointFingerprint: "predecessor-baseline")
    let fetcher = PerRecordFailureFetcher(failure: failure)
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    for expectedCallCount in 1...3 {
      await #expect(throws: CloudSyncPerRecordFetchFailure.self) {
        try await subject.runCycle(sync: core)
      }
      #expect(await fetcher.callCount == expectedCallCount)
    }

    let progress = try #require(
      try core.cloudTraversalState(
        accountIdentifier: "account-A", zoneIdentifier: source.zoneName
      ).progress)
    #expect(progress.mode == .baseline)
    #expect(progress.nextPageIndex == 0)
    #expect(progress.continuationToken == nil)
    #expect(try core.isReseedRequired() == false)
    guard
      case .rebuilding(let currentLease, _, _, _, _)? =
        try await pusher.currentZoneGenerationState()
    else {
      Issue.record("the existing candidate lease must remain claimed")
      return
    }
    #expect(currentLease == lease)
  }

  @Test
  func readyCycleRetriesRetiredZoneCleanupAfterTransientFailure() async throws {
    let pusher = RecordingRecordPusher(deleteZoneFailuresBeforeSuccess: 1)
    let descriptor = RecordingRecordPusher.readyDescriptor
    await pusher.setGenerationState(
      .ready(
        descriptor: descriptor,
        retiredZoneNames: ["LorvexData-e0-retired-generation"]))
    let core = try makeInMemoryCore()
    let coordinator = coordinator(pusher: pusher)

    let first = try #require(try await coordinator.runCycle(sync: core))
    #expect(first.moreInboundComing == false)
    #expect(await pusher.deleteZoneCallCount == 1)
    guard
      case .ready(_, let retainedAfterFailure, _)? =
        try await pusher.currentZoneGenerationState()
    else {
      Issue.record("expected ready generation")
      return
    }
    #expect(retainedAfterFailure == ["LorvexData-e0-retired-generation"])

    let second = try #require(try await coordinator.runCycle(sync: core))
    #expect(second.moreInboundComing == false)
    #expect(await pusher.deleteZoneCallCount == 2)
    guard
      case .ready(_, let retainedAfterRetry, _)? =
        try await pusher.currentZoneGenerationState()
    else {
      Issue.record("expected ready generation")
      return
    }
    #expect(retainedAfterRetry.isEmpty)
  }

  @Test
  func generationChangeDuringCycleIsAQuietRetryNotAConfirmation() async throws {
    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let fetcher = SideEffectOnFetchRemoteChangeFetcher {
      await pusher.setGenerationState(
        .deleted(
          deletionGeneration: descriptor.epoch + 1,
          retiredZoneNames: [descriptor.zoneName], modifiedAt: nil))
    }
    let coordinator = coordinator(pusher: pusher, fetcher: fetcher)

    #expect(try await coordinator.runCycle(sync: makeInMemoryCore()) == nil)
    #expect(await pusher.pushBatchSizes.isEmpty)
  }

  @Test
  func candidateUploadAndReadbackResumeExactDurableProgressAfterCrash() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let fetcher = CrashAfterFirstCandidateReadbackPageFetcher(pusher: pusher)
    let coordinator = coordinator(pusher: pusher, fetcher: fetcher)
    let core = try makeInMemoryCore()
    for index in 0..<4 {
      _ = try await core.createTask(title: "Captured \(index)", notes: "")
    }

    await #expect(throws: GenerationReadbackCrash.self) {
      try await coordinator.runCycle(sync: core)
    }
    let interrupted = try #require(try core.currentGenerationSnapshotStaging())
    #expect(interrupted.progress.uploadNextOrdinal == interrupted.manifest.recordCount)
    #expect(interrupted.progress.readbackPageIndex == 1)
    #expect(interrupted.progress.readbackContinuationToken == Data([1]))
    #expect(interrupted.progress.readbackWitnessObserved)
    let rebuildingPushCount = await pusher.rebuildingPushedRecordNames.count

    _ = try #require(try await coordinator.runCycle(sync: core))

    #expect(try core.currentGenerationSnapshotStaging() == nil)
    #expect(await pusher.rebuildingPushedRecordNames.count == rebuildingPushCount)
    guard case .ready? = try await pusher.currentZoneGenerationState() else {
      Issue.record("the exact interrupted candidate should publish on resume")
      return
    }
  }

  @Test
  func candidateReadbackExpiryRestartsFromNilWithoutReuploadingOrReplacingTheLease()
    async throws
  {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let fetcher = ExpiringCandidateReadbackFetcher(pusher: pusher)
    let subject = coordinator(pusher: pusher, fetcher: fetcher)
    let core = try makeInMemoryCore()
    for index in 0..<4 {
      _ = try await core.createTask(title: "Candidate expiry \(index)", notes: "")
    }

    _ = try #require(try await subject.runCycle(sync: core))

    let checkpoints = await fetcher.candidateCheckpoints
    #expect(checkpoints.count == 3)
    #expect(checkpoints[0] == nil)
    #expect(checkpoints[1]?.serverChangeTokenData == Data([0x41]))
    #expect(checkpoints[2] == nil)
    let traversalIdentifiers = await fetcher.candidateTraversalIdentifiers
    #expect(Set(traversalIdentifiers.compactMap { $0 }).count == 1)
    #expect(await pusher.zoneRebuildFloors.count == 1)
    #expect(try core.currentGenerationSnapshotStaging() == nil)
    guard case .ready? = try await pusher.currentZoneGenerationState() else {
      Issue.record("the same candidate lease should publish after nil-token readback")
      return
    }
  }

  @Test
  func persistentCandidateReadbackFailurePreparesOneFreshCandidateThenYieldsToPacing()
    async throws
  {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let failure = CloudSyncPerRecordFetchFailure(
      failedRecordCount: 1, failedRecordNames: ["missing-candidate-record"],
      cloudKitErrorCodes: [CKError.Code.unknownItem.rawValue],
      kind: .persistent, checkpointFingerprint: "candidate-baseline")
    let fetcher = PerRecordFailureFetcher(failure: failure)
    let subject = coordinator(pusher: pusher, fetcher: fetcher)
    let core = try makeInMemoryCore()
    _ = try await core.createTask(title: "Candidate must be complete", notes: "")

    await #expect(throws: CloudSyncPerRecordFetchFailure.self) {
      try await subject.runCycle(sync: core)
    }

    #expect(await fetcher.callCount == 1)
    #expect(try core.currentGenerationSnapshotStaging() == nil)
    guard
      case .rebuilding(let replacement, _, _, let retired, _)? =
        try await pusher.currentZoneGenerationState()
    else {
      Issue.record("persistent readback failure must leave a fresh candidate claimed")
      return
    }
    #expect(replacement.epoch >= 2)
    #expect(retired.isEmpty == false)
  }

  @Test
  func newlyUnderstoodHeldRecordInvalidatesAnOlderImmutableCandidate() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let core = try makeInMemoryCore()
    _ = try await core.createTask(title: "Captured before future replay", notes: "")
    let crashingFetcher = CrashAfterFirstCandidateReadbackPageFetcher(pusher: pusher)
    let firstCoordinator = coordinator(pusher: pusher, fetcher: crashingFetcher)

    await #expect(throws: GenerationReadbackCrash.self) {
      try await firstCoordinator.runCycle(sync: core)
    }
    let stale = try #require(try core.currentGenerationSnapshotStaging())

    let recoveredTaskID = "01966a3f-7c8b-7d4e-8f3a-00000000c701"
    let recoveredVersion = try Hlc.parse("1811234567890_0000_c1d2e3f4c1d2e3f4")
    let recovered = SyncEnvelope(
      entityType: .task, entityId: recoveredTaskID, operation: .upsert,
      version: recoveredVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try coordinatorTaskPayload(
        id: recoveredTaskID, title: "Recovered future record",
        version: recoveredVersion.description,
        timestamp: "2026-07-15T00:00:00.000Z"),
      deviceId: "future-device")
    try core.write { db in
      try PendingInboxDrain.enqueuePending(
        db, envelope: recovered,
        reason: "entity_type_too_new",
        missingEntityType: nil, missingEntityID: nil)
    }

    let resumedCoordinator = coordinator(
      pusher: pusher, fetcher: RecordingPusherRemoteChangeFetcher(pusher: pusher))
    _ = try #require(try await resumedCoordinator.runCycle(sync: core))

    let published = try #require(
      (try await pusher.currentZoneGenerationState())?.activeDescriptor)
    #expect(published.epoch > stale.binding.generation)
    #expect(try core.currentGenerationSnapshotStaging() == nil)
    #expect(try core.unresolvedFutureRecordCount() == 0)
    #expect((try await core.loadTask(id: recoveredTaskID)).title == "Recovered future record")
    let recordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityName.task, entityId: recoveredTaskID)
    #expect((await pusher.rebuildingPushedRecordNames).contains(recordName))
  }

  @Test
  func candidatePublicationPausesWhileFutureRecordsRemainDurablyHeld() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let core = try makeInMemoryCore()
    try core.deferUnknownTypeRecords([
      RawEnvelopeFields(
        entityType: "future_entity", entityId: "future-record",
        operation: SyncOperation.upsert.asString,
        version: authoritativeRemoteVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: #"{"future":true}"#, deviceId: "future-device")
    ])
    let subject = coordinator(pusher: pusher)

    do {
      _ = try await subject.runCycle(sync: core)
      Issue.record("a candidate must not publish while a future record is held")
    } catch let error as CloudSyncFutureRecordsPending {
      #expect(error == CloudSyncFutureRecordsPending(count: 1))
    }

    #expect(try core.unresolvedFutureRecordCount() == 1)
    #expect(await pusher.ensureZoneCallCount == 0)
    guard case .rebuilding? = try await pusher.currentZoneGenerationState() else {
      Issue.record("the claimed generation must remain unpublished for a future app build")
      return
    }
  }

  @Test
  func initialGenerationBuildRejectsCurrentSchemaUnresolvedDependency() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let core = try makeInMemoryCore()
    let missingListID = coordinatorFixtureID(20_000)
    let pendingTask = try coordinatorTaskEnvelope(
      id: coordinatorFixtureID(20_001), title: "Pending current-schema child",
      listID: missingListID)
    try core.write { db in
      try PendingInboxDrain.enqueuePending(
        db, envelope: pendingTask,
        reason: "missing dependency",
        missingEntityType: EntityKind.list.asString,
        missingEntityID: missingListID)
    }
    let subject = coordinator(pusher: pusher)

    do {
      _ = try await subject.runCycle(sync: core)
      Issue.record("an unresolved current-schema dependency must block candidate publication")
    } catch let error as CloudSyncInboundStatePending {
      #expect(
        error
          == CloudSyncInboundStatePending(
            pendingRecordCount: 1, corruptRecordCount: 0))
    }

    #expect(try core.unresolvedFutureRecordCount() == 0)
    #expect(try core.unresolvedInboundRecordCount() == 1)
    #expect(await pusher.ensureZoneCallCount == 0)
    #expect(await pusher.rebuildingPushedRecordNames.isEmpty)
    guard case .rebuilding? = try await pusher.currentZoneGenerationState() else {
      Issue.record("the unpublished rebuild lease must remain claimed for retry")
      return
    }
  }

  @Test
  func initialGenerationBuildResolvesAStandingReseedBeforePublishing() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let core = try makeInMemoryCore()
    let task = try await core.createTask(title: "Bootstrap reseed", notes: "")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }
    let subject = coordinator(
      pusher: pusher,
      fetcher: RecordingPusherRemoteChangeFetcher(pusher: pusher))

    _ = try #require(try await subject.runCycle(sync: core))

    #expect(try core.isReseedRequired() == false)
    let taskRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityName.task, entityId: task.id)
    #expect((await pusher.rebuildingPushedRecordNames).contains(taskRecordName))
    guard case .ready? = try await pusher.currentZoneGenerationState() else {
      Issue.record("the complete local seed should publish after resolving the marker")
      return
    }
  }

  @Test
  func initialGenerationBuildStillRejectsAnIncompleteReseedPass() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let core = try makeInMemoryCore()
    try core.write { db in
      try seedCloudSyncCorruption(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
            VALUES ('task', 'poison-bootstrap-reseed-task', 'tainted-version',
                    '2026-07-14T00:00:00.000Z')
            """)
      }
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }
    let subject = coordinator(pusher: pusher)

    await #expect(throws: CloudSyncReseedRequiredPending.self) {
      try await subject.runCycle(sync: core)
    }

    #expect(try core.isReseedRequired())
    #expect(await pusher.ensureZoneCallCount == 0)
    #expect(await pusher.rebuildingPushedRecordNames.isEmpty)
    guard case .rebuilding? = try await pusher.currentZoneGenerationState() else {
      Issue.record("an incomplete local enumeration must not publish a candidate")
      return
    }
  }

  @Test
  func standingReseedPreemptsAnEligibleCompactionRotation() async throws {
    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let core = try makeInMemoryCore()
    try seedCompletedBaseline(core: core, descriptor: descriptor)
    let entityID = "00000001-0000-7000-8000-000000000299"
    let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
    try core.write { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: entityID,
        version: version, deletedAt: "2024-01-01T00:00:00.000Z")
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: entityID,
          version: version, confirmedAt: "2024-01-02T00:00:00.000Z"))
      try db.execute(
        sql: """
          UPDATE sync_cloudkit_account_binding
          SET trusted_server_time = '2026-01-02T00:00:00.000Z'
          WHERE singleton = 1 AND account_identifier = 'account-A'
          """)
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }
    #expect(
      try core.trustedTombstoneCompactionCutoff(
        forAccountIdentifier: "account-A") != nil)
    let fetcher = RecordingTerminalChangeFetcher(terminalToken: Data([0x25]))
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await subject.runCycle(sync: core))

    #expect(await pusher.zoneRebuildFloors.isEmpty)
    #expect(try core.isReseedRequired() == false)
    #expect((await fetcher.checkpoints).count == 1)
    #expect((await fetcher.checkpoints)[0] == nil)
    #expect(
      try core.read { db in
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: entityID)
      } != nil)
    guard case .ready(let current, _, _)? = try await pusher.currentZoneGenerationState() else {
      Issue.record("reseed recovery must finish in the existing ready generation")
      return
    }
    #expect(current == descriptor)
  }

  @Test
  func localWriteAfterCaptureStaysPendingAndShipsOnlyAfterPublication() async throws {
    let pusher = RecordingRecordPusher()
    await pusher.setGenerationState(nil)
    let core = try makeInMemoryCore()
    let fetcher = MutatingCandidateReadbackFetcher(pusher: pusher, core: core)
    let coordinator = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await coordinator.runCycle(sync: core))

    let taskID = try #require(await fetcher.createdTaskID)
    let taskRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityKind.task.asString, entityId: taskID)
    #expect(!(await pusher.rebuildingPushedRecordNames).contains(taskRecordName))
    #expect((await pusher.readyPushedRecordNames).contains(taskRecordName))
    #expect(await pusher.zoneRebuildFloors.count == 1)
    #expect(
      try core.enrolledZoneEpoch(forAccountIdentifier: "account-A")
        == (try await pusher.currentZoneGenerationState())?.epoch)
  }

  @Test
  func publisherProofSurvivesAnInterruptedFirstCompactedGenerationBaseline() async throws {
    let pusher = RecordingRecordPusher()
    var descriptor = RecordingRecordPusher.readyDescriptor
    descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    await pusher.setGenerationState(
      .ready(descriptor: descriptor, retiredZoneNames: []))
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let boundary = try CloudTraversalBoundary(
      accountIdentifier: "account-A", zoneIdentifier: descriptor.zoneName,
      generation: descriptor.epoch,
      generationIdentifier: descriptor.generationID,
      readyWitness: descriptor.readyWitness,
      tombstoneCompactionCutoff: descriptor.tombstoneCompactionCutoff)
    let publishedEpoch = descriptor.epoch
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: String(publishedEpoch))
    }
    _ = try core.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "interrupted-publisher-baseline",
      start: .baseline)
    let localTask = try await core.createTask(
      title: "Pending after published capture", notes: "")
    let fetcher = RecordingTerminalChangeFetcher(terminalToken: Data([0x26]))
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await subject.runCycle(sync: core))

    #expect(try core.authoritativeSnapshotSession() == nil)
    #expect((try await core.loadTask(id: localTask.id)).id == localTask.id)
    let taskRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityKind.task.asString, entityId: localTask.id)
    #expect((await pusher.readyPushedRecordNames).contains(taskRecordName))
    #expect((await fetcher.checkpoints).count == 1)
    #expect((await fetcher.checkpoints)[0] == nil)
  }

  @Test
  func peerWithoutTerminalServerCoverageAdoptsCompactedGenerationAuthoritatively() async throws {
    let pusher = RecordingRecordPusher()
    var descriptor = RecordingRecordPusher.readyDescriptor
    descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let retiredZone = "LorvexData-e0-retired-generation"
    await pusher.setGenerationState(
      .ready(descriptor: descriptor, retiredZoneNames: [retiredZone]))
    let core = try makeInMemoryCore()
    let staleTask = try await core.createTask(title: "Stale offline task", notes: "")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: "0")
    }
    let fetcher = StubRemoteChangeFetcher(
      records: [
        try authoritativeInboxRecord(descriptor: descriptor),
        authoritativeFutureRecord(descriptor: descriptor),
      ],
      serverChangeTokenData: Data([0x21]))
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    let report = try #require(try await subject.runCycle(sync: core))

    #expect(report.pushedRecordCount == 0)
    #expect(report.inbound.applied >= 1)
    #expect(report.inbound.deferredUnknownType == 1)
    #expect(try core.unresolvedFutureRecordCount() == 1)
    #expect(try core.authoritativeSnapshotSession() == nil)
    #expect(try core.enrolledZoneEpoch(forAccountIdentifier: "account-A") == descriptor.epoch)
    let tasks = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(!tasks.tasks.contains(where: { $0.id == staleTask.id }))
    #expect(await pusher.readyPushedRecordNames.isEmpty)
  }

  @Test
  func peerWithStrictlyLaterTerminalServerCoverageUnionsCompactedGeneration() async throws {
    let pusher = RecordingRecordPusher()
    var descriptor = RecordingRecordPusher.readyDescriptor
    descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let enrolledEpoch = descriptor.epoch - 1
    await pusher.setGenerationState(
      .ready(descriptor: descriptor, retiredZoneNames: []))
    let core = try makeInMemoryCore()
    let localTask = try await core.createTask(title: "Covered offline task", notes: "")
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: String(enrolledEpoch))
      try db.execute(
        sql: """
          UPDATE sync_cloudkit_account_binding
          SET trusted_terminal_server_time = '2025-01-01T00:00:00.001Z'
          WHERE singleton = 1 AND account_identifier = 'account-A'
          """)
    }
    let subject = coordinator(
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(
        records: [try authoritativeInboxRecord(descriptor: descriptor)],
        serverChangeTokenData: Data([0x22])))

    let report = try #require(try await subject.runCycle(sync: core))

    #expect(report.pushedRecordCount > 0)
    #expect(try core.authoritativeSnapshotSession() == nil)
    let tasks = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(tasks.tasks.contains(where: { $0.id == localTask.id }))
    let taskRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityKind.task.asString, entityId: localTask.id)
    #expect((await pusher.readyPushedRecordNames).contains(taskRecordName))
    #expect(try core.enrolledZoneEpoch(forAccountIdentifier: "account-A") == descriptor.epoch)
  }

  @Test
  func completedCompactionBaselineRetriesLocalCleanupBeforeOutbound() async throws {
    let pusher = RecordingRecordPusher()
    var descriptor = RecordingRecordPusher.readyDescriptor
    descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    await pusher.setGenerationState(
      .ready(descriptor: descriptor, retiredZoneNames: []))
    let core = try makeInMemoryCore()
    try seedCompletedBaseline(core: core, descriptor: descriptor)
    let entityID = "00000001-0000-7000-8000-000000000201"
    let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
    try core.write { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: entityID,
        version: version, deletedAt: "2024-01-01T00:00:00.000Z")
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: entityID,
          version: version, confirmedAt: "2024-01-02T00:00:00.000Z"))
      try seedOutboxEnvelope(
        db,
        SyncEnvelope(
          entityType: .task, entityId: entityID, operation: .delete,
          version: try Hlc.parse(version), payloadSchemaVersion: 1,
          payload: "{}", deviceId: "compaction-retry-device"))
    }

    _ = try #require(
      try await coordinator(
        pusher: pusher,
        fetcher: StubRemoteChangeFetcher(
          records: [], serverChangeTokenData: Data([0x23]))
      ).runCycle(sync: core))

    #expect(
      try core.read { db in
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: entityID) == nil
          && (try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ? AND synced_at IS NULL",
            arguments: [entityID]) ?? 0) == 0
      })
    let recordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityName.task, entityId: entityID)
    #expect(!(await pusher.readyPushedRecordNames).contains(recordName))
  }

  @Test
  func compactedGenerationAuthoritativeSnapshotResumesExactContinuation() async throws {
    let pusher = RecordingRecordPusher()
    var descriptor = RecordingRecordPusher.readyDescriptor
    descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let retiredZone = "LorvexData-e0-retired-generation"
    await pusher.setGenerationState(
      .ready(descriptor: descriptor, retiredZoneNames: [retiredZone]))
    let core = try makeInMemoryCore()
    let staleTask = try await core.createTask(title: "Absent remotely", notes: "")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: "0")
    }
    let fetcher = TwoPageAuthoritativeSnapshotFetcher(
      inbox: try authoritativeInboxRecord(descriptor: descriptor))
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    let first = try #require(try await subject.runCycle(sync: core))
    let interrupted = try #require(try core.authoritativeSnapshotSession())
    #expect(first.moreInboundComing)
    #expect(interrupted.phase == .pulling)
    let beforeFinalization = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(beforeFinalization.tasks.contains(where: { $0.id == staleTask.id }))

    let second = try #require(try await subject.runCycle(sync: core))
    #expect(!second.moreInboundComing)
    #expect(try core.authoritativeSnapshotSession() == nil)
    let checkpoints = await fetcher.checkpoints
    #expect(checkpoints.count == 2)
    #expect(checkpoints[0] == nil)
    #expect(checkpoints[1]?.serverChangeTokenData == Data([0x31]))
    let traversalIdentifiers = await fetcher.traversalIdentifiers
    #expect(traversalIdentifiers == [interrupted.sessionToken, interrupted.sessionToken])
    let afterFinalization = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(!afterFinalization.tasks.contains(where: { $0.id == staleTask.id }))
  }

  @Test
  func foreignRecordTypeCannotProveAuthoritativeEntityAbsence() async throws {
    let pusher = RecordingRecordPusher()
    var descriptor = RecordingRecordPusher.readyDescriptor
    descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    await pusher.setGenerationState(
      .ready(descriptor: descriptor, retiredZoneNames: ["LorvexData-e0-retired-generation"]))
    let core = try makeInMemoryCore()
    let localTask = try await core.createTask(title: "Preserve on foreign slot", notes: "")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: "0")
    }
    let foreign = foreignRecordOccupyingEntitySlot(
      descriptor: descriptor, entityType: EntityKind.task.asString,
      entityID: localTask.id)
    let subject = coordinator(
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(
        records: [try authoritativeInboxRecord(descriptor: descriptor), foreign],
        serverChangeTokenData: Data([0x71])))

    _ = try #require(try await subject.runCycle(sync: core))

    let tasks = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(tasks.tasks.contains { $0.id == localTask.id })
    // Corrupt inventory restarts from nil and leaves the durable session armed
    // for a clean retry; it must never finalize absence from this record.
    #expect(try core.authoritativeSnapshotSession()?.phase == .preparing)
  }

  @Test
  func physicalDeletionOfActiveMarkerAbortsAuthoritativeFinalization() async throws {
    for markerName in [
      CloudSyncGenerationRootRecord.recordName,
      CloudSyncGenerationSealRecord.recordName,
    ] {
      let pusher = RecordingRecordPusher()
      var descriptor = RecordingRecordPusher.readyDescriptor
      descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
      await pusher.setGenerationState(
        .ready(descriptor: descriptor, retiredZoneNames: ["LorvexData-e0-retired-generation"]))
      let core = try makeInMemoryCore()
      let localTask = try await core.createTask(title: "Preserve on marker deletion", notes: "")
      try core.write { db in
        try SyncCheckpoints.set(
          db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
          value: "0")
      }
      let subject = coordinator(
        pusher: pusher,
        fetcher: StubRemoteChangeFetcher(
          records: [try authoritativeInboxRecord(descriptor: descriptor)],
          deletedRecordNames: [markerName],
          serverChangeTokenData: Data([0x72])))

      // The public cycle boundary intentionally converts a generation crossing
      // into a no-op report so the next trigger re-reads control authority.
      #expect(try await subject.runCycle(sync: core) == nil)

      let tasks = try await core.listTasks(
        status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
      #expect(tasks.tasks.contains { $0.id == localTask.id })
    }
  }

  @Test
  func authoritativeSnapshotExpiryClearsStagingAndRestartsTheSameSessionFromNil()
    async throws
  {
    let pusher = RecordingRecordPusher()
    var descriptor = RecordingRecordPusher.readyDescriptor
    descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let retiredZone = "LorvexData-e0-retired-generation"
    await pusher.setGenerationState(
      .ready(descriptor: descriptor, retiredZoneNames: [retiredZone]))
    let core = try makeInMemoryCore()
    let staleTask = try await core.createTask(title: "Removed by recovered snapshot", notes: "")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: "0")
    }
    let fetcher = ExpiringAuthoritativeSnapshotFetcher(
      completeInventory: [try authoritativeInboxRecord(descriptor: descriptor)])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    let first = try #require(try await subject.runCycle(sync: core))
    #expect(first.moreInboundComing)
    let session = try #require(try core.authoritativeSnapshotSession())
    #expect(session.phase == .pulling)

    await #expect(throws: CloudSyncCursorRecoveryPrepared.self) {
      try await subject.runCycle(sync: core)
    }
    let restarted = try #require(try core.authoritativeSnapshotSession())
    #expect(restarted.sessionToken == session.sessionToken)
    #expect(restarted.phase == .ready)

    _ = try #require(try await subject.runCycle(sync: core))

    let checkpoints = await fetcher.checkpoints
    #expect(checkpoints.count == 3)
    #expect(checkpoints[0] == nil)
    #expect(checkpoints[1]?.serverChangeTokenData == Data([0x51]))
    #expect(checkpoints[2] == nil)
    let traversalIdentifiers = await fetcher.traversalIdentifiers
    #expect(
      traversalIdentifiers
        == [session.sessionToken, session.sessionToken, session.sessionToken])
    #expect(try core.authoritativeSnapshotSession() == nil)
    let tasks = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(!tasks.tasks.contains { $0.id == staleTask.id })
  }

  @Test
  func persistentAuthoritativeFailureRestartsTheSessionAtThresholdWithoutReseedLeak()
    async throws
  {
    let pusher = RecordingRecordPusher()
    var descriptor = RecordingRecordPusher.readyDescriptor
    descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let retiredZone = "LorvexData-e0-retired-generation"
    await pusher.setGenerationState(
      .ready(descriptor: descriptor, retiredZoneNames: [retiredZone]))
    let core = try makeInMemoryCore()
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: "0")
    }
    let failure = CloudSyncPerRecordFetchFailure(
      failedRecordCount: 1, failedRecordNames: ["poisoned-authoritative-record"],
      kind: .persistent, checkpointFingerprint: "authoritative-baseline")
    let fetcher = PerRecordFailureFetcher(failure: failure)
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    var originalSessionToken: String?
    for expectedCallCount in 1...3 {
      await #expect(throws: CloudSyncPerRecordFetchFailure.self) {
        try await subject.runCycle(sync: core)
      }
      #expect(await fetcher.callCount == expectedCallCount)
      let session = try #require(try core.authoritativeSnapshotSession())
      originalSessionToken = originalSessionToken ?? session.sessionToken
      #expect(session.sessionToken == originalSessionToken)
    }

    let restarted = try #require(try core.authoritativeSnapshotSession())
    #expect(restarted.phase == .ready)
    #expect(try core.isReseedRequired() == false)
  }

  @Test
  func expiredIncrementalCursorPersistsReseedAndRecoversFromNilWithoutDiscardingLocalRows()
    async throws
  {
    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let core = try makeInMemoryCore()
    try seedCompletedBaseline(core: core, descriptor: descriptor)
    let localTask = try await core.createTask(title: "Keep during in-window reseed", notes: "")
    let fetcher = ThrowOnceRemoteChangeFetcher(
      error: CKError(.changeTokenExpired),
      recoveredRecords: [try authoritativeInboxRecord(descriptor: descriptor)],
      recoveredTokenData: Data([0x22]))
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    await #expect(throws: CloudSyncCursorRecoveryPrepared.self) {
      try await subject.runCycle(sync: core)
    }
    #expect(try core.isReseedRequired())
    #expect(await pusher.readyPushedRecordNames.isEmpty)

    _ = try #require(try await subject.runCycle(sync: core))
    #expect(try core.isReseedRequired() == false)
    #expect(await fetcher.callCount == 2)
    let tasks = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(tasks.tasks.contains(where: { $0.id == localTask.id }))
    #expect(await pusher.readyPushedRecordNames.isEmpty == false)
  }

  @Test
  func completedBaselineStartsTheFirstIncrementalFromItsTerminalToken() async throws {
    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let core = try makeInMemoryCore()
    try seedCompletedBaseline(core: core, descriptor: descriptor)
    let fetcher = RecordingTerminalChangeFetcher(terminalToken: Data([0x21]))
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await subject.runCycle(sync: core))

    let checkpoints = await fetcher.checkpoints
    #expect(checkpoints.count == 1)
    #expect(checkpoints[0]?.serverChangeTokenData == Data([0x20]))
    let state = try core.cloudTraversalState(
      accountIdentifier: "account-A", zoneIdentifier: descriptor.zoneName)
    #expect(state.baselineWitness?.finalChangeToken == Data([0x20]))
    #expect(state.incrementalCursor?.changeToken == Data([0x21]))
  }

  @Test
  func nilIncrementalTerminalTokenResetsOnceAndRecoversFromANilBaseline() async throws {
    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let core = try makeInMemoryCore()
    try seedCompletedBaseline(core: core, descriptor: descriptor)
    let fetcher = NilThenValidTerminalChangeFetcher()
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    await #expect(throws: CloudSyncCursorRecoveryPrepared.self) {
      try await subject.runCycle(sync: core)
    }

    #expect(try core.isReseedRequired())
    let reset = try core.cloudTraversalState(
      accountIdentifier: "account-A", zoneIdentifier: descriptor.zoneName)
    let resetProgress = try #require(reset.progress)
    #expect(resetProgress.mode == .baseline)
    #expect(resetProgress.nextPageIndex == 0)
    #expect(resetProgress.startingChangeToken == nil)
    #expect(resetProgress.continuationToken == nil)

    _ = try #require(try await subject.runCycle(sync: core))

    #expect(try core.isReseedRequired() == false)
    let checkpoints = await fetcher.checkpoints
    #expect(checkpoints.count == 2)
    #expect(checkpoints[0]?.serverChangeTokenData == Data([0x20]))
    #expect(checkpoints[1] == nil)
    let traversalIdentifiers = await fetcher.traversalIdentifiers.compactMap { $0 }
    #expect(Set(traversalIdentifiers).count == 1)
    let recovered = try core.cloudTraversalState(
      accountIdentifier: "account-A", zoneIdentifier: descriptor.zoneName)
    #expect(recovered.baselineWitness?.finalChangeToken == Data([0x24]))
  }

  @Test
  func failedWitnessPublishReusesTheExactDurableTraversalOnRetry() async throws {
    let core = try makeInMemoryCore()
    let pusher = WitnessRecoveryPusher(publishFailures: 1)
    let fetcher = ScriptedInboundFetcher(
      pages: [
        ScriptedInboundPage(records: [], token: Data([0x71]), moreComing: false)
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    await #expect(throws: CoordinatorRecoveryProbeError.publish) {
      try await subject.runCycle(sync: core)
    }

    let interrupted = try #require(
      try core.cloudTraversalState(
        accountIdentifier: "account-A",
        zoneIdentifier: cloudSyncTestDescriptor.zoneName
      ).progress)
    #expect(await fetcher.callCount == 0)
    #expect(await pusher.publishedTraversalIdentifiers == [interrupted.traversalIdentifier])

    _ = try #require(try await subject.runCycle(sync: core))

    let completed = try #require(
      try core.cloudTraversalState(
        accountIdentifier: "account-A",
        zoneIdentifier: cloudSyncTestDescriptor.zoneName
      ).baselineWitness)
    #expect(completed.traversalIdentifier == interrupted.traversalIdentifier)
    #expect(
      await pusher.publishedTraversalIdentifiers
        == [interrupted.traversalIdentifier, interrupted.traversalIdentifier])
    #expect(await fetcher.traversalIdentifiers == [interrupted.traversalIdentifier])
  }

  @Test
  func previousWitnessDeleteFailureBlocksNewTraversalAndRetriesBeforeFetch() async throws {
    let core = try makeInMemoryCore()
    try seedCompletedBaseline(core: core, descriptor: cloudSyncTestDescriptor)
    let prior = try #require(
      try core.cloudTraversalState(
        accountIdentifier: "account-A",
        zoneIdentifier: cloudSyncTestDescriptor.zoneName
      ).baselineWitness)
    let pusher = WitnessRecoveryPusher(deleteFailures: 1)
    let fetcher = ScriptedInboundFetcher(
      pages: [
        ScriptedInboundPage(records: [], token: Data([0x72]), moreComing: false)
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    await #expect(throws: CoordinatorRecoveryProbeError.delete) {
      try await subject.runCycle(sync: core)
    }

    let blocked = try core.cloudTraversalState(
      accountIdentifier: "account-A",
      zoneIdentifier: cloudSyncTestDescriptor.zoneName)
    #expect(blocked.progress == nil)
    #expect(blocked.baselineWitness?.traversalIdentifier == prior.traversalIdentifier)
    #expect(await fetcher.callCount == 0)
    #expect(await pusher.deletedTraversalIdentifiers == [prior.traversalIdentifier])

    _ = try #require(try await subject.runCycle(sync: core))

    let recovered = try core.cloudTraversalState(
      accountIdentifier: "account-A",
      zoneIdentifier: cloudSyncTestDescriptor.zoneName)
    let incremental = try #require(recovered.incrementalCursor)
    #expect(incremental.traversalIdentifier != prior.traversalIdentifier)
    #expect(
      await pusher.deletedTraversalIdentifiers
        == [prior.traversalIdentifier, prior.traversalIdentifier])
    #expect(await fetcher.callCount == 1)
    #expect(await fetcher.traversalIdentifiers == [incremental.traversalIdentifier])
  }

  @Test
  func terminalInboundCommitSurvivesPostWorkFailureInPartialReport() async throws {
    let core = try makeInMemoryCore()
    let pusher = WitnessRecoveryPusher(failRetentionReadAt: 2)
    let fetcher = ScriptedInboundFetcher(
      pages: [
        ScriptedInboundPage(
          records: [try partialRemoteListRecord(descriptor: cloudSyncTestDescriptor)],
          token: Data([0x73]), moreComing: false)
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    do {
      _ = try await subject.runDrainingCycle(sync: core)
      Issue.record("post-commit failure must preserve failure semantics")
    } catch let partial as CloudSyncPartialCycleFailure {
      #expect(partial.underlyingError as? CoordinatorRecoveryProbeError == .postCommit)
      #expect(partial.partialReport.fetchedRecordCount == 1)
      #expect(partial.partialReport.inbound.applied == 1)
      #expect(partial.partialReport.inbound.appliedEntityTypes == [.list])
    }

    let committedName = try core.read { db in
      try String.fetchOne(
        db, sql: "SELECT name FROM lists WHERE id = ?",
        arguments: ["01966a3f-7c8b-7d4e-8f3a-00000000c701"])
    }
    #expect(committedName == "Committed before retry")
  }

  @Test
  func laterTerminalPostWorkFailureAggregatesEveryCommittedPage() async throws {
    let core = try makeInMemoryCore()
    let pusher = WitnessRecoveryPusher(failRetentionReadAt: 3)
    let fetcher = ScriptedInboundFetcher(
      pages: [
        ScriptedInboundPage(
          records: [try partialRemoteListRecord(descriptor: cloudSyncTestDescriptor)],
          token: Data([0x74]), moreComing: true),
        ScriptedInboundPage(
          records: [try partialRemoteTaskRecord(descriptor: cloudSyncTestDescriptor)],
          token: Data([0x75]), moreComing: false),
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    do {
      _ = try await subject.runDrainingCycle(sync: core)
      Issue.record("the terminal post-work failure must remain visible")
    } catch let partial as CloudSyncPartialCycleFailure {
      #expect(partial.underlyingError as? CoordinatorRecoveryProbeError == .postCommit)
      #expect(partial.partialReport.fetchedRecordCount == 2)
      #expect(partial.partialReport.inbound.applied == 2)
      #expect(partial.partialReport.inbound.appliedEntityTypes == [.list, .task])
    }

    #expect(
      (try await core.loadTask(id: "01966a3f-7c8b-7d4e-8f3a-00000000c702")).title
        == "Committed terminal page")
  }

  @Test
  func midBaselineExpiryAtomicallyRestartsTheSameWitnessFromNilOnTheNextTrigger()
    async throws
  {
    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let core = try makeInMemoryCore()
    let localTask = try await core.createTask(title: "Keep across baseline restart", notes: "")
    let fetcher = ExpiringMidBaselineFetcher(
      firstPageRecords: [try partialRemoteListRecord(descriptor: descriptor)])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    do {
      _ = try await subject.runDrainingCycle(sync: core)
      Issue.record("page-two cursor expiry must preserve failure semantics")
    } catch let partial as CloudSyncPartialCycleFailure {
      #expect(partial.underlyingError is CloudSyncCursorRecoveryPrepared)
      #expect(partial.partialReport.fetchedRecordCount == 1)
      #expect(partial.partialReport.inbound.appliedEntityTypes == [.list])
    }
    let reset = try #require(
      try core.cloudTraversalState(
        accountIdentifier: "account-A", zoneIdentifier: descriptor.zoneName
      ).progress)
    #expect(reset.mode == .baseline)
    #expect(reset.nextPageIndex == 0)
    #expect(reset.startingChangeToken == nil)
    #expect(reset.continuationToken == nil)
    #expect(try core.isReseedRequired())

    _ = try #require(try await subject.runCycle(sync: core))

    let checkpoints = await fetcher.checkpoints
    #expect(checkpoints.count == 3)
    #expect(checkpoints[0] == nil)
    #expect(checkpoints[1]?.serverChangeTokenData == Data([0x31]))
    #expect(checkpoints[2] == nil)
    let recordedTraversalIdentifiers = await fetcher.traversalIdentifiers
    let traversalIdentifiers = recordedTraversalIdentifiers.compactMap { $0 }
    #expect(Set(traversalIdentifiers).count == 1)
    let tasks = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(tasks.tasks.contains { $0.id == localTask.id })
  }

  @Test
  func transientPerRecordFailureStopsAfterOneFetchWithoutApplyingOrReseeding()
    async throws
  {
    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let core = try makeInMemoryCore()
    let record = try authoritativeInboxRecord(descriptor: descriptor)
    let failure = CloudSyncPerRecordFetchFailure(
      failedRecordCount: 1, failedRecordNames: ["rate-limited"],
      cloudKitErrorCodes: [CKError.Code.requestRateLimited.rawValue],
      kind: .transient, retryAfter: 37, checkpointFingerprint: "baseline")
    let fetcher = PerRecordFailureFetcher(failure: failure, records: [record])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    await #expect(throws: CloudSyncPerRecordFetchFailure.self) {
      try await subject.runDrainingCycle(sync: core)
    }

    #expect(await fetcher.callCount == 1)
    #expect(!CloudSyncTransientClassifier.isTransient(CKError(.internalError)))
    #expect(CloudSyncTransientClassifier.serverRetryAfter(failure) == 37)
    #expect(try core.isReseedRequired() == false)
    let state = try core.cloudTraversalState(
      accountIdentifier: "account-A", zoneIdentifier: descriptor.zoneName)
    #expect(state.progress?.nextPageIndex == 0)
  }

  @Test
  func persistentPerRecordFailureResetsExactlyAtThresholdWithoutTightLooping()
    async throws
  {
    let pusher = RecordingRecordPusher()
    let descriptor = RecordingRecordPusher.readyDescriptor
    let core = try makeInMemoryCore()
    let failure = CloudSyncPerRecordFetchFailure(
      failedRecordCount: 1, failedRecordNames: ["unreadable"],
      cloudKitErrorCodes: [CKError.Code.internalError.rawValue],
      kind: .persistent, checkpointFingerprint: "baseline")
    let fetcher = PerRecordFailureFetcher(failure: failure)
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    for expectedCallCount in 1...3 {
      await #expect(throws: CloudSyncPerRecordFetchFailure.self) {
        try await subject.runCycle(sync: core)
      }
      #expect(await fetcher.callCount == expectedCallCount)
      #expect(try core.isReseedRequired() == (expectedCallCount == 3))
    }
    let progress = try #require(
      try core.cloudTraversalState(
        accountIdentifier: "account-A", zoneIdentifier: descriptor.zoneName
      ).progress)
    #expect(progress.mode == .baseline)
    #expect(progress.nextPageIndex == 0)
    #expect(progress.continuationToken == nil)
  }

  @Test
  func drainingReseedPreparesBaselineOnlyOnceAcrossMultiplePages() async throws {
    let pusher = RecordingRecordPusher()
    let core = try makeInMemoryCore()
    try core.write { db in
      try seedCloudSyncCorruption(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
            VALUES ('task', 'poison-reseed-task', 'tainted-version',
                    '2026-07-14T00:00:00.000Z')
            """)
      }
    }
    try core.write { db in
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }
    let fetcher = ScriptedMoreComingFetcher(
      moreComingScript: [true, false], tokenData: Data([0x44]))
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    let report = try #require(try await subject.runDrainingCycle(sync: core))

    #expect(report.moreInboundComing == false)
    #expect(await fetcher.callCount == 2)
    let state = try core.cloudTraversalState(
      accountIdentifier: "account-A",
      zoneIdentifier: RecordingRecordPusher.readyDescriptor.zoneName)
    #expect(state.baselineWitness?.completedPageCount == 2)
    #expect(state.baselineWitness?.finalChangeToken == Data([0x44]))
    // The poison row makes the backfill partial. The marker must remain for a
    // later top-level trigger, but page 2 must still advance the active baseline
    // instead of observing that marker and resetting to page 1.
    #expect(try core.isReseedRequired())
  }

  @Test
  func terminalReseedKeepsMarkerWhenBackfillSkipsPoisonedRows() async throws {
    let pusher = RecordingRecordPusher()
    let core = try makeInMemoryCore()
    try core.write { db in
      try seedCloudSyncCorruption(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
            VALUES ('task', 'poison-terminal-reseed-task', 'tainted-version',
                    '2026-07-14T00:00:00.000Z')
            """)
      }
    }
    try core.write { db in
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }
    let subject = coordinator(
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(
        records: [], serverChangeTokenData: Data([0x45])))

    let report = try #require(try await subject.runCycle(sync: core))

    #expect(report.moreInboundComing == false)
    // A terminal remote page completes only the inbound half of recovery. The
    // poisoned tombstone prevented a complete outbound backfill, so the durable
    // marker must remain set for a later retry instead of declaring recovery
    // complete and allowing a stale peer to resurrect the deleted task.
    #expect(try core.isReseedRequired())
  }

  @Test
  func unresolvedPredecessorDependencyPersistsANilBaselineForTheNextBuild()
    async throws
  {
    let pusher = RecordingRecordPusher()
    let previous = RecordingRecordPusher.readyDescriptor
    let foreign = CloudSyncZoneRebuildLease(
      identifier: "foreign-dependency-rebuild",
      ownerIdentifier: "foreign-database", epoch: previous.epoch + 1,
      generationID: "foreign-dependency-generation",
      candidateZoneName: "LorvexData-e2-foreign-dependency-generation")
    await pusher.setGenerationState(
      .rebuilding(
        lease: foreign, previousActive: previous, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let core = try makeInMemoryCore()
    try seedCompletedBaseline(core: core, descriptor: previous)
    let parentID = coordinatorFixtureID(40_000)
    let taskID = coordinatorFixtureID(40_001)
    let child = CloudSyncEnvelopeRecord.makeRecord(
      try coordinatorTaskEnvelope(
        id: taskID, title: "Waits for unchanged parent", listID: parentID),
      zoneID: previous.zoneID)
    let parent = try coordinatorListRecord(
      descriptor: previous, id: parentID, name: "Recovered unchanged parent")
    let fetcher = ScriptedPredecessorRecoveryFetcher(
      previousZoneName: previous.zoneName, pusher: pusher,
      previousPages: [
        .init(records: [child], token: Data([0x71])),
        .init(records: [parent], token: Data([0x72])),
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    await #expect(throws: CloudSyncInboundStatePending.self) {
      try await subject.runCycle(sync: core)
    }

    let reset = try core.cloudTraversalState(
      accountIdentifier: "account-A", zoneIdentifier: previous.zoneName)
    let resetProgress = try #require(reset.progress)
    #expect(resetProgress.mode == .baseline)
    #expect(resetProgress.startingChangeToken == nil)
    #expect(resetProgress.continuationToken == nil)
    let firstCheckpoints = await fetcher.previousCheckpoints
    #expect(firstCheckpoints.count == 1)
    #expect(firstCheckpoints[0]?.serverChangeTokenData == Data([0x20]))

    _ = try #require(try await subject.runCycle(sync: core))

    #expect((try await core.loadTask(id: taskID)).title == "Waits for unchanged parent")
    let recoveredCheckpoints = await fetcher.previousCheckpoints
    #expect(recoveredCheckpoints.count >= 2)
    #expect(recoveredCheckpoints[1] == nil)
  }

  @Test
  func corruptPredecessorFencePersistsANilBaselineForRecovery() async throws {
    let pusher = RecordingRecordPusher()
    let previous = RecordingRecordPusher.readyDescriptor
    let foreign = CloudSyncZoneRebuildLease(
      identifier: "foreign-corrupt-rebuild",
      ownerIdentifier: "foreign-database", epoch: previous.epoch + 1,
      generationID: "foreign-corrupt-generation",
      candidateZoneName: "LorvexData-e2-foreign-corrupt-generation")
    await pusher.setGenerationState(
      .rebuilding(
        lease: foreign, previousActive: previous, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let core = try makeInMemoryCore()
    try seedCompletedBaseline(core: core, descriptor: previous)
    let fetcher = ScriptedPredecessorRecoveryFetcher(
      previousZoneName: previous.zoneName, pusher: pusher,
      previousPages: [
        .init(
          records: [corruptEntityRecord(descriptor: previous)],
          token: Data([0x75]))
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    do {
      _ = try await subject.runCycle(sync: core)
      Issue.record("a corrupt predecessor record must block candidate publication")
    } catch let error as CloudSyncInboundStatePending {
      #expect(error.pendingRecordCount == 0)
      #expect(error.corruptRecordCount == 1)
    }

    let reset = try core.cloudTraversalState(
      accountIdentifier: "account-A", zoneIdentifier: previous.zoneName)
    let resetProgress = try #require(reset.progress)
    #expect(resetProgress.mode == .baseline)
    #expect(resetProgress.startingChangeToken == nil)
    #expect(resetProgress.continuationToken == nil)
    let checkpoints = await fetcher.previousCheckpoints
    #expect(checkpoints.count == 1)
    #expect(checkpoints[0]?.serverChangeTokenData == Data([0x20]))
  }

  @Test
  func predecessorAdoptionReplacesMismatchedSnapshotWithoutReclassifyingPostSessionWrite()
    async throws
  {
    let pusher = RecordingRecordPusher()
    var previous = RecordingRecordPusher.readyDescriptor
    previous.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let foreign = CloudSyncZoneRebuildLease(
      identifier: "foreign-session-replacement-rebuild",
      ownerIdentifier: "foreign-database", epoch: previous.epoch + 1,
      generationID: "foreign-session-replacement-generation",
      candidateZoneName: "LorvexData-e2-foreign-session-replacement-generation")
    await pusher.setGenerationState(
      .rebuilding(
        lease: foreign, previousActive: previous, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))

    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    let oldBoundary = try CloudTraversalBoundary(
      accountIdentifier: "account-A",
      zoneIdentifier: "LorvexData-e0-old-authoritative-session",
      generation: 0,
      generationIdentifier: "old-authoritative-session",
      readyWitness: "old-authoritative-session-witness")
    _ = try core.beginAuthoritativeSnapshot(boundary: oldBoundary)
    let postSessionTask = try await core.createTask(
      title: "Preserve post-session intent", notes: "")
    let fetcher = ScriptedPredecessorRecoveryFetcher(
      previousZoneName: previous.zoneName, pusher: pusher,
      previousPages: [
        .init(
          records: [try authoritativeInboxRecord(descriptor: previous)],
          token: Data([0x76]))
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await subject.runCycle(sync: core))

    #expect(try core.authoritativeSnapshotSession() == nil)
    #expect((try await core.loadTask(id: postSessionTask.id)).id == postSessionTask.id)
    let taskRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityKind.task.asString, entityId: postSessionTask.id)
    #expect((await pusher.rebuildingPushedRecordNames).contains(taskRecordName))
  }

  @Test
  func foreignRebuildTakeoverAdoptsAnUncoveredCompactedPredecessorBeforeCapture()
    async throws
  {
    let pusher = RecordingRecordPusher()
    var previous = RecordingRecordPusher.readyDescriptor
    previous.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let foreign = CloudSyncZoneRebuildLease(
      identifier: "foreign-compacted-rebuild",
      ownerIdentifier: "foreign-database", epoch: previous.epoch + 1,
      generationID: "foreign-compacted-generation",
      candidateZoneName: "LorvexData-e2-foreign-compacted-generation")
    await pusher.setGenerationState(
      .rebuilding(
        lease: foreign, previousActive: previous, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let core = try makeInMemoryCore()
    let staleTask = try await core.createTask(
      title: "Must not survive foreign takeover", notes: "")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: "0")
    }
    let fetcher = ScriptedPredecessorRecoveryFetcher(
      previousZoneName: previous.zoneName, pusher: pusher,
      previousPages: [
        .init(
          records: [try authoritativeInboxRecord(descriptor: previous)],
          token: Data([0x73]))
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await subject.runCycle(sync: core))

    let tasks = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(!tasks.tasks.contains { $0.id == staleTask.id })
    let staleRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityKind.task.asString, entityId: staleTask.id)
    #expect(!(await pusher.rebuildingPushedRecordNames).contains(staleRecordName))
    let checkpoints = await fetcher.previousCheckpoints
    #expect(!checkpoints.isEmpty)
    #expect(checkpoints[0] == nil)
  }

  @Test
  func foreignRebuildTakeoverUnionsACompactedPredecessorWithTrustedCoverage()
    async throws
  {
    let pusher = RecordingRecordPusher()
    var previous = RecordingRecordPusher.readyDescriptor
    previous.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let foreign = CloudSyncZoneRebuildLease(
      identifier: "foreign-covered-rebuild",
      ownerIdentifier: "foreign-database", epoch: previous.epoch + 1,
      generationID: "foreign-covered-generation",
      candidateZoneName: "LorvexData-e2-foreign-covered-generation")
    await pusher.setGenerationState(
      .rebuilding(
        lease: foreign, previousActive: previous, phase: .claimed,
        retiredZoneNames: [], leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let core = try makeInMemoryCore()
    let localTask = try await core.createTask(title: "Covered local intent", notes: "")
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: "0")
      try db.execute(
        sql: """
          UPDATE sync_cloudkit_account_binding
          SET trusted_terminal_server_time = '2025-01-01T00:00:00.001Z'
          WHERE singleton = 1 AND account_identifier = 'account-A'
          """)
    }
    let fetcher = ScriptedPredecessorRecoveryFetcher(
      previousZoneName: previous.zoneName, pusher: pusher,
      previousPages: [
        .init(
          records: [try authoritativeInboxRecord(descriptor: previous)],
          token: Data([0x74]))
      ])
    let subject = coordinator(pusher: pusher, fetcher: fetcher)

    _ = try #require(try await subject.runCycle(sync: core))

    let tasks = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(tasks.tasks.contains { $0.id == localTask.id })
    let localRecordName = CloudSyncEnvelopeRecord.recordName(
      entityType: EntityKind.task.asString, entityId: localTask.id)
    #expect((await pusher.rebuildingPushedRecordNames).contains(localRecordName))
  }

  @Test
  func foreignRebuildTakeoverPrunesAFullRetiredLedgerBeforeClaimingReplacement() async throws {
    let pusher = RecordingRecordPusher()
    let retired = (0..<CloudSyncGenerationNaming.retiredZoneLimit).map {
      "LorvexData-e0-abandoned-\($0)"
    }
    let foreign = CloudSyncZoneRebuildLease(
      identifier: "foreign-rebuild", ownerIdentifier: "foreign-database",
      epoch: 8, generationID: "foreign-generation",
      candidateZoneName: "LorvexData-e8-foreign-generation")
    await pusher.setGenerationState(
      .rebuilding(
        lease: foreign, previousActive: nil, phase: .claimed,
        retiredZoneNames: retired,
        leaseActivityAt: Date(timeIntervalSince1970: 0)))
    let core = try makeInMemoryCore()
    let subject = coordinator(
      pusher: pusher,
      fetcher: RecordingPusherRemoteChangeFetcher(pusher: pusher))

    _ = try #require(try await subject.runCycle(sync: core))

    #expect(await pusher.deleteZoneCallCount >= retired.count + 1)
    #expect(await pusher.zoneRebuildFloors == [foreign.epoch])
    guard
      case .ready(_, let survivingRetired, _)? =
        try await pusher.currentZoneGenerationState()
    else {
      Issue.record("the expired foreign rebuild should publish its replacement")
      return
    }
    #expect(survivingRetired.isEmpty)
  }

  @Test
  func restoredDatabaseRotationCannotReuseEnrollmentToBypassCompactionAdoption()
    async throws
  {
    let pusher = RecordingRecordPusher()
    var descriptor = RecordingRecordPusher.readyDescriptor
    descriptor.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let enrolledEpoch = descriptor.epoch
    let retiredZone = "LorvexData-e0-retired-generation"
    await pusher.setGenerationState(
      .ready(descriptor: descriptor, retiredZoneNames: [retiredZone]))
    let core = try makeInMemoryCore()
    _ = try core.claimCloudTraversalAccount(accountIdentifier: "account-A")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-A"),
        value: String(enrolledEpoch))
    }
    let staleTask = try await core.createTask(title: "Restored stale task", notes: "")
    try core.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: "rotated-coordinator-database-instance")
    }
    let subject = coordinator(
      pusher: pusher,
      fetcher: StubRemoteChangeFetcher(
        records: [try authoritativeInboxRecord(descriptor: descriptor)],
        serverChangeTokenData: Data([0x91])))

    _ = try #require(try await subject.runCycle(sync: core))

    let tasks = try await core.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    #expect(!tasks.tasks.contains(where: { $0.id == staleTask.id }))
    #expect(try core.enrolledZoneEpoch(forAccountIdentifier: "account-A") == descriptor.epoch)
    #expect(await pusher.readyPushedRecordNames.isEmpty)
  }
}
