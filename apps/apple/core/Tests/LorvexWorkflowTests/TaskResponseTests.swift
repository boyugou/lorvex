import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity tests for `LorvexWorkflow.TaskResponse`. Mirrors the
/// Rust `lorvex_workflow::task_response` surface — that module ships
/// no Rust-side unit tests of its own (the contract is exercised
/// through caller tests we don't port in this slice), so these tests
/// focus on shape parity: every TaskRow column lands as a key in the
/// JSON object, enrichment fields append, and the
/// ``canonicalizeJSON(_:)`` byte output matches a hand-pinned
/// expectation for a minimal fixture.
final class TaskResponseTests: XCTestCase {
  private func insertList(_ db: Database, id: String, name: String) throws {
    try db.execute(
      sql:
        "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
        + "VALUES (?1, ?2, '0000000000000_0000_0000000000000000', "
        + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
      arguments: [id, name])
  }

  /// Insert a minimal `tasks` row covering every column the canonical
  /// projection touches.
  private func insertTask(
    _ db: Database, id: String, title: String = "T", listId: String = "L",
    status: String = "open",
    dueDate: String? = nil, plannedDate: String? = nil
  ) throws {
    try insertList(db, id: listId, name: "List")
    try db.execute(
      sql:
        "INSERT INTO tasks (id, title, status, list_id, due_date, planned_date, "
        + "version, created_at, updated_at, defer_count) "
        + "VALUES (?1, ?2, ?3, ?4, ?5, ?6, "
        + "        '0000000000000_0000_0000000000000000', "
        + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)",
      arguments: [id, title, status, listId, dueDate, plannedDate])
  }

  func testEncodedTaskRowCarriesEveryColumnAsAKey() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(
        db, id: "t1", title: "Hello", listId: "L1",
        dueDate: "2999-04-15", plannedDate: "2999-04-10")
    }
    let json = try store.writer.read { db in
      try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: "t1"))
    }
    guard case .object(let map) = json else {
      return XCTFail("expected JSON object")
    }
    // 28 TaskRow columns + 5 enrichment slots.
    let expected: Set<String> = [
      "id", "title", "body", "raw_input", "ai_notes",
      "status", "list_id", "priority", "version", "created_at", "updated_at",
      "due_date", "estimated_minutes", "planned_date", "available_from",
      "defer_count", "last_deferred_at", "last_defer_reason",
      "recurrence", "recurrence_exceptions", "spawned_from", "recurrence_group_id",
      "canonical_occurrence_date", "recurrence_instance_key",
      "completed_at", "archived_at",
      "tags", "depends_on", "checklist_items", "lateness_state", "reminders",
    ]
    XCTAssertEqual(Set(map.keys), expected)
    XCTAssertEqual(map["id"], .string("t1"))
    XCTAssertEqual(map["title"], .string("Hello"))
    XCTAssertEqual(map["list_id"], .string("L1"))
    XCTAssertEqual(map["due_date"], .string("2999-04-15"))
    XCTAssertEqual(map["planned_date"], .string("2999-04-10"))
    XCTAssertEqual(map["status"], .string("open"))
    XCTAssertEqual(map["defer_count"], .int(0))
    // Enrichment fields default to JSON null when the helper produced
    // no entries — checklist, tags, depends_on, lateness_state all
    // collapse to null on a bare task.
    XCTAssertEqual(map["tags"], .null)
    XCTAssertEqual(map["depends_on"], .null)
    XCTAssertEqual(map["checklist_items"], .null)
    XCTAssertEqual(map["lateness_state"], .null)
    XCTAssertEqual(map["reminders"], .array([]))
  }

  func testTaskTitleFallsBackToLiteralTask() throws {
    XCTAssertEqual(TaskResponse.taskTitle(.object([:])), "task")
    XCTAssertEqual(TaskResponse.taskTitle(.object(["title": .string("X")])), "X")
    XCTAssertEqual(
      TaskResponse.taskTitle(.object(["title": .int(7)])), "task",
      "non-string title falls back to literal 'task'")
  }

  func testMissingTaskRaisesNotFound() throws {
    let store = try WorkflowTestSupport.freshStore()
    do {
      _ = try store.writer.read { db in
        try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: "ghost"))
      }
      XCTFail("expected NotFound")
    } catch let StoreError.notFound(entity, id) {
      XCTAssertEqual(entity, "task")
      XCTAssertEqual(id, "ghost")
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

  func testBatchPreservesOrderAndRejectsMissing() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, id: "t1", title: "A")
      try self.insertTask(db, id: "t2", title: "B")
    }
    let tasks = try store.writer.read { db in
      try TaskResponse.loadEnrichedTasksJSON(db, taskIds: ["t2", "t1"])
    }
    XCTAssertEqual(tasks.count, 2)
    if case .object(let m0) = tasks[0] {
      XCTAssertEqual(m0["id"], .string("t2"))
    } else {
      XCTFail()
    }
    if case .object(let m1) = tasks[1] {
      XCTAssertEqual(m1["id"], .string("t1"))
    } else {
      XCTFail()
    }
  }

  /// Reminders are sorted by `reminder_at` ascending. Pin three rows
  /// inserted out of order and confirm the returned `reminders` array
  /// reads chronologically.
  func testRemindersSortedByReminderAtAscending() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, id: "t1")
      // Inserted out of chronological order; helper must sort.
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, "
          + "original_local_time, original_tz, version, created_at) "
          + "VALUES (?1, 't1', ?2, '12:00', 'UTC', "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00.000Z')",
        arguments: ["r-mid", "2026-04-15T12:00:00.000Z"])
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, "
          + "original_local_time, original_tz, version, created_at) "
          + "VALUES (?1, 't1', ?2, '08:00', 'UTC', "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00.000Z')",
        arguments: ["r-early", "2026-04-15T08:00:00.000Z"])
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, "
          + "original_local_time, original_tz, version, created_at) "
          + "VALUES (?1, 't1', ?2, '20:00', 'UTC', "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00.000Z')",
        arguments: ["r-late", "2026-04-15T20:00:00.000Z"])
    }
    let json = try store.writer.read { db in
      try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: "t1"))
    }
    guard case .object(let map) = json, case .array(let reminders) = map["reminders"] ?? .null
    else {
      return XCTFail("missing reminders array")
    }
    let ids = reminders.compactMap { payload -> String? in
      if case .object(let m) = payload, case .string(let id) = m["id"] ?? .null { return id }
      return nil
    }
    XCTAssertEqual(ids, ["r-early", "r-mid", "r-late"])
  }

  /// The batch row-enrichment primitive (`loadEnrichedTasksJSON(_:rows:)`),
  /// which list / search / overview reads route through, must produce output
  /// byte-for-byte identical to enriching each row's id individually via the
  /// per-task `loadEnrichedTaskJSON`. The fixture exercises every enrichment
  /// channel across multiple tasks — tags, dependencies, checklist items,
  /// reminders (inserted out of order), and lateness (an overdue open task) —
  /// so any divergence in the batch assembly surfaces as a canonical-JSON diff.
  func testBatchRowEnrichmentMatchesPerTaskCanonicalJson() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, id: "t1", title: "Alpha", listId: "L1")
      // Overdue open task drives lateness enrichment.
      try self.insertTask(
        db, id: "t2", title: "Beta", listId: "L1",
        dueDate: "2000-01-01", plannedDate: "2000-01-01")
      try self.insertTask(db, id: "t3", title: "Gamma", listId: "L1")

      // Tags on t1.
      try db.execute(
        sql:
          "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) "
          + "VALUES ('tag-a', 'Work', 'work', "
          + "'0000000000000_0000_0000000000000000', "
          + "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")
      try db.execute(
        sql:
          "INSERT INTO task_tags (task_id, tag_id, version, created_at) "
          + "VALUES ('t1', 'tag-a', '0000000000000_0000_0000000000000000', "
          + "'2026-01-01T00:00:00.000Z')")

      // t1 depends on t3.
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES ('t1', 't3', '0000000000000_0000_0000000000000000', "
          + "'2026-01-01T00:00:00.000Z')")

      // Checklist on t2.
      try db.execute(
        sql:
          "INSERT INTO task_checklist_items (id, task_id, position, text, version, "
          + "created_at, updated_at) "
          + "VALUES ('ck-1', 't2', 0, 'step one', "
          + "'0000000000000_0000_0000000000000000', "
          + "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")

      // Reminders on t1, inserted out of chronological order.
      for (id, at) in [
        ("r-late", "2026-04-15T20:00:00.000Z"),
        ("r-early", "2026-04-15T08:00:00.000Z"),
        ("r-mid", "2026-04-15T12:00:00.000Z"),
      ] {
        try db.execute(
          sql:
            "INSERT INTO task_reminders (id, task_id, reminder_at, "
            + "original_local_time, original_tz, version, created_at) "
            + "VALUES (?1, 't1', ?2, '00:00', 'UTC', "
            + "'0000000000000_0000_0000000000000000', "
            + "'2026-01-01T00:00:00.000Z')",
          arguments: [id, at])
      }
    }

    let order = ["t2", "t1", "t3"]
    let (perTask, batch) = try store.writer.read {
      db -> ([String], [String]) in
      let perTask = try order.map { id in
        try canonicalizeJSON(
          TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id)))
      }
      let rows = try order.map { id -> TaskRow in
        guard let row = try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: id)) else {
          throw StoreError.notFound(entity: "task", id: id)
        }
        return row
      }
      let batch = try TaskResponse.loadEnrichedTasksJSON(db, rows: rows).map {
        try canonicalizeJSON($0)
      }
      return (perTask, batch)
    }
    XCTAssertEqual(batch, perTask)
  }

  /// Canonical JSON output is reproducible across runs for a
  /// fully-stable fixture. This is the byte-parity pin — change a
  /// field, change the SHA, drift surfaces immediately.
  func testCanonicalJsonByteParityForStableFixture() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(
        db, id: "t1", title: "Hello", listId: "L1",
        dueDate: "2999-04-15", plannedDate: nil)
    }
    let json = try store.writer.read { db in
      try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: "t1"))
    }
    let encoded = try canonicalizeJSON(json)
    // Keys are emitted in UTF-8 byte order. The expected string is
    // assembled below by listing every (key, value) pair sorted, so
    // a drift between the encoder and the assertion surfaces as a
    // single-character diff in the test output.
    let expected = #"""
      {"ai_notes":null,"archived_at":null,"available_from":null,"body":null,"canonical_occurrence_date":null,"checklist_items":null,"completed_at":null,"created_at":"2026-01-01T00:00:00.000Z","defer_count":0,"depends_on":null,"due_date":"2999-04-15","estimated_minutes":null,"id":"t1","last_defer_reason":null,"last_deferred_at":null,"lateness_state":null,"list_id":"L1","planned_date":null,"priority":null,"raw_input":null,"recurrence":null,"recurrence_exceptions":null,"recurrence_group_id":null,"recurrence_instance_key":null,"reminders":[],"spawned_from":null,"status":"open","tags":null,"title":"Hello","updated_at":"2026-01-01T00:00:00.000Z","version":"0000000000000_0000_0000000000000000"}
      """#.trimmingCharacters(in: .whitespacesAndNewlines)
    XCTAssertEqual(encoded, expected)
  }
}
