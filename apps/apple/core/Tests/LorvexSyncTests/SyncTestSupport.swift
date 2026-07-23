import Foundation
import GRDB
import LorvexDomain

@testable import LorvexStore
@testable import LorvexSync

/// Shared helpers for `LorvexSyncTests`. Mirrors `LorvexStoreTests.TestSupport`
/// so DB-backed sync tests can seed against the authoritative schema.
enum SyncTestSupport {
  /// Load the authoritative root `schema/schema.sql` via a `#filePath`-relative
  /// walk. Layout:
  /// `apps/apple/core/Tests/LorvexSyncTests/<file>.swift` →
  /// `<repo>/lorvex/schema/schema.sql` (5 levels up).
  static func loadSchemaSQL(file: StaticString = #filePath) throws -> String {
    var path = (String(describing: file) as NSString).deletingLastPathComponent
    for _ in 0..<5 {
      path = (path as NSString).deletingLastPathComponent
    }
    let schemaPath = (path as NSString).appendingPathComponent("schema/schema.sql")
    return try String(contentsOfFile: schemaPath, encoding: .utf8)
  }

  /// Fresh in-memory store with the authoritative schema applied.
  static func freshStore(file: StaticString = #filePath) throws -> LorvexStore {
    let sql = try loadSchemaSQL(file: file)
    return try LorvexStore.openInMemory(schemaSQL: sql)
  }

  /// Seed one deliberately corrupt persisted row for repair-path coverage.
  /// The production schema rejects such rows; keep the constraint bypass
  /// scoped to the exact seed closure and restore enforcement before the
  /// behavior under test runs.
  static func seedIgnoringCheckConstraints<T>(
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

  /// Insert a non-coalesced outbox row for retry/GC bookkeeping tests.
  /// Production code exposes no unchecked enqueue surface; tests keep this raw
  /// seed local to the test target so sparse fixtures cannot become a runtime
  /// manifest bypass.
  static func insertOutboxEnvelopeUnchecked(
    _ db: Database, _ envelope: SyncEnvelope
  ) throws {
    if case .failure(let error) = envelope.validate() {
      throw Outbox.OutboxError.sql(
        "sync_outbox test seed rejected malformed envelope: \(error.message)")
    }
    try Outbox.requireOperationalWireVersion(envelope)
    try db.execute(
      sql: """
        INSERT INTO sync_outbox
          (entity_type, entity_id, operation, version, payload_schema_version,
           payload, device_id, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        envelope.entityType.asString,
        envelope.entityId,
        envelope.operation.asString,
        envelope.version.description,
        envelope.payloadSchemaVersion,
        envelope.payload,
        envelope.deviceId,
        SyncTimestampFormat.syncTimestampNow(),
      ])
  }

  static func cloudTraversalBoundary(
    accountIdentifier: String, zoneIdentifier: String, generation: Int = 1,
    generationIdentifier: String = "test-generation",
    readyWitness: String = "test-ready-witness"
  ) throws -> CloudTraversalBoundary {
    try CloudTraversalBoundary(
      accountIdentifier: accountIdentifier, zoneIdentifier: zoneIdentifier,
      generation: generation, generationIdentifier: generationIdentifier,
      readyWitness: readyWitness)
  }

  /// Seed the two independent records produced by an identity merge. Tests use
  /// the production alias writer so wire shape, monotonic join, and outbox
  /// behavior stay covered; the ordinary loser death barrier remains separate.
  static func seedEntityRedirect(
    _ db: Database, sourceType: EntityKind, sourceId: String, targetId: String,
    version: String, createdAt: String = "2026-01-01T00:00:00.000Z"
  ) throws {
    _ = try EntityRedirect.upsertAndEnqueue(
      db, sourceType: sourceType, sourceId: sourceId, targetId: targetId,
      version: version, createdAt: createdAt,
      deviceId: "00000000-0000-7000-8000-000000000001")
    try Tombstone.createTombstone(
      db, entityType: sourceType.asString, entityId: sourceId,
      version: version, deletedAt: createdAt)
  }

  /// Complete a deliberately terse test payload from the numbered golden
  /// contract before it crosses the production Apply/outbox preflight.
  ///
  /// Older sync tests often specified only the fields relevant to the behavior
  /// under test. That was safe while Apply decoded payloads ad hoc, but it no
  /// longer represents a real wire envelope now that the complete manifest is
  /// enforced at the boundary. This helper keeps those tests focused without
  /// weakening production validation: the supplied object wins over the golden
  /// payload, identity/version fields are tied to the envelope, and the final
  /// result is validated by the same production registry.
  static func completeEnvelope(
    entityType: EntityKind, entityId: String, operation: SyncOperation,
    version: Hlc, payloadSchemaVersion: UInt32, payload: String, deviceId: String
  ) throws -> SyncEnvelope {
    guard case .object(let supplied)? = JSONValue.parse(payload) else {
      return SyncEnvelope(
        entityType: entityType, entityId: entityId, operation: operation,
        version: version, payloadSchemaVersion: payloadSchemaVersion,
        payload: payload, deviceId: deviceId)
    }

    let contractVersion = min(payloadSchemaVersion, LorvexVersion.payloadSchemaVersion)
    let contract = try SyncPayloadContractFixture.load(version: contractVersion)
    guard let entityContract = contract.entities[entityType.asString] else {
      return SyncEnvelope(
        entityType: entityType, entityId: entityId, operation: operation,
        version: version, payloadSchemaVersion: payloadSchemaVersion,
        payload: payload, deviceId: deviceId)
    }

    var object: [String: JSONValue]
    switch operation {
    case .upsert:
      guard
        let golden = try SyncPayloadContractFixture.goldenEnvelopes(contract: contract)
          .first(where: { $0.entityType == entityType }),
        case .object(var goldenObject)? = JSONValue.parse(golden.payload)
      else {
        throw NSError(
          domain: "SyncTestSupport", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "missing golden payload for \(entityType.asString)"]
        )
      }
      neutralizeGoldenDefaults(entityType: entityType, object: &goldenObject)
      guard case .object(let merged) = merge(.object(goldenObject), overlaidBy: .object(supplied))
      else { preconditionFailure("object merge must produce an object") }
      object = merged
    case .delete:
      object = supplied
    }

    // lookup_key is a persisted normalization aid, never a wire field.
    object["lookup_key"] = nil
    object["version"] = .string(version.description)
    rewriteIdentity(entityType: entityType, entityId: entityId, object: &object)
    if entityType == .task {
      for clock in [
        "content_version", "schedule_version", "lifecycle_version", "archive_version",
      ] where supplied[clock] == nil {
        object[clock] = .string(version.description)
      }
    } else if entityType == .calendarEvent {
      let isDecision: Bool
      if case .some(.string(_)) = object["series_id"] {
        isDecision = true
      } else {
        isDecision = false
      }
      if supplied["content_version"] == nil {
        object["content_version"] = isDecision ? .null : .string(version.description)
      }
      if supplied["recurrence_topology_version"] == nil {
        object["recurrence_topology_version"] = isDecision ? .null : .string(version.description)
      }
    }
    object = normalize(object: object, fields: entityContract.fields)

    let completed = SyncEnvelope(
      entityType: entityType, entityId: entityId, operation: operation,
      version: version, payloadSchemaVersion: payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)), deviceId: deviceId)
    try SyncPayloadContractRegistry.validate(completed)
    return completed
  }

  private static func merge(_ base: JSONValue, overlaidBy overlay: JSONValue) -> JSONValue {
    switch (base, overlay) {
    case (.object(let baseObject), .object(let overlayObject)):
      var result = baseObject
      for (key, value) in overlayObject {
        result[key] = result[key].map { merge($0, overlaidBy: value) } ?? value
      }
      return .object(result)
    case (.array, .array):
      // Arrays are aggregate content, not partial dictionaries. Reusing a
      // golden element here would silently add attendee/block content that the
      // test did not author.
      return overlay
    default:
      return overlay
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

  /// Golden fixtures are intentionally populated contract examples. A terse
  /// behavior fixture needs valid *neutral* omissions instead: completing a
  /// plain task must not make it recurring/cancelled, and completing a plain
  /// calendar event must not turn it into a recurring series.
  private static func neutralizeGoldenDefaults(
    entityType: EntityKind, object: inout [String: JSONValue]
  ) {
    switch entityType {
    case .task:
      object["ai_notes"] = .null
      object["archived_at"] = .null
      object["available_from"] = .null
      object["body"] = .null
      object["canonical_occurrence_date"] = .null
      object["completed_at"] = .null
      object["defer_count"] = .int(0)
      object["due_date"] = .null
      object["estimated_minutes"] = .null
      object["last_defer_reason"] = .null
      object["last_deferred_at"] = .null
      object["planned_date"] = .null
      object["priority"] = .int(1)
      object["raw_input"] = .null
      object["recurrence"] = .null
      object["recurrence_exceptions"] = .null
      object["recurrence_group_id"] = .null
      object["recurrence_instance_key"] = .null
      object["recurrence_rollover_state"] = .string("none")
      object["recurrence_successor_id"] = .null
      object["spawned_from"] = .null
      object["spawned_from_version"] = .null
      object["status"] = .string("open")
    case .calendarEvent:
      object["attendees"] = .null
      object["color"] = .null
      object["description"] = .null
      object["end_date"] = .null
      object["end_time"] = .null
      object["location"] = .null
      object["person_name"] = .null
      object["recurrence"] = .null
      object["recurrence_generation"] = .null
      object["recurrence_instance_date"] = .null
      object["occurrence_state"] = .null
      object["series_cutover_id"] = .null
      object["series_id"] = .null
      object["url"] = .null
    case .taskChecklistItem:
      object["completed_at"] = .null
    case .currentFocus:
      object["task_ids"] = .array([])
    case .dailyReview:
      object["linked_list_ids"] = .array([])
      object["linked_task_ids"] = .array([])
    default:
      break
    }
  }

  private static func normalize(
    object: [String: JSONValue], fields: [String: SyncPayloadFieldContract]
  ) -> [String: JSONValue] {
    object.mapValues { value in value }.reduce(into: [:]) { result, entry in
      guard let field = fields[entry.key] else {
        result[entry.key] = entry.value
        return
      }
      result[entry.key] = normalize(value: entry.value, field: field)
    }
  }

  private static func normalize(
    value: JSONValue, field: SyncPayloadFieldContract
  ) -> JSONValue {
    if field.format == "rfc3339-utc", case .string(let raw) = value,
      let timestamp = SyncTimestamp.parse(raw)
    {
      return .string(timestamp.asString)
    }
    if case .array(let values) = value, let item = field.items {
      return .array(values.map { normalize(value: $0, field: item) })
    }
    if case .object(let object) = value, let properties = field.properties {
      return .object(normalize(object: object, fields: properties))
    }
    return value
  }

}
