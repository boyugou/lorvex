import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports the parity `#[test]` cases for the `task` aggregate applier:
/// `build_task_row` (partial-update tri-state, validators, list_id fallback,
/// defer_count default), the `update_sql` / INSERT byte-shape tests, and the
/// `apply_task_delete` cascade-tombstone + LWW-gate behaviors.
final class ApplyTaskTests: XCTestCase {

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private static let taskId = "00000000-0000-7000-8000-000000000099"
  private static let version = "1711234567000_0000_dec0000100000001"

  private func minimalPayload(_ overrides: [String: JSONValue] = [:]) -> String {
    var obj: [String: JSONValue] = [
      "title": .string("task title"),
      "status": .string("open"),
      "list_id": .string(inboxListId),
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
    ]
    for (k, v) in overrides { obj[k] = v }
    return (try? SyncCanonicalize.canonicalizeJSON(.object(obj))) ?? "{}"
  }

  /// Like `minimalPayload` but allows removing a key (e.g. omit `list_id`).
  private func payloadWithout(_ key: String) -> String {
    var obj: [String: JSONValue] = [
      "title": .string("task title"),
      "status": .string("open"),
      "list_id": .string(inboxListId),
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
    ]
    obj[key] = nil
    return (try? SyncCanonicalize.canonicalizeJSON(.object(obj))) ?? "{}"
  }

  private func buildRow(_ db: Database, _ payload: String) throws -> ApplyTask.TaskRow {
    try ApplyTask.buildTaskRow(db, taskId: Self.taskId, payload: payload, version: Self.version)
  }

  // MARK: - build_task_row

  func testMinimalPayloadMarksEveryOptionalColumnAbsent() throws {
    try withDB { db in
      let row = try self.buildRow(db, self.minimalPayload())
      XCTAssertEqual(row.entityId, Self.taskId)
      XCTAssertEqual(row.title, "task title")
      XCTAssertEqual(row.status, "open")
      XCTAssertEqual(row.createdAt, "2026-04-01T00:00:00.000Z")
      XCTAssertEqual(row.updatedAt, "2026-04-01T00:00:00.000Z")
      XCTAssertEqual(row.version, Self.version)

      XCTAssertEqual(row.bodyPresent, 0)
      XCTAssertEqual(row.rawInputPresent, 0)
      XCTAssertEqual(row.aiNotesPresent, 0)
      XCTAssertEqual(row.priorityPresent, 0)
      XCTAssertEqual(row.dueDatePresent, 0)
      XCTAssertEqual(row.estimatedMinutesPresent, 0)
      XCTAssertEqual(row.recurrencePresent, 0)
      XCTAssertEqual(row.recurrenceExceptionsPresent, 0)
      XCTAssertEqual(row.spawnedFromPresent, 0)
      XCTAssertEqual(row.recurrenceGroupIdPresent, 0)
      XCTAssertEqual(row.canonicalOccurrenceDatePresent, 0)
      // `status` and `completed_at` are one lifecycle value. A non-completed
      // payload implicitly clears `completed_at`, even when an older peer
      // omitted the nullable companion field.
      XCTAssertEqual(row.completedAtPresent, 1)
      XCTAssertEqual(row.lastDeferredAtPresent, 0)
      XCTAssertEqual(row.lastDeferReasonPresent, 0)
      XCTAssertEqual(row.plannedDatePresent, 0)
      XCTAssertEqual(row.deferCountPresent, 0)
      XCTAssertEqual(row.recurrenceInstanceKeyPresent, 0)
      XCTAssertEqual(row.archivedAtPresent, 0)

      XCTAssertNil(row.body)
      XCTAssertNil(row.priority)
      XCTAssertNil(row.estimatedMinutes)
      XCTAssertEqual(row.deferCount, 0)
    }
  }

  func testExplicitNullValueMarksFieldPresentWithNoneValue() throws {
    try withDB { db in
      let payload = self.minimalPayload([
        "body": .null, "priority": .null, "recurrence": .null,
      ])
      let row = try self.buildRow(db, payload)
      XCTAssertEqual(row.bodyPresent, 1)
      XCTAssertNil(row.body)
      XCTAssertEqual(row.priorityPresent, 1)
      XCTAssertNil(row.priority)
      XCTAssertEqual(row.recurrencePresent, 1)
      XCTAssertNil(row.recurrence)
    }
  }

  func testExplicitEmptyStringOnTextColumnCollapsesToClear() throws {
    try withDB { db in
      let payload = self.minimalPayload([
        "body": .string(""), "due_date": .string(""),
      ])
      let row = try self.buildRow(db, payload)
      XCTAssertEqual(row.bodyPresent, 1)
      XCTAssertNil(row.body)
      XCTAssertEqual(row.dueDatePresent, 1)
      XCTAssertNil(row.dueDate)
    }
  }

  func testExplicitValueCarriesThroughValidatedAndScrubbed() throws {
    try withDB { db in
      let payload = self.minimalPayload([
        "body": .string("hello world"), "priority": .int(2),
        "estimated_minutes": .int(45), "due_date": .string("2026-05-01"),
      ])
      let row = try self.buildRow(db, payload)
      XCTAssertEqual(row.body, "hello world")
      XCTAssertEqual(row.bodyPresent, 1)
      XCTAssertEqual(row.priority, 2)
      XCTAssertEqual(row.priorityPresent, 1)
      XCTAssertEqual(row.estimatedMinutes, 45)
      XCTAssertEqual(row.estimatedMinutesPresent, 1)
      XCTAssertEqual(row.dueDate, "2026-05-01")
    }
  }

  func testInvalidStatusYieldsTypedInvalidPayloadError() throws {
    try withDB { db in
      let payload = self.minimalPayload(["status": .string("garbage")])
      XCTAssertThrowsError(try self.buildRow(db, payload)) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("status"), "got: \(msg)")
      }
    }
  }

  func testCompletedStatusRequiresACompletionTimestamp() throws {
    try withDB { db in
      let payload = self.minimalPayload(["status": .string("completed")])
      XCTAssertThrowsError(try self.buildRow(db, payload)) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("completed_at"), "got: \(msg)")
      }
    }
  }

  func testCompletedStatusCanonicalizesItsCompletionTimestamp() throws {
    try withDB { db in
      let payload = self.minimalPayload([
        "status": .string("completed"),
        "completed_at": .string("2026-04-01T00:00:00Z"),
      ])
      let row = try self.buildRow(db, payload)
      XCTAssertEqual(row.completedAt, "2026-04-01T00:00:00.000Z")
      XCTAssertEqual(row.completedAtPresent, 1)
    }
  }

  func testCompletedStatusRejectsMalformedCompletionTimestamp() throws {
    try withDB { db in
      let payload = self.minimalPayload([
        "status": .string("completed"),
        "completed_at": .string("yesterday"),
      ])
      XCTAssertThrowsError(try self.buildRow(db, payload)) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("completed_at"), "got: \(msg)")
      }
    }
  }

  func testNonCompletedStatusRejectsACompletionTimestamp() throws {
    try withDB { db in
      let payload = self.minimalPayload([
        "status": .string("open"),
        "completed_at": .string("2026-04-01T00:00:00.000Z"),
      ])
      XCTAssertThrowsError(try self.buildRow(db, payload)) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("completed_at"), "got: \(msg)")
      }
    }
  }

  func testNonCompletedStatusImplicitlyClearsAnOmittedCompletionTimestamp() throws {
    try withDB { db in
      let row = try self.buildRow(db, self.minimalPayload())
      XCTAssertNil(row.completedAt)
      XCTAssertEqual(row.completedAtPresent, 1)
    }
  }

  func testSchemaRejectsStatusCompletionTimestampContradictions() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO tasks
              (id, title, status, list_id, version, created_at, updated_at)
            VALUES
              ('bad-completed', 'Bad', 'completed', 'inbox', ?, ?, ?)
            """,
          arguments: [Self.version, "2026-04-01T00:00:00.000Z", "2026-04-01T00:00:00.000Z"]))

      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO tasks
              (id, title, status, list_id, version, created_at, updated_at, completed_at)
            VALUES
              ('bad-open', 'Bad', 'open', 'inbox', ?, ?, ?, ?)
            """,
          arguments: [
            Self.version, "2026-04-01T00:00:00.000Z", "2026-04-01T00:00:00.000Z",
            "2026-04-01T00:00:00.000Z",
          ]))
    }
  }

  func testNegativeDeferCountIsRejectedAtApplyBoundary() throws {
    try withDB { db in
      let payload = self.minimalPayload(["defer_count": .int(-1)])
      XCTAssertThrowsError(try self.buildRow(db, payload)) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("defer_count"), "got: \(msg)")
      }
    }
  }

  func testInvalidDeferReasonEnumIsRejected() throws {
    try withDB { db in
      let payload = self.minimalPayload([
        "last_defer_reason": .string("totally-not-a-real-reason")
      ])
      XCTAssertThrowsError(try self.buildRow(db, payload)) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("last_defer_reason"), "got: \(msg)")
      }
    }
  }

  func testListIdFallsBackToInboxWhenPayloadOmitsField() throws {
    try withDB { db in
      let row = try self.buildRow(db, self.payloadWithout("list_id"))
      XCTAssertEqual(
        row.listId, inboxListId, "absent list_id must fall back to the canonical inbox list")
    }
  }

  func testListIdFallsBackToInboxWhenPayloadSuppliesEmptyString() throws {
    try withDB { db in
      let row = try self.buildRow(db, self.minimalPayload(["list_id": .string("")]))
      XCTAssertEqual(row.listId, inboxListId)
    }
  }

  func testDeferCountDefaultIsZeroWhenFieldAbsent() throws {
    try withDB { db in
      let row = try self.buildRow(db, self.minimalPayload())
      XCTAssertEqual(row.deferCount, 0)
      XCTAssertEqual(row.deferCountPresent, 0)
    }
  }

  func testPriorityOutOfRangeIsRejected() throws {
    try withDB { db in
      let payload = self.minimalPayload(["priority": .int(99)])
      XCTAssertThrowsError(try self.buildRow(db, payload)) { err in
        guard case ApplyError.invalidPayload = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
      }
    }
  }

  func testMalformedPlannedDateIsRejectedAtApplyBoundary() throws {
    try withDB { db in
      let payload = self.minimalPayload(["planned_date": .string("next friday")])
      XCTAssertThrowsError(try self.buildRow(db, payload)) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("planned_date"), "got: \(msg)")
      }
    }
  }

  func testMalformedCanonicalOccurrenceDateIsRejectedAtApplyBoundary() throws {
    try withDB { db in
      let payload = self.minimalPayload(["canonical_occurrence_date": .string("2026/05/08")])
      XCTAssertThrowsError(try self.buildRow(db, payload)) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("canonical_occurrence_date"), "got: \(msg)")
      }
    }
  }

  // MARK: - D4 cross-field CHECK invariants + recurrence normalization

  private func applyUpsert(
    _ db: Database, _ payload: String, version: String = ApplyTaskTests.version
  ) throws {
    _ = try ApplyTask.applyTaskUpsert(
      db, entityId: Self.taskId, payload: payload, version: version,
      tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00.000Z")
  }

  /// The recurrence-companion CHECK is pre-validated: `recurrence` set without
  /// all of `due_date` / `recurrence_group_id` / `canonical_occurrence_date`
  /// drops as InvalidPayload instead of tripping the SQL CHECK.
  func testRecurrenceWithoutCompanionsRejectedAtApplyBoundary() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try self.applyUpsert(
          db, self.minimalPayload(["recurrence": .string("{\"FREQ\":\"DAILY\",\"INTERVAL\":1}")]))
      ) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("recurrence"), "got: \(msg)")
      }
    }
  }

  func testFutureRecurrenceWithoutCompanionsDefersWithoutPersistence() throws {
    try withDB { db in
      let remoteSchema = LorvexVersion.payloadSchemaVersion + 1
      let version = try Hlc.parse(Self.version)
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .task, entityId: Self.taskId, operation: .upsert,
        version: version, payloadSchemaVersion: remoteSchema,
        payload: self.minimalPayload([
          "recurrence": .string("{\"FREQ\":\"DAILY\",\"INTERVAL\":1}")
        ]),
        deviceId: "00000000-0000-7000-8000-000000000002")

      XCTAssertEqual(
        try Apply.applyEnvelope(
          db,
          registry: EntityApplierRegistry(
            appliers: EntityApplierRegistry.defaultEntityAppliers()),
          envelope: envelope),
        .deferred(
          reason: .schemaTooNew(
            remoteVersion: remoteSchema,
            localVersion: LorvexVersion.payloadSchemaVersion)))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        0)
    }
  }

  func testRecurrenceExceptionsWithoutRecurrenceAreRejectedWithoutPersistence() throws {
    try withDB { db in
      let payload = self.minimalPayload([
        "recurrence": .null,
        "recurrence_exceptions": .string("[\"2026-05-02\"]"),
      ])

      XCTAssertThrowsError(try self.applyUpsert(db, payload)) { error in
        guard case let ApplyError.invalidPayload(message) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("recurrence_exceptions"), "got: \(message)")
      }
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM task_recurrence_exceptions WHERE task_id = ?",
          arguments: [Self.taskId]),
        0)
    }
  }

  func testFutureRecurrenceExceptionsWithoutRecurrenceDeferWithoutPersistence() throws {
    try withDB { db in
      let remoteSchema = LorvexVersion.payloadSchemaVersion + 1
      let version = try Hlc.parse(Self.version)
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .task, entityId: Self.taskId, operation: .upsert,
        version: version, payloadSchemaVersion: remoteSchema,
        payload: self.minimalPayload([
          "recurrence": .null,
          "recurrence_exceptions": .string("[\"2026-05-02\"]"),
        ]),
        deviceId: "00000000-0000-7000-8000-000000000002")

      XCTAssertEqual(
        try Apply.applyEnvelope(
          db,
          registry: EntityApplierRegistry(
            appliers: EntityApplierRegistry.defaultEntityAppliers()),
          envelope: envelope),
        .deferred(
          reason: .schemaTooNew(
            remoteVersion: remoteSchema,
            localVersion: LorvexVersion.payloadSchemaVersion)))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM task_recurrence_exceptions WHERE task_id = ?",
          arguments: [Self.taskId]),
        0)
    }
  }

  func testEmptyRecurrenceExceptionsRemainValidWithoutRecurrence() throws {
    try withDB { db in
      try self.applyUpsert(
        db,
        self.minimalPayload([
          "recurrence": .null,
          "recurrence_exceptions": .string("[]"),
        ]))

      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM task_recurrence_exceptions WHERE task_id = ?",
          arguments: [Self.taskId]),
        0)
    }
  }

  /// A recurring task carrying all three companions applies and stores the
  /// canonical recurrence JSON.
  func testRecurrenceWithCompanionsAppliesAndNormalizes() throws {
    try withDB { db in
      try self.applyUpsert(
        db,
        self.minimalPayload([
          // `INTERVAL` omitted on the wire; the normalizer supplies the default.
          "recurrence": .string("{\"FREQ\":\"WEEKLY\"}"),
          "due_date": .string("2026-05-01"),
          "recurrence_group_id": .string("grp-1"),
          "canonical_occurrence_date": .string("2026-05-01"),
        ]))
      let stored = try String.fetchOne(
        db, sql: "SELECT recurrence FROM tasks WHERE id = ?", arguments: [Self.taskId])
      XCTAssertEqual(stored, "{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}", "recurrence stored canonical")
    }
  }

  /// A malformed recurrence rule is rejected at `buildTaskRow` (the normalizer
  /// runs at the trust boundary), surfaced as InvalidPayload at the current
  /// schema version.
  func testMalformedRecurrenceRejectedAtApplyBoundary() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try self.buildRow(db, self.minimalPayload(["recurrence": .string("FREQ=DAILY-not-json")]))
      ) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("recurrence"), "got: \(msg)")
      }
    }
  }

  // MARK: - update_sql / insert_sql byte shape

  func testUpdateSQLRejectEqualUsesStrictlyGreaterVersionPredicate() {
    let sql = ApplyTask.taskUpdateSQL(.rejectEqual)
    XCTAssertTrue(sql.hasPrefix("UPDATE tasks SET"))
    XCTAssertTrue(sql.hasSuffix("WHERE id = :id AND :version > version"))
  }

  func testUpdateSQLAllowEqualUsesGreaterOrEqualVersionPredicate() {
    let sql = ApplyTask.taskUpdateSQL(.allowEqual)
    XCTAssertTrue(sql.hasSuffix("WHERE id = :id AND :version >= version"))
  }

  func testUpdateSQLPartialUpdateGatesEveryNullableColumn() {
    let sql = ApplyTask.taskUpdateSQL(.rejectEqual)
    let gated = [
      "body", "raw_input", "ai_notes", "priority", "due_date",
      "estimated_minutes", "recurrence", "spawned_from",
      "recurrence_group_id", "canonical_occurrence_date", "completed_at", "last_deferred_at",
      "last_defer_reason", "planned_date", "available_from", "defer_count",
      "recurrence_instance_key", "archived_at",
    ]
    for col in gated {
      XCTAssertTrue(sql.contains(":\(col)_present"), "UPDATE must gate `\(col)`")
    }
    for col in ["title", "status", "list_id", "created_at", "updated_at"] {
      XCTAssertFalse(
        sql.contains(":\(col)_present"), "unconditional column `\(col)` must NOT carry a gate")
    }
  }

  func testInsertSQLIncludesEverySyncedTaskColumnInOrder() {
    let cols = [
      "id", "title", "body", "raw_input", "ai_notes", "status",
      "list_id", "priority", "due_date", "estimated_minutes",
      "recurrence", "spawned_from", "recurrence_group_id", "canonical_occurrence_date",
      "created_at", "updated_at", "completed_at", "last_deferred_at", "last_defer_reason",
      "planned_date", "available_from", "defer_count", "recurrence_instance_key", "version",
      "archived_at",
    ]
    let sql = ApplyTask.taskInsertSQL
    var cursor = sql.startIndex
    for col in cols {
      guard let r = sql.range(of: col, range: cursor..<sql.endIndex) else {
        return XCTFail("INSERT missing column `\(col)` in order")
      }
      cursor = r.upperBound
    }
    cursor = sql.startIndex
    for col in cols {
      guard let r = sql.range(of: ":\(col)", range: cursor..<sql.endIndex) else {
        return XCTFail("INSERT missing bind `:\(col)` in order")
      }
      cursor = r.upperBound
    }
  }

  // MARK: - apply_task_delete

  private func seedTask(_ db: Database, id: String, version: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at, defer_count)
        VALUES (?, 'inbox', 'T', 'open', ?, '2026-04-01T00:00:00.000Z',
                '2026-04-01T00:00:00.000Z', 0)
        """,
      arguments: [id, version])
  }

  private func seedTag(_ db: Database, id: String, version: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
        VALUES (?, 'X', 'x', ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
        """,
      arguments: [id, version])
  }

  func testApplyTaskInsertRejectsRecurrenceInstanceKeyCollisionWithoutSideEffects() throws {
    try withDB { db in
      let groupId = "00000000-0000-7000-8000-0000000000a1"
      let occurrenceDate = "2026-04-02"
      let key = "\(groupId):\(occurrenceDate)"
      let incomingId = "00000000-0000-7000-8000-000000000041"
      let existingId = "00000000-0000-7000-8000-000000000042"
      let existingVersion = "1711234567000_0000_dec0000100000001"
      let incomingVersion = "1711234568000_0000_dec0000200000002"
      try db.execute(
        sql: """
          INSERT INTO tasks (
              id, list_id, title, body, status, recurrence_group_id,
              canonical_occurrence_date, recurrence_instance_key,
              version, created_at, updated_at, defer_count
          ) VALUES (?, 'inbox', 'Existing task', 'existing body', 'open', ?, ?, ?, ?,
                    '2026-04-01T00:00:00.000Z',
                    '2026-04-01T00:00:00.000Z', 0)
          """,
        arguments: [existingId, groupId, occurrenceDate, key, existingVersion])

      let payload = self.minimalPayload([
        "title": .string("Incoming task"),
        "recurrence_group_id": .string(groupId),
        "canonical_occurrence_date": .string(occurrenceDate),
        "recurrence_instance_key": .string(key),
      ])
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .task, entityId: incomingId, operation: .upsert,
        version: try Hlc.parse(incomingVersion),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "device-remote")

      XCTAssertThrowsError(
        try Apply.applyEnvelope(
          db,
          registry: EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers()),
          envelope: envelope)
      ) { error in
        guard case .invalidPayload(let message) = error as? ApplyError else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("already claimed by task \(existingId)"))
      }

      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE recurrence_instance_key = ?",
          arguments: [key]),
        1)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT body FROM tasks WHERE id = ?", arguments: [existingId]),
        "existing body")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [incomingId]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'task'"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
    }
  }

  func testApplyTaskUpdateRejectsRecurrenceInstanceKeyCollisionWithoutMutation() throws {
    try withDB { db in
      let firstId = "00000000-0000-7000-8000-000000000040"
      let claimantId = "00000000-0000-7000-8000-000000000041"
      let firstGroup = "00000000-0000-7000-8000-0000000000a1"
      let claimantGroup = "00000000-0000-7000-8000-0000000000a2"
      let firstDate = "2026-04-02"
      let claimantDate = "2026-04-03"
      let firstKey = "\(firstGroup):\(firstDate)"
      let claimantKey = "\(claimantGroup):\(claimantDate)"
      let existingVersion = "1711234567000_0000_dec0000100000001"
      let incomingVersion = "1711234568000_0000_dec0000200000002"
      for row in [
        (firstId, "First task", firstGroup, firstDate, firstKey),
        (claimantId, "Claimant task", claimantGroup, claimantDate, claimantKey),
      ] {
        try db.execute(
          sql: """
            INSERT INTO tasks (
                id, list_id, title, status, recurrence_group_id,
                canonical_occurrence_date, recurrence_instance_key,
                version, schedule_version, created_at, updated_at, defer_count
            ) VALUES (?, 'inbox', ?, 'open', ?, ?, ?, ?, ?,
                      '2026-04-01T00:00:00.000Z',
                      '2026-04-01T00:00:00.000Z', 0)
            """,
          arguments: [row.0, row.1, row.2, row.3, row.4, existingVersion, existingVersion])
      }

      let payload = self.minimalPayload([
        "title": .string("Mutated title"),
        "recurrence_group_id": .string(claimantGroup),
        "canonical_occurrence_date": .string(claimantDate),
        "recurrence_instance_key": .string(claimantKey),
        "schedule_version": .string(incomingVersion),
      ])
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .task, entityId: firstId, operation: .upsert,
        version: try Hlc.parse(incomingVersion),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "device-remote")

      XCTAssertThrowsError(
        try Apply.applyEnvelope(
          db,
          registry: EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers()),
          envelope: envelope)
      ) { error in
        guard case .invalidPayload(let message) = error as? ApplyError else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("already claimed by task \(claimantId)"))
      }

      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [firstId]),
        "First task")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT recurrence_instance_key FROM tasks WHERE id = ?", arguments: [firstId]),
        firstKey)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
    }
  }

  func testCascadeTombstoneUsesMaxOfParentAndEdgeVersion() throws {
    try withDB { db in
      let taskId = "00000000-0000-7000-8000-000000000010"
      let tagId = "tag-x"
      try self.seedTask(db, id: taskId, version: "1711234567000_0000_dec0000100000001")
      try self.seedTag(db, id: tagId, version: "1711234567000_0000_dec0000100000001")

      let edgeVersion = "1711234599000_0000_dec0000200000002"
      let parentDeleteVersion = "1711234567500_0000_dec0000100000001"
      try db.execute(
        sql: """
          INSERT INTO task_tags (task_id, tag_id, created_at, version)
          VALUES (?, ?, '2026-04-01T00:00:00.000Z', ?)
          """,
        arguments: [taskId, tagId, edgeVersion])

      _ = try ApplyTask.applyTaskDelete(
        db, entityId: taskId, version: parentDeleteVersion, applyTs: "")

      let edgeEntityId = "\(taskId):\(tagId)"
      let storedVersion = try String.fetchOne(
        db,
        sql: "SELECT version FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
        arguments: [EdgeName.taskTag, edgeEntityId])
      XCTAssertEqual(
        storedVersion, edgeVersion,
        "cascade tombstone must be stamped at the edge row's own (greater) version")

      let tsHlc = try Hlc.parse(XCTUnwrap(storedVersion))
      let parentHlc = try Hlc.parse(parentDeleteVersion)
      XCTAssertTrue(tsHlc > parentHlc)
    }
  }

  func testApplyTaskDeleteRefusesToRemoveANewerLocalRow() throws {
    try withDB { db in
      let taskId = "00000000-0000-7000-8000-000000000020"
      try self.seedTask(db, id: taskId, version: "1711234599000_0000_dec0000200000002")
      try db.execute(
        sql: """
          INSERT INTO current_focus (date, version, created_at, updated_at)
          VALUES ('2026-04-02', '1711234599000_0000_dec0000200000002',
                  '2026-04-02T00:00:00.000Z', '2026-04-02T00:00:00.000Z')
          """)
      try db.execute(
        sql: "INSERT INTO current_focus_items (date, position, task_id) VALUES ('2026-04-02', 0, ?)",
        arguments: [taskId])

      let staleVersion = "1711234567000_0000_dec0000100000001"
      _ = try ApplyTask.applyTaskDelete(db, entityId: taskId, version: staleVersion, applyTs: "")

      let count = try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [taskId])
      XCTAssertEqual(count, 1, "stale-version delete must NOT remove a newer local task row")
      let focusCount = try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE task_id = ?", arguments: [taskId])
      XCTAssertEqual(focusCount, 1, "stale-version delete must NOT clean focus projections")
    }
  }

  func testApplyTaskDeleteCleansFocusProjectionRowsAfterGatePasses() throws {
    try withDB { db in
      let taskId = "00000000-0000-7000-8000-000000000021"
      let version = "1711234567000_0000_dec0000100000001"
      try self.seedTask(db, id: taskId, version: version)
      try db.execute(
        sql: """
          INSERT INTO current_focus (date, version, created_at, updated_at)
          VALUES ('2026-04-02', ?, '2026-04-02T00:00:00.000Z',
                  '2026-04-02T00:00:00.000Z')
          """,
        arguments: [version])
      try db.execute(
        sql: "INSERT INTO current_focus_items (date, position, task_id) VALUES ('2026-04-02', 0, ?)",
        arguments: [taskId])
      try db.execute(
        sql: """
          INSERT INTO focus_schedule (date, version, created_at, updated_at)
          VALUES ('2026-04-02', ?, '2026-04-02T00:00:00.000Z',
                  '2026-04-02T00:00:00.000Z')
          """,
        arguments: [version])
      try db.execute(
        sql: """
          INSERT INTO focus_schedule_blocks
              (date, position, block_type, start_minutes, end_minutes, task_id)
          VALUES ('2026-04-02', 0, 'task', 540, 600, ?)
          """,
        arguments: [taskId])

      let result = try ApplyTask.applyTaskDeleteWithRepairs(
        db, entityId: taskId, version: "1711234568000_0000_dec0000200000002", applyTs: "")

      XCTAssertEqual(result.decision, .applied)
      let rootFloor = try Hlc.parseCanonical(version)
      XCTAssertEqual(result.repairTargets.count, 2)
      XCTAssertTrue(
        result.repairTargets.contains(
          .relatedEntity(
            entityType: .currentFocus, entityId: "2026-04-02",
            operation: .delete, knownVersionFloor: rootFloor)))
      XCTAssertTrue(
        result.repairTargets.contains(
          .relatedEntity(
            entityType: .focusSchedule, entityId: "2026-04-02",
            operation: .delete, knownVersionFloor: rootFloor)))

      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE task_id = ?",
          arguments: [taskId]),
        0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE task_id = ?",
          arguments: [taskId]),
        0)
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM current_focus WHERE date = '2026-04-02'"),
        0)
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = '2026-04-02'"),
        0)
    }
  }

  func testCascadeDoesNotRunWhenByteCompareFallbackRejectsLegacyLocalVersion() throws {
    try withDB { db in
      let taskId = "00000000-0000-7000-8000-000000000031"
      let tagId = "tag-3002-h1"
      let canonicalEnvelopeVersion = "1711234599000_0000_dec0000200000002"
      // Legacy unparseable local version. ASCII 'v' sorts above any digit, so
      // the byte-compare fallback interprets `'v1'` as the dominating version
      // and rejects the delete.
      let legacyLocalVersion = "v1"
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try self.seedTask(db, id: taskId, version: legacyLocalVersion)
      }
      try self.seedTag(db, id: tagId, version: canonicalEnvelopeVersion)
      try db.execute(
        sql: """
          INSERT INTO task_tags (task_id, tag_id, created_at, version)
          VALUES (?, ?, '2026-04-01T00:00:00.000Z', ?)
          """,
        arguments: [taskId, tagId, canonicalEnvelopeVersion])

      let outcome = try ApplyTask.applyTaskDelete(
        db, entityId: taskId, version: canonicalEnvelopeVersion,
        applyTs: "2026-04-01T00:00:00.000Z")
      guard case .rejected = outcome else {
        return XCTFail("byte-compare fallback must surface the loss as rejected, got \(outcome)")
      }

      let parentCount = try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [taskId])
      XCTAssertEqual(parentCount, 1, "byte-compare-rejected delete must leave the parent alive")

      let edgeEntityId = "\(taskId):\(tagId)"
      let edgeTombstoneCount = try Int64.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
        arguments: [EdgeName.taskTag, edgeEntityId])
      XCTAssertEqual(
        edgeTombstoneCount, 0,
        "cascade tombstone must NOT be written when the LWW gate rejects the parent delete")
    }
  }
}
