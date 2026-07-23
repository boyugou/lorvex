import Foundation
import LorvexDomain

@testable import LorvexSync

/// Completes intentionally terse CoreService test envelopes from the numbered
/// golden payload before they cross production manifest validation.
///
/// This helper belongs only to the outer Apple test target. Production has no
/// sparse-payload escape hatch: the resulting envelope is validated by the same
/// runtime registry as a real CloudKit record.
enum CurrentSyncEnvelopeTestSupport {
  private static let goldenPayloadCache = try! loadGoldenPayloads()

  static func complete(_ envelope: SyncEnvelope) throws -> SyncEnvelope {
    guard case .object(let supplied)? = JSONValue.parse(envelope.payload) else {
      return envelope
    }
    guard envelope.operation == .upsert else {
      return envelope
    }
    guard var golden = goldenPayloadCache[envelope.entityType] else {
      return envelope
    }

    neutralizeGoldenDefaults(entityType: envelope.entityType, object: &golden)
    let merged = merge(golden, overlay: supplied)
    var object = normalizeTimestamps(merged)
    object["lookup_key"] = nil
    object["version"] = .string(envelope.version.description)
    rewriteIdentity(
      entityType: envelope.entityType, entityId: envelope.entityId, object: &object)
    normalizeTaskRegisterDefaults(
      entityType: envelope.entityType, supplied: supplied,
      version: envelope.version, object: &object)
    normalizeCalendarRegisterDefaults(
      entityType: envelope.entityType, supplied: supplied,
      version: envelope.version, object: &object)

    let completed = SyncEnvelope(
      entityType: envelope.entityType,
      entityId: envelope.entityId,
      operation: envelope.operation,
      version: envelope.version,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: try canonicalizeJSON(.object(object)),
      deviceId: envelope.deviceId)
    try SyncPayloadContractRegistry.validate(completed)
    return completed
  }

  private static func loadGoldenPayloads() throws -> [EntityKind: [String: JSONValue]] {
    let data = try Data(contentsOf: goldenFixtureURL())
    guard let raw = String(data: data, encoding: .utf8),
      case .object(let root)? = JSONValue.parse(raw),
      case .array(let envelopes)? = root["envelopes"]
    else {
      throw NSError(
        domain: "CurrentSyncEnvelopeTestSupport", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "invalid golden sync fixture"])
    }
    var result: [EntityKind: [String: JSONValue]] = [:]
    for value in envelopes {
      guard case .object(let envelope) = value,
        envelope["operation"] == .string("upsert"),
        case .string(let rawType)? = envelope["entity_type"],
        let entityType = EntityKind.parse(rawType),
        case .object(let payload)? = envelope["payload"]
      else { continue }
      result[entityType] = payload
    }
    return result
  }

  private static func goldenFixtureURL(file: StaticString = #filePath) throws -> URL {
    var directory = URL(fileURLWithPath: String(describing: file)).deletingLastPathComponent()
    let fm = FileManager.default
    while directory.path != "/" {
      let candidate = directory.appendingPathComponent(
        "schema/sync_payload/fixtures/001.golden.json")
      if fm.fileExists(atPath: candidate.path) { return candidate }
      directory.deleteLastPathComponent()
    }
    throw NSError(
      domain: "CurrentSyncEnvelopeTestSupport", code: 2,
      userInfo: [NSLocalizedDescriptionKey: "golden sync fixture not found"])
  }

  private static func merge(
    _ base: [String: JSONValue], overlay: [String: JSONValue]
  ) -> [String: JSONValue] {
    var result = base
    for (key, value) in overlay {
      if case .object(let baseObject)? = result[key], case .object(let overlayObject) = value {
        result[key] = .object(merge(baseObject, overlay: overlayObject))
      } else {
        // Arrays are complete aggregate content, never partial golden overlays.
        result[key] = value
      }
    }
    return result
  }

  private static func normalizeTimestamps(
    _ object: [String: JSONValue]
  ) -> [String: JSONValue] {
    object.mapValues(normalizeTimestamps)
  }

  private static func normalizeTimestamps(_ value: JSONValue) -> JSONValue {
    switch value {
    case .string(let raw):
      return SyncTimestamp.parse(raw).map { .string($0.asString) } ?? value
    case .array(let values):
      return .array(values.map(normalizeTimestamps))
    case .object(let object):
      return .object(normalizeTimestamps(object))
    default:
      return value
    }
  }

  private static func rewriteIdentity(
    entityType: EntityKind, entityId: String, object: inout [String: JSONValue]
  ) {
    switch entityType {
    case .task, .list, .habit, .tag, .calendarEvent, .calendarSeriesCutover, .memory,
      .taskReminder, .taskChecklistItem, .habitReminderPolicy:
      object["id"] = .string(entityId)
    case .preference:
      object["key"] = .string(entityId)
    case .dailyReview, .currentFocus, .focusSchedule:
      object["date"] = .string(entityId)
    case .taskTag, .taskDependency, .taskCalendarEventLink, .habitCompletion:
      guard case .success(let pair) = CompositeEdge.splitCompositeEdgeId(entityId) else { return }
      switch entityType {
      case .taskTag:
        object["task_id"] = .string(pair.0)
        object["tag_id"] = .string(pair.1)
      case .taskDependency:
        object["task_id"] = .string(pair.0)
        object["depends_on_task_id"] = .string(pair.1)
      case .taskCalendarEventLink:
        object["task_id"] = .string(pair.0)
        object["calendar_event_id"] = .string(pair.1)
      case .habitCompletion:
        object["habit_id"] = .string(pair.0)
        object["completed_date"] = .string(pair.1)
      default:
        break
      }
    case .aiChangelog, .entityRedirect, .deviceState, .importSession:
      break
    }
  }

  /// The golden task fixture carries one concrete register history. Terse
  /// facade fixtures describe a fresh snapshot instead, so absent task clocks
  /// and lifecycle provenance must be derived from the target envelope rather
  /// than inherited from that unrelated golden row.
  private static func normalizeTaskRegisterDefaults(
    entityType: EntityKind, supplied: [String: JSONValue],
    version: Hlc, object: inout [String: JSONValue]
  ) {
    guard entityType == .task else { return }
    let versionValue = JSONValue.string(version.description)
    for key in [
      "content_version", "schedule_version", "lifecycle_version", "archive_version",
    ] where supplied[key] == nil {
      object[key] = versionValue
    }

    if supplied["spawned_from_version"] == nil {
      if case .string? = object["spawned_from"] {
        object["spawned_from_version"] = versionValue
      } else {
        object["spawned_from_version"] = .null
      }
    }
    if supplied["recurrence_rollover_state"] == nil {
      let isTerminal =
        object["status"] == .string("completed") || object["status"] == .string("cancelled")
      object["recurrence_rollover_state"] = .string(isTerminal ? "ended" : "none")
    }
    if supplied["recurrence_successor_id"] == nil {
      object["recurrence_successor_id"] = .null
    }
  }

  /// The golden calendar fixture is a recurring master, while many facade
  /// tests intentionally provide a sparse plain event or occurrence decision.
  /// Complete the grouped-register clocks from the target envelope rather than
  /// leaking the golden row's unrelated HLCs into those shapes.
  private static func normalizeCalendarRegisterDefaults(
    entityType: EntityKind, supplied: [String: JSONValue],
    version: Hlc, object: inout [String: JSONValue]
  ) {
    guard entityType == .calendarEvent else { return }
    object["recurrence_exceptions"] = nil
    let versionValue = JSONValue.string(version.description)
    let isDecision: Bool
    if case .string? = object["series_id"] {
      isDecision = true
    } else {
      isDecision = false
    }

    if supplied["content_version"] == nil {
      object["content_version"] = isDecision ? .null : versionValue
    }
    if supplied["recurrence_topology_version"] == nil {
      object["recurrence_topology_version"] = isDecision ? .null : versionValue
    }
    if supplied["recurrence_generation"] == nil {
      let hasRecurrence: Bool
      if case .string? = object["recurrence"] {
        hasRecurrence = true
      } else {
        hasRecurrence = false
      }
      object["recurrence_generation"] =
        isDecision || hasRecurrence ? versionValue : .null
    }
    if supplied["occurrence_state"] == nil, !isDecision {
      object["occurrence_state"] = .null
    }
  }

  private static func neutralizeGoldenDefaults(
    entityType: EntityKind, object: inout [String: JSONValue]
  ) {
    switch entityType {
    case .task:
      object.merge([
        "ai_notes": .null,
        "archived_at": .null,
        "available_from": .null,
        "body": .null,
        "canonical_occurrence_date": .null,
        "completed_at": .null,
        "defer_count": .int(0),
        "due_date": .null,
        "estimated_minutes": .null,
        "last_defer_reason": .null,
        "last_deferred_at": .null,
        "planned_date": .null,
        "priority": .null,
        "raw_input": .null,
        "recurrence": .null,
        "recurrence_exceptions": .null,
        "recurrence_group_id": .null,
        "recurrence_instance_key": .null,
        "spawned_from": .null,
        "status": .string("open"),
      ], uniquingKeysWith: { _, neutral in neutral })
    case .calendarEvent:
      object.merge([
        "attendees": .null,
        "color": .null,
        "description": .null,
        "end_date": .null,
        "end_time": .null,
        "location": .null,
        "occurrence_state": .null,
        "person_name": .null,
        "recurrence": .null,
        "recurrence_generation": .null,
        "recurrence_instance_date": .null,
        "series_cutover_id": .null,
        "series_id": .null,
        "url": .null,
      ], uniquingKeysWith: { _, neutral in neutral })
    case .list:
      object.merge([
        "ai_notes": .null,
        "archived_at": .null,
        "color": .null,
        "description": .null,
        "icon": .null,
        "position": .int(0),
      ], uniquingKeysWith: { _, neutral in neutral })
    case .habit:
      object.merge([
        "archived": .bool(false),
        "color": .null,
        "cue": .null,
        "day_of_month": .null,
        "icon": .null,
        "milestone_target": .null,
        "per_period_target": .int(1),
        "position": .int(0),
        "weekdays": .array([]),
      ], uniquingKeysWith: { _, neutral in neutral })
    case .tag:
      object["color"] = .null
    case .taskChecklistItem:
      object["completed_at"] = .null
    case .currentFocus:
      object["task_ids"] = .array([])
    case .focusSchedule:
      object["blocks"] = .array([])
    case .dailyReview:
      object["linked_list_ids"] = .array([])
      object["linked_task_ids"] = .array([])
    default:
      break
    }
  }
}
