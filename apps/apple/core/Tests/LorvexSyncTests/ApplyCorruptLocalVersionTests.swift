import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Regression coverage for the inbound-UPSERT-vs-corrupt-local-version gap.
///
/// The outer LWW gate treats an UNPARSEABLE local `version` as "absent" and lets
/// a canonical envelope land. But the per-entity handlers RE-gate the write in
/// raw SQL (`WHERE excluded.version > table.version` / `:version > version`), a
/// byte compare. A corrupt local string that lex-sorts above canonical HLCs
/// (letters sort above digits) made the UPDATE match zero rows while apply still
/// reported `.applied` — the change token advanced, no conflict/error row was
/// written, and the row was permanently deaf to inbound sync until a local edit
/// re-stamped it. These tests pin that a canonical inbound upsert now lands over
/// a corrupt local version AND re-stamps it canonical, while a genuine
/// canonical-vs-canonical LWW loss still no-ops.
final class ApplyCorruptLocalVersionTests: XCTestCase {

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func registry() -> EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  /// A non-canonical version string that byte-sorts ABOVE every canonical HLC
  /// (canonical HLCs begin with a digit; `z` = 0x7a > `9` = 0x39).
  private static let corruptLexHighVersion = "zzz-corrupt"
  private static let canonicalVersion = "1711234567000_0000_dec0000100000001"

  // MARK: - Generic LwwUpsertSpec gate (list)

  func testCanonicalUpsertLandsOverCorruptLocalListVersion() throws {
    try withDB { db in
      let listId = "00000000-0000-7000-8000-0000000000d1"
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO lists (id, name, version, created_at, updated_at)
            VALUES (?, 'stale-name', ?, '2026-04-19T08:00:00.000Z',
                    '2026-04-19T08:00:00.000Z')
            """,
          arguments: [listId, Self.corruptLexHighVersion])
      }

      let payload = try SyncCanonicalize.canonicalizeJSON(.object([
        "name": .string("fresh-name"),
        "created_at": .string("2026-04-19T08:00:00.000Z"),
        "updated_at": .string("2026-04-19T09:00:00.000Z"),
      ]))
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .list, entityId: listId, operation: .upsert,
        version: try Hlc.parse(Self.canonicalVersion),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device")

      let result = try Apply.applyEnvelope(db, registry: self.registry(), envelope: envelope)

      XCTAssertEqual(result, .applied)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT name FROM lists WHERE id = ?", arguments: [listId]),
        "fresh-name", "canonical upsert must overwrite the corrupt-versioned row")
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT version FROM lists WHERE id = ?", arguments: [listId]),
        Self.canonicalVersion, "row version must be re-stamped canonical, not left corrupt")
    }
  }

  // MARK: - Task-specific taskUpdateSQL gate

  func testCanonicalUpsertLandsOverCorruptLocalTaskVersion() throws {
    try withDB { db in
      let taskId = "00000000-0000-7000-8000-0000000000d2"
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO tasks (
                id, list_id, title, status, content_version, schedule_version,
                lifecycle_version, archive_version, version, created_at, updated_at, defer_count
            )
            VALUES (?, 'inbox', 'stale-title', 'open', ?, ?, ?, ?, ?,
                    '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z', 0)
            """,
          arguments: [
            taskId, Self.corruptLexHighVersion, Self.corruptLexHighVersion,
            Self.corruptLexHighVersion, Self.corruptLexHighVersion,
            Self.corruptLexHighVersion,
          ])
      }

      let payload = try SyncCanonicalize.canonicalizeJSON(.object([
        "title": .string("fresh-title"),
        "status": .string("open"),
        "list_id": .string("inbox"),
        "created_at": .string("2026-04-19T08:00:00.000Z"),
        "updated_at": .string("2026-04-19T09:00:00.000Z"),
      ]))
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .task, entityId: taskId, operation: .upsert,
        version: try Hlc.parse(Self.canonicalVersion),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device")

      let result = try Apply.applyEnvelope(db, registry: self.registry(), envelope: envelope)

      XCTAssertEqual(result, .applied)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [taskId]),
        "fresh-title", "canonical upsert must overwrite the corrupt-versioned task")
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [taskId]),
        Self.canonicalVersion, "task version must be re-stamped canonical, not left corrupt")
    }
  }

  // MARK: - Calendar grouped-register reset

  func testCanonicalUpsertClearsCorruptCalendarRowAndRegisterClocksTogether() throws {
    try withDB { db in
      let eventId = "00000000-0000-7000-8000-0000000000d4"
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO calendar_events
              (id, title, start_date, start_time, all_day, event_type,
               content_version, recurrence_topology_version, version, created_at, updated_at)
            VALUES (?, 'stale-title', '2026-04-19', '08:00', 0, 'event', ?, ?, ?,
                    '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z')
            """,
          arguments: [
            eventId, Self.corruptLexHighVersion, Self.corruptLexHighVersion,
            Self.corruptLexHighVersion,
          ])
      }

      let payload = try SyncCanonicalize.canonicalizeJSON(.object([
        "title": .string("fresh-title"), "start_date": .string("2026-04-19"),
        "start_time": .string("09:00"), "all_day": .bool(false),
        "event_type": .string("event"),
        "created_at": .string("2026-04-19T08:00:00.000Z"),
        "updated_at": .string("2026-04-19T09:00:00.000Z"),
      ]))
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .calendarEvent, entityId: eventId, operation: .upsert,
        version: try Hlc.parse(Self.canonicalVersion),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device")

      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: envelope), .applied)
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT title, content_version, recurrence_topology_version, version
              FROM calendar_events WHERE id = ?
            """,
          arguments: [eventId]))
      XCTAssertEqual(row["title"] as String, "fresh-title")
      XCTAssertEqual(row["content_version"] as String, Self.canonicalVersion)
      XCTAssertEqual(row["recurrence_topology_version"] as String, Self.canonicalVersion)
      XCTAssertEqual(row["version"] as String, Self.canonicalVersion)
    }
  }

  // MARK: - Regression guard: genuine canonical-vs-canonical LWW loss still no-ops

  func testCanonicalOlderUpsertStillNoOpsAgainstCanonicalLocal() throws {
    try withDB { db in
      let taskId = "00000000-0000-7000-8000-0000000000d3"
      let newerLocal = "1711234569999_0000_dec0000100000001"
      let olderIncoming = "1711234560000_0000_dec0000100000001"
      try db.execute(
        sql: """
          INSERT INTO tasks (
              id, list_id, title, status, content_version, schedule_version,
              lifecycle_version, archive_version, version, created_at, updated_at, defer_count
          )
          VALUES (?, 'inbox', 'local-title', 'open', ?, ?, ?, ?, ?,
                  '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z', 0)
          """,
        arguments: [taskId, newerLocal, newerLocal, newerLocal, newerLocal, newerLocal])

      let payload = try SyncCanonicalize.canonicalizeJSON(.object([
        "title": .string("stale-remote-title"),
        "status": .string("open"),
        "list_id": .string("inbox"),
        "created_at": .string("2026-04-19T08:00:00.000Z"),
        "updated_at": .string("2026-04-19T07:00:00.000Z"),
      ]))
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .task, entityId: taskId, operation: .upsert,
        version: try Hlc.parse(olderIncoming),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device")

      let result = try Apply.applyEnvelope(db, registry: self.registry(), envelope: envelope)

      guard case .skipped = result else {
        return XCTFail("stale canonical upsert must be skipped, got \(result)")
      }
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [taskId]),
        "local-title", "newer local row must survive the stale upsert unchanged")
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [taskId]),
        newerLocal, "local version must be preserved")
    }
  }
}
