import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Apply-path coverage for the calendar_event aggregate: the `attendees` JSON
/// annotation column (verbatim-stored last-writer-wins, no per-attendee identity
/// or shadow) and the delete cascade-does-not-run-on-LWW-reject regression.
final class ApplyCalendarEventTests: XCTestCase {

  private var versionCounter = 0
  private func nextVersion() -> String {
    versionCounter += 1
    return String(format: "1711234%06d_0000_dec0000100000001", versionCounter)
  }

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func eventPayload(attendees: JSONValue) -> String {
    let obj: JSONValue = .object([
      "title": .string("Standup"),
      "start_date": .string("2026-04-20"),
      "start_time": .string("09:00"),
      "all_day": .bool(false),
      "event_type": .string("event"),
      "occurrence_state": .null,
      "recurrence": .null,
      "recurrence_generation": .null,
      "recurrence_instance_date": .null,
      "content_version": .string("1711234000000_0000_dec0000100000001"),
      "recurrence_topology_version": .string("1711234000000_0000_dec0000100000001"),
      "series_cutover_id": .null,
      "series_id": .null,
      "created_at": .string("2026-04-20T09:00:00.000Z"),
      "updated_at": .string("2026-04-20T09:00:00.000Z"),
      "attendees": attendees,
    ])
    return try! SyncCanonicalize.canonicalizeJSON(obj)
  }

  private func upsert(_ db: Database, _ eventId: String, _ payload: String) throws {
    let version = nextVersion()
    guard case .object(var object)? = JSONValue.parse(payload) else {
      return XCTFail("calendar payload must be an object")
    }
    object["content_version"] = .string(version)
    try ApplyCalendarEvent.applyCalendarEventUpsert(
      db, entityId: eventId,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)), version: version,
      tieBreak: .rejectEqual,
      applyTs: "2026-04-20T09:00:00.000Z")
  }

  private func attendeesColumn(_ db: Database, _ eventId: String) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT attendees FROM calendar_events WHERE id = ?", arguments: [eventId])
  }

  /// A canonical calendar_event payload that OMITS the `attendees` key entirely
  /// (an older peer that predates attendees, or a partial edit that did not
  /// mention them).
  private func eventPayloadNoAttendees() -> String {
    let obj: JSONValue = .object([
      "title": .string("Standup"),
      "start_date": .string("2026-04-20"),
      "start_time": .string("09:00"),
      "all_day": .bool(false),
      "event_type": .string("event"),
      "occurrence_state": .null,
      "recurrence": .null,
      "recurrence_generation": .null,
      "recurrence_instance_date": .null,
      "content_version": .string("1711234000000_0000_dec0000100000001"),
      "recurrence_topology_version": .string("1711234000000_0000_dec0000100000001"),
      "series_cutover_id": .null,
      "series_id": .null,
      "created_at": .string("2026-04-20T09:00:00.000Z"),
      "updated_at": .string("2026-04-20T09:00:00.000Z"),
    ])
    return try! SyncCanonicalize.canonicalizeJSON(obj)
  }

  // MARK: - attendees JSON column (plain last-writer-wins)

  /// An array of `{email, name}` pairs is stored verbatim (canonicalized) in the
  /// `attendees` column and parses back into the same pairs.
  func testAttendeesArrayStoredVerbatimInColumn() throws {
    try withDB { db in
      let eventId = "evt-attendees-verbatim"
      let attendees: JSONValue = .array([
        .object(["email": .string("alice@example.com"), "name": .string("Alice")]),
        .object(["name": .string("Bob")]),
      ])
      try self.upsert(db, eventId, self.eventPayload(attendees: attendees))
      let stored = try XCTUnwrap(try self.attendeesColumn(db, eventId))
      XCTAssertEqual(JSONValue.parse(stored), attendees)
      // The column must be the canonical (sorted-key) form of the wire array.
      XCTAssertEqual(stored, try SyncCanonicalize.canonicalizeJSON(attendees))
    }
  }

  /// Unknown per-attendee sub-keys a newer peer emits round-trip because the
  /// array is stored verbatim — no bespoke shadow, no stripping.
  func testUnknownAttendeeSubKeysRoundTripVerbatim() throws {
    try withDB { db in
      let eventId = "evt-attendees-forwardcompat"
      let attendees: JSONValue = .array([
        .object([
          "email": .string("alice@example.com"), "name": .string("Alice"),
          "role": .string("chair"), "rsvp_deadline": .string("2026-04-19T17:00:00Z"),
        ])
      ])
      try self.upsert(db, eventId, self.eventPayload(attendees: attendees))
      let stored = try XCTUnwrap(JSONValue.parse(try XCTUnwrap(self.attendeesColumn(db, eventId))))
      guard case let .array(items) = stored, case let .object(att) = items.first else {
        return XCTFail("attendees column must parse to an array of objects")
      }
      XCTAssertEqual(att["role"], .string("chair"))
      XCTAssertEqual(att["rsvp_deadline"], .string("2026-04-19T17:00:00Z"))
    }
  }

  /// A later envelope that OMITS `attendees` clears the column — a plain
  /// last-writer-wins column, not absence-preserving.
  func testEnvelopeOmittingAttendeesClearsColumn() throws {
    try withDB { db in
      let eventId = "evt-attendees-omit-clears"
      try self.upsert(
        db, eventId,
        self.eventPayload(attendees: .array([.object(["email": .string("alice@example.com")])])))
      XCTAssertNotNil(try self.attendeesColumn(db, eventId))

      try self.upsert(db, eventId, self.eventPayloadNoAttendees())
      XCTAssertNil(
        try self.attendeesColumn(db, eventId),
        "omitting attendees clears the column like any other plain LWW column")
    }
  }

  /// An explicit empty array — and JSON `null` — both store NULL (none).
  func testEmptyAndNullAttendeesStoreNull() throws {
    try withDB { db in
      let eventId = "evt-attendees-empty"
      try self.upsert(
        db, eventId,
        self.eventPayload(attendees: .array([.object(["email": .string("alice@example.com")])])))
      XCTAssertNotNil(try self.attendeesColumn(db, eventId))

      try self.upsert(db, eventId, self.eventPayload(attendees: .array([])))
      XCTAssertNil(try self.attendeesColumn(db, eventId), "an empty array stores NULL")

      try self.upsert(
        db, eventId,
        self.eventPayload(attendees: .array([.object(["name": .string("Bob")])])))
      XCTAssertNotNil(try self.attendeesColumn(db, eventId))

      try self.upsert(db, eventId, self.eventPayload(attendees: .null))
      XCTAssertNil(try self.attendeesColumn(db, eventId), "JSON null stores NULL")
    }
  }

  /// A later envelope replaces the whole array (last-writer-wins).
  func testAttendeesUpdateReplacesColumn() throws {
    try withDB { db in
      let eventId = "evt-attendees-replace"
      try self.upsert(
        db, eventId,
        self.eventPayload(attendees: .array([.object(["email": .string("alice@example.com")])])))
      let replacement: JSONValue = .array([.object(["email": .string("bob@example.com")])])
      try self.upsert(db, eventId, self.eventPayload(attendees: replacement))
      XCTAssertEqual(
        JSONValue.parse(try XCTUnwrap(self.attendeesColumn(db, eventId))), replacement)
    }
  }

  /// A non-object attendee entry is a shape error at the trust boundary.
  func testNonObjectAttendeeEntryRejected() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try self.upsert(
          db, "evt-attendees-bad-shape",
          self.eventPayload(attendees: .array([.int(1)]))))
    }
  }

  /// The `attendees` column survives an outbound (payload rebuild) → inbound
  /// (re-apply) envelope round-trip byte-for-byte, like any other LWW column.
  func testAttendeesColumnSurvivesOutboundInboundRoundTrip() throws {
    try withDB { db in
      let src = "evt-attendees-roundtrip-src"
      let attendees: JSONValue = .array([
        .object(["email": .string("alice@example.com"), "name": .string("Alice")]),
        .object(["name": .string("Bob"), "role": .string("guest")]),
      ])
      try self.upsert(db, src, self.eventPayload(attendees: attendees))
      let srcColumn = try XCTUnwrap(try self.attendeesColumn(db, src))

      // Enqueue: rebuild the aggregate wire payload (the outbound form).
      let payload = try XCTUnwrap(
        try PayloadBuild.buildAggregatePayload(
          db, entityType: EntityName.calendarEvent, entityId: src))
      guard case let .object(obj) = payload, case let .array(atts)? = obj["attendees"] else {
        return XCTFail("rebuilt payload must embed attendees")
      }

      // Apply the rebuilt attendees to a fresh event (peer re-materialization).
      let dst = "evt-attendees-roundtrip-dst"
      try self.upsert(db, dst, self.eventPayload(attendees: .array(atts)))
      let dstColumn = try XCTUnwrap(try self.attendeesColumn(db, dst))

      XCTAssertEqual(dstColumn, srcColumn, "attendees column must survive the wire round-trip")
    }
  }

  // MARK: - delete cascade gate

  func testCascadeDoesNotRunWhenByteCompareFallbackRejectsLegacyLocalVersion() throws {
    try withDB { db in
      let eventId = "00000000-0000-7000-8000-000000004001"
      let taskId = "00000000-0000-7000-8000-000000004002"
      let canonicalVersion = "1711234599000_0000_dec0000200000002"
      let legacyLocal = "v1"

      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO calendar_events (id, title, start_date, all_day, version, created_at, updated_at)
            VALUES (?, 'meeting', '2026-04-01', 0, ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
            """,
          arguments: [eventId, legacyLocal])
      }
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, version, created_at, updated_at, defer_count)
          VALUES (?, 'T', 'open', ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0)
          """,
        arguments: [taskId, canonicalVersion])
      try db.execute(
        sql: """
          INSERT INTO task_calendar_event_links (task_id, calendar_event_id, version, created_at, updated_at)
          VALUES (?, ?, ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
          """,
        arguments: [taskId, eventId, canonicalVersion])

      let result = try ApplyCalendarEvent.applyCalendarEventDeleteWithRepairs(
        db, entityId: eventId, version: canonicalVersion, applyTs: "2026-04-01T00:00:00.000Z")
      guard case .rejected = result.decision else {
        return XCTFail("byte-compare fallback must surface as rejected, got \(result.decision)")
      }
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM calendar_events WHERE id = ?", arguments: [eventId]), 1)
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_tombstones
             WHERE entity_type = 'task_calendar_event_link' AND entity_id = ?
            """,
          arguments: ["\(taskId):\(eventId)"]), 0)
    }
  }
}
