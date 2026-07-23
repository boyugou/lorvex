import CloudKit
import Foundation
import LorvexCloudSync
import LorvexDomain
import LorvexSync

// Shared fixtures for the dirty-domain reload-gating tests (macOS + iOS): build a
// well-formed inbound CKRecord of a chosen entity kind so a real coordinator
// decodes and atomically commits it through the backing in-memory core's current
// traversal protocol. The resulting real apply report drives selective reload.

let inboundSelectiveZoneID = CKRecordZone.ID(
  zoneName: CloudSyncZoneConstants.zoneName, ownerName: CKCurrentUserDefaultName)

func inboundSelectiveEnvelope(_ type: EntityKind, _ id: String, _ seq: Int) -> SyncEnvelope {
  let version = try! Hlc.parse("171123456789\(seq)_0000_a1b2c3d4a1b2c3d4")
  let commonTimestamp = "2026-05-23T12:00:00.000Z"
  let payloadValue: JSONValue
  switch type {
  case .task:
    payloadValue = .object([
      "ai_notes": .null,
      "archive_version": .string(version.description),
      "archived_at": .null,
      "available_from": .null,
      "body": .null,
      "canonical_occurrence_date": .null,
      "completed_at": .null,
      "content_version": .string(version.description),
      "created_at": .string(commonTimestamp),
      "defer_count": .int(0),
      "due_date": .null,
      "estimated_minutes": .null,
      "id": .string(id),
      "last_defer_reason": .null,
      "last_deferred_at": .null,
      "lifecycle_version": .string(version.description),
      "list_id": .string("inbox"),
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
      "title": .string("Peer task"),
      "updated_at": .string(commonTimestamp),
      "version": .string(version.description),
    ])
  case .habit:
    payloadValue = .object([
      "archived": .bool(false),
      "color": .null,
      "created_at": .string(commonTimestamp),
      "cue": .null,
      "day_of_month": .null,
      "frequency_type": .string("daily"),
      "icon": .null,
      "id": .string(id),
      "milestone_target": .null,
      "name": .string("Peer habit"),
      "per_period_target": .int(1),
      "position": .int(0),
      "target_count": .int(1),
      "updated_at": .string(commonTimestamp),
      "version": .string(version.description),
      "weekdays": .array([]),
    ])
  case .calendarEvent:
    payloadValue = .object([
      "all_day": .bool(true),
      "attendees": .null,
      "color": .null,
      "content_version": .string(version.description),
      "created_at": .string(commonTimestamp),
      "description": .null,
      "end_date": .null,
      "end_time": .null,
      "event_type": .string("event"),
      "id": .string(id),
      "location": .null,
      "occurrence_state": .null,
      "person_name": .null,
      "recurrence": .null,
      "recurrence_generation": .null,
      "recurrence_instance_date": .null,
      "recurrence_topology_version": .string(version.description),
      "series_cutover_id": .null,
      "series_id": .null,
      "start_date": .string("2026-05-23"),
      "start_time": .null,
      "timezone": .null,
      "title": .string("Peer event"),
      "updated_at": .string(commonTimestamp),
      "url": .null,
      "version": .string(version.description),
    ])
  default:
    preconditionFailure("unsupported selective-reload fixture type \(type)")
  }
  let payload = try! canonicalizeJSON(payloadValue)
  return SyncEnvelope(
    entityType: type,
    entityId: id,
    operation: .upsert,
    version: version,
    payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
    payload: payload,
    deviceId: "device-peer")
}

func inboundSelectiveRecord(_ type: EntityKind, _ id: String, _ seq: Int) -> CKRecord {
  CloudSyncEnvelopeRecord.makeRecord(
    inboundSelectiveEnvelope(type, id, seq), zoneID: inboundSelectiveZoneID)
}
