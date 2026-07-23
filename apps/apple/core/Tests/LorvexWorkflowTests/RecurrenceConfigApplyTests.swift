import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity port of `lorvex_workflow::recurrence_config::tests` — the
/// applier half. Planner cases are covered by
/// ``RecurrenceConfigTests``.
final class RecurrenceConfigApplyTests: XCTestCase {
  private let version = "9999913599999_0000_a0a0a0a0a0a0a0a0"
  private let now = "2026-04-01T00:00:00.000Z"

  private func insertList(_ db: Database, id: String) throws {
    try db.execute(
      sql:
        "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
        + "VALUES (?1, 'L', '0000000000000_0000_0000000000000000', "
        + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
      arguments: [id])
  }

  private func insertTask(
    _ db: Database, id: String,
    dueDate: String? = nil,
    recurrence: String? = nil
  ) throws {
    try insertList(db, id: "L1")
    try db.execute(
      sql:
        "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
        + "version, created_at, updated_at, defer_count) "
        + "VALUES (?1, 'T', 'open', 'L1', ?2, ?3, "
        + "        '0000000000000_0000_0000000000000000', "
        + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)",
      arguments: [id, dueDate, recurrence])
  }

  func testEnableSetsGroupIdAnchorAndDueDate() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, id: "t1", dueDate: "2026-04-15")
    }
    let transition = try RecurrenceConfig.applyRecurrenceChange(
      store.writer, taskId: TaskId(trusted: "t1"),
      recurrencePatch: .set("{\"FREQ\":\"DAILY\"}"),
      dueDatePatch: .unset,
      today: "2026-04-01", version: version, now: now)
    XCTAssertEqual(transition, .enable)

    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT recurrence, recurrence_group_id, canonical_occurrence_date, "
          + "due_date, version, updated_at FROM tasks WHERE id = ?1",
        arguments: ["t1"])!
      XCTAssertEqual(row[0] as String?, "{\"FREQ\":\"DAILY\"}")
      XCTAssertNotNil(row[1] as String?)
      XCTAssertEqual(row[2] as String?, "2026-04-15")
      XCTAssertEqual(row[3] as String?, "2026-04-15")
      XCTAssertEqual(row[4] as String?, version)
      XCTAssertEqual(row[5] as String?, now)
    }
  }

  func testEnableOnCompletedOneOffCreatesEndedSeries() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertList(db, id: "L1")
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, completed_at, "
          + "version, created_at, updated_at) VALUES ("
          + "'terminal-enable', 'T', 'completed', 'L1', '2026-04-15', "
          + "'2026-04-15T09:00:00.000Z', "
          + "'0000000000000_0000_0000000000000000', "
          + "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")
    }

    let transition = try RecurrenceConfig.applyRecurrenceChange(
      store.writer, taskId: TaskId(trusted: "terminal-enable"),
      recurrencePatch: .set("{\"FREQ\":\"DAILY\"}"),
      dueDatePatch: .unset,
      today: "2026-04-01", version: version, now: now)
    XCTAssertEqual(transition, .enable)

    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT recurrence, recurrence_rollover_state, recurrence_successor_id, "
          + "lifecycle_version FROM tasks WHERE id = 'terminal-enable'")
    }
    XCTAssertEqual(row?[0] as String?, "{\"FREQ\":\"DAILY\"}")
    XCTAssertEqual(row?[1] as String?, "ended")
    XCTAssertNil(row?[2] as String?)
    XCTAssertEqual(row?[3] as String?, version)
  }

  func testDisableClearsActiveSeriesConfig() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('L1', 'L', '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "recurrence_group_id, canonical_occurrence_date, "
          + "version, created_at, updated_at, defer_count) "
          + "VALUES ('t1', 'T', 'open', 'L1', '2026-04-15', '{\"FREQ\":\"DAILY\"}', "
          + "        'g-1', '2026-04-15', "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)")
      // Pre-existing EXDATE row to verify the applier wipes them on disable.
      try db.execute(
        sql:
          "INSERT INTO task_recurrence_exceptions (task_id, exception_date) "
          + "VALUES ('t1', '2026-04-20')")
    }
    let transition = try RecurrenceConfig.applyRecurrenceChange(
      store.writer, taskId: TaskId(trusted: "t1"),
      recurrencePatch: .clear,
      dueDatePatch: .unset,
      today: "2026-04-01", version: version, now: now)
    XCTAssertEqual(transition, .disable)

    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT recurrence, recurrence_group_id, canonical_occurrence_date "
          + "FROM tasks WHERE id = ?1",
        arguments: ["t1"])!
      XCTAssertNil(row[0] as String?)
      XCTAssertNil(row[1] as String?)
      XCTAssertNil(row[2] as String?)
      let exCount = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM task_recurrence_exceptions WHERE task_id = ?1",
        arguments: ["t1"])!
      XCTAssertEqual(exCount, 0)
    }
  }

  func testDisableContractsRevokedActiveRolloverWithOneClock() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertList(db, id: "L1")
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "recurrence_group_id, canonical_occurrence_date, "
          + "recurrence_rollover_state, recurrence_successor_id, "
          + "version, created_at, updated_at) VALUES ("
          + "'t-revoked', 'T', 'open', 'L1', '2026-04-15', "
          + "'{\"FREQ\":\"DAILY\"}', 'g-revoked', '2026-04-15', "
          + "'revoked', 'old-successor', "
          + "'0000000000000_0000_0000000000000000', "
          + "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")
    }

    _ = try RecurrenceConfig.applyRecurrenceChange(
      store.writer, taskId: TaskId(trusted: "t-revoked"),
      recurrencePatch: .clear, dueDatePatch: .unset,
      today: "2026-04-01", version: version, now: now)

    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT recurrence_rollover_state, recurrence_successor_id, "
          + "schedule_version, lifecycle_version, version "
          + "FROM tasks WHERE id = 't-revoked'")
    }
    XCTAssertEqual(row?[0] as String?, "none")
    XCTAssertNil(row?[1] as String?)
    XCTAssertEqual(row?[2] as String?, version)
    XCTAssertEqual(row?[3] as String?, version)
    XCTAssertEqual(row?[4] as String?, version)
  }

  func testDisableContractsAuthorizedTerminalRolloverWithOneClock() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertList(db, id: "L1")
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "recurrence_group_id, canonical_occurrence_date, completed_at, "
          + "recurrence_rollover_state, recurrence_successor_id, "
          + "version, created_at, updated_at) VALUES ("
          + "'t-authorized', 'T', 'completed', 'L1', '2026-04-15', "
          + "'{\"FREQ\":\"DAILY\"}', 'g-authorized', '2026-04-15', "
          + "'2026-04-15T10:00:00.000Z', 'authorized', 'live-successor', "
          + "'0000000000000_0000_0000000000000000', "
          + "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")
    }

    _ = try RecurrenceConfig.applyRecurrenceChange(
      store.writer, taskId: TaskId(trusted: "t-authorized"),
      recurrencePatch: .clear, dueDatePatch: .unset,
      today: "2026-04-01", version: version, now: now)

    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT recurrence_rollover_state, recurrence_successor_id, "
          + "schedule_version, lifecycle_version, version "
          + "FROM tasks WHERE id = 't-authorized'")
    }
    XCTAssertEqual(row?[0] as String?, "ended")
    XCTAssertNil(row?[1] as String?)
    XCTAssertEqual(row?[2] as String?, version)
    XCTAssertEqual(row?[3] as String?, version)
    XCTAssertEqual(row?[4] as String?, version)
  }

  func testDisableAuthorizedParentCancelsSuccessorAndReturnsAllEffects() throws {
    let store = try WorkflowTestSupport.freshStore()
    let parentId = "parent-with-successor"
    let groupId = "group-with-successor"
    let successorId = TaskRecurrenceSuccessorID.make(
      parentTaskId: parentId, recurrenceGroupId: groupId)
    let baseVersion = "0000000000001_0000_1111111111111111"
    try store.writer.write { db in
      try self.insertList(db, id: "L1")
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "recurrence_group_id, canonical_occurrence_date, completed_at, "
          + "schedule_version, lifecycle_version, recurrence_rollover_state, "
          + "recurrence_successor_id, version, created_at, updated_at) VALUES ("
          + "?1, 'Parent', 'completed', 'L1', '2026-04-15', "
          + "'{\"FREQ\":\"DAILY\"}', ?2, '2026-04-15', "
          + "'2026-04-15T10:00:00.000Z', ?3, ?3, 'authorized', ?4, ?3, "
          + "'2026-01-01T00:00:00.000Z', '2026-04-15T10:00:00.000Z')",
        arguments: [parentId, groupId, baseVersion, successorId])
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "spawned_from, spawned_from_version, recurrence_group_id, "
          + "canonical_occurrence_date, content_version, schedule_version, "
          + "lifecycle_version, archive_version, version, created_at, updated_at) VALUES ("
          + "?1, 'Child', 'open', 'L1', '2026-04-16', "
          + "'{\"FREQ\":\"DAILY\"}', ?2, ?3, ?4, '2026-04-16', "
          + "?3, ?3, ?3, ?3, ?3, "
          + "'2026-04-15T10:00:00.000Z', '2026-04-15T10:00:00.000Z')",
        arguments: [successorId, parentId, baseVersion, groupId])
      try self.insertTask(db, id: "blocker")
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES (?1, 'blocker', ?2, '2026-04-15T10:00:00.000Z')",
        arguments: [successorId, baseVersion])
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at) "
          + "VALUES ('child-reminder', ?1, '2026-04-16T09:00:00.000Z', ?2, "
          + "'2026-04-15T10:00:00.000Z')",
        arguments: [successorId, baseVersion])
      try db.execute(
        sql:
          "INSERT INTO current_focus (date, version, created_at, updated_at) "
          + "VALUES ('2026-04-16', ?1, '2026-04-15T10:00:00.000Z', "
          + "'2026-04-15T10:00:00.000Z')",
        arguments: [baseVersion])
      try db.execute(
        sql:
          "INSERT INTO current_focus_items (date, position, task_id) "
          + "VALUES ('2026-04-16', 0, ?1)",
        arguments: [successorId])
      try db.execute(
        sql:
          "INSERT INTO focus_schedule (date, version, created_at, updated_at) "
          + "VALUES ('2026-04-16', ?1, '2026-04-15T10:00:00.000Z', "
          + "'2026-04-15T10:00:00.000Z')",
        arguments: [baseVersion])
      try db.execute(
        sql:
          "INSERT INTO focus_schedule_blocks "
          + "(date, position, block_type, start_minutes, end_minutes, task_id) "
          + "VALUES ('2026-04-16', 0, 'task', 540, 600, ?1)",
        arguments: [successorId])
    }

    let result = try store.writer.write { db in
      try RecurrenceConfig.applyRecurrenceChangeWithEffectsInTx(
        db, taskId: TaskId(trusted: parentId),
        recurrencePatch: .clear, dueDatePatch: .unset,
        today: "2026-04-01", version: version, now: now)
    }

    XCTAssertEqual(result.transition, .disable)
    XCTAssertEqual(result.disableEffects.cancelledSuccessorIds, [successorId])
    XCTAssertEqual(result.disableEffects.reminderUpsertIds, ["child-reminder"])
    XCTAssertEqual(result.disableEffects.deletedDependencyEdges.count, 1)
    XCTAssertEqual(result.disableEffects.currentFocusDates, ["2026-04-16"])
    XCTAssertEqual(result.disableEffects.focusScheduleDates, ["2026-04-16"])
    try store.writer.read { db in
      let child = try Row.fetchOne(
        db,
        sql:
          "SELECT status, recurrence_rollover_state, lifecycle_version "
          + "FROM tasks WHERE id = ?1",
        arguments: [successorId])!
      XCTAssertEqual(child[0] as String?, "cancelled")
      XCTAssertEqual(child[1] as String?, "ended")
      XCTAssertEqual(child[2] as String?, version)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM task_dependencies WHERE task_id = ?1",
          arguments: [successorId]), 0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE task_id = ?1",
          arguments: [successorId]), 0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE task_id = ?1",
          arguments: [successorId]), 0)
    }
  }

  func testDisablingGeneratedTaskRerootsItAndEndsPredecessor() throws {
    let store = try WorkflowTestSupport.freshStore()
    let parentId = "predecessor"
    let groupId = "predecessor-group"
    let childId = TaskRecurrenceSuccessorID.make(
      parentTaskId: parentId, recurrenceGroupId: groupId)
    let baseVersion = "0000000000001_0000_2222222222222222"
    try store.writer.write { db in
      try self.insertList(db, id: "L1")
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "recurrence_group_id, canonical_occurrence_date, completed_at, "
          + "lifecycle_version, recurrence_rollover_state, recurrence_successor_id, "
          + "version, created_at, updated_at) VALUES ("
          + "?1, 'Parent', 'completed', 'L1', '2026-04-15', "
          + "'{\"FREQ\":\"DAILY\"}', ?2, '2026-04-15', "
          + "'2026-04-15T10:00:00.000Z', ?3, 'authorized', ?4, ?3, "
          + "'2026-01-01T00:00:00.000Z', '2026-04-15T10:00:00.000Z')",
        arguments: [parentId, groupId, baseVersion, childId])
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "spawned_from, spawned_from_version, recurrence_group_id, "
          + "canonical_occurrence_date, schedule_version, lifecycle_version, "
          + "version, created_at, updated_at) VALUES ("
          + "?1, 'Child', 'open', 'L1', '2026-04-16', "
          + "'{\"FREQ\":\"DAILY\"}', ?2, ?3, ?4, '2026-04-16', "
          + "?3, ?3, ?3, '2026-04-15T10:00:00.000Z', "
          + "'2026-04-15T10:00:00.000Z')",
        arguments: [childId, parentId, baseVersion, groupId])
    }

    let result = try store.writer.write { db in
      try RecurrenceConfig.applyRecurrenceChangeWithEffectsInTx(
        db, taskId: TaskId(trusted: childId),
        recurrencePatch: .clear, dueDatePatch: .unset,
        today: "2026-04-01", version: version, now: now)
    }

    XCTAssertEqual(result.disableEffects.taskUpsertIds, [parentId])
    try store.writer.read { db in
      let child = try Row.fetchOne(
        db,
        sql:
          "SELECT recurrence, recurrence_group_id, spawned_from, spawned_from_version "
          + "FROM tasks WHERE id = ?1",
        arguments: [childId])!
      XCTAssertNil(child[0] as String?)
      XCTAssertNil(child[1] as String?)
      XCTAssertNil(child[2] as String?)
      XCTAssertNil(child[3] as String?)
      let parent = try Row.fetchOne(
        db,
        sql:
          "SELECT recurrence_rollover_state, recurrence_successor_id, lifecycle_version "
          + "FROM tasks WHERE id = ?1",
        arguments: [parentId])!
      XCTAssertEqual(parent[0] as String?, "ended")
      XCTAssertNil(parent[1] as String?)
      XCTAssertEqual(parent[2] as String?, version)
    }
  }

  func testUpdateRuleClearsExceptionsButKeepsSeriesIdentity() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('L1', 'L', '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "recurrence_group_id, canonical_occurrence_date, "
          + "version, created_at, updated_at, defer_count) "
          + "VALUES ('t1', 'T', 'open', 'L1', '2026-04-15', '{\"FREQ\":\"DAILY\"}', "
          + "        'g-1', '2026-04-15', "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)")
      try db.execute(
        sql:
          "INSERT INTO task_recurrence_exceptions (task_id, exception_date) "
          + "VALUES ('t1', '2026-04-20')")
    }
    let transition = try RecurrenceConfig.applyRecurrenceChange(
      store.writer, taskId: TaskId(trusted: "t1"),
      recurrencePatch: .set("{\"FREQ\":\"WEEKLY\"}"),
      dueDatePatch: .unset,
      today: "2026-04-01", version: version, now: now)
    XCTAssertEqual(transition, .updateRule)

    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT recurrence, recurrence_group_id, canonical_occurrence_date "
          + "FROM tasks WHERE id = ?1",
        arguments: ["t1"])!
      XCTAssertEqual(row[0] as String?, "{\"FREQ\":\"WEEKLY\"}")
      XCTAssertEqual(row[1] as String?, "g-1")  // identity preserved
      XCTAssertEqual(row[2] as String?, "2026-04-15")  // anchor preserved
      let exCount = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM task_recurrence_exceptions WHERE task_id = ?1",
        arguments: ["t1"])!
      XCTAssertEqual(exCount, 0)
    }
  }

  func testStaleVersionRejectedWithTypedError() throws {
    let store = try WorkflowTestSupport.freshStore()
    let highVer = "9999913599999_9999_ffffffffffffffff"
    try store.writer.write { db in
      try self.insertTask(db, id: "t1", dueDate: "2026-04-15")
      try db.execute(
        sql: "UPDATE tasks SET version = ?1 WHERE id = 't1'",
        arguments: [highVer])
    }
    do {
      _ = try RecurrenceConfig.applyRecurrenceChange(
        store.writer, taskId: TaskId(trusted: "t1"),
        recurrencePatch: .set("{\"FREQ\":\"DAILY\"}"),
        dueDatePatch: .unset,
        today: "2026-04-01", version: version, now: now)
      XCTFail("expected staleVersion")
    } catch RecurrenceConfig.ChangeError.staleVersion(let id) {
      XCTAssertEqual(id, "t1")
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

  /// Explicitly rescheduling a recurring task's due_date (recurrence not in the
  /// patch → NoChange transition) re-anchors `canonical_occurrence_date` to the
  /// new due date, so the cadence follows the new day. Regression: a monthly
  /// task anchored the 6th, moved to the 15th, previously kept a stale anchor
  /// and kept spawning on the 6th.
  func testExplicitDueDateRescheduleReAnchorsCadence() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('L1', 'L', '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "recurrence_group_id, canonical_occurrence_date, "
          + "version, created_at, updated_at, defer_count) "
          + "VALUES ('t1', 'T', 'open', 'L1', '2026-01-06', "
          + "        '{\"FREQ\":\"MONTHLY\",\"INTERVAL\":1}', "
          + "        'g-1', '2026-01-06', "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)")
    }
    let transition = try RecurrenceConfig.applyRecurrenceChange(
      store.writer, taskId: TaskId(trusted: "t1"),
      recurrencePatch: .unset,
      dueDatePatch: .set("2026-01-15"),
      today: "2026-01-01", version: version, now: now)
    XCTAssertEqual(transition, .noChange)

    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT due_date, canonical_occurrence_date, recurrence, recurrence_group_id "
          + "FROM tasks WHERE id = ?1",
        arguments: ["t1"])!
      XCTAssertEqual(row[0] as String?, "2026-01-15")  // due moved
      XCTAssertEqual(row[1] as String?, "2026-01-15")  // anchor re-anchored
      XCTAssertEqual(row[2] as String?, "{\"FREQ\":\"MONTHLY\",\"INTERVAL\":1}")  // rule intact
      XCTAssertEqual(row[3] as String?, "g-1")  // series identity intact
    }
  }

  /// An LWW-rejected recurrence write on an *archived* task must surface as
  /// `staleVersion`, not silently return success. The existence probe checks
  /// the row regardless of `archived_at`, so a 0-row UPDATE on an archived row
  /// is recognized as an LWW rejection.
  func testArchivedTaskLWWRejectionSurfacesStaleVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    let highVer = "9999913599999_9999_ffffffffffffffff"
    try store.writer.write { db in
      try self.insertTask(db, id: "t1", dueDate: "2026-04-15")
      try db.execute(
        sql: "UPDATE tasks SET version = ?1, archived_at = '2026-04-02T00:00:00.000Z' "
          + "WHERE id = 't1'",
        arguments: [highVer])
    }
    do {
      _ = try RecurrenceConfig.applyRecurrenceChange(
        store.writer, taskId: TaskId(trusted: "t1"),
        recurrencePatch: .set("{\"FREQ\":\"DAILY\"}"),
        dueDatePatch: .unset,
        today: "2026-04-01", version: version, now: now)
      XCTFail("expected staleVersion on archived row")
    } catch RecurrenceConfig.ChangeError.staleVersion(let id) {
      XCTAssertEqual(id, "t1")
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

  func testNoChangePathStillBumpsVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, id: "t1", dueDate: "2026-04-15")
    }
    let transition = try RecurrenceConfig.applyRecurrenceChange(
      store.writer, taskId: TaskId(trusted: "t1"),
      recurrencePatch: .unset,
      dueDatePatch: .unset,
      today: "2026-04-01", version: version, now: now)
    XCTAssertEqual(transition, .noChange)
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT version, updated_at FROM tasks WHERE id = 't1'")!
      XCTAssertEqual(row[0] as String?, version)
      XCTAssertEqual(row[1] as String?, now)
    }
  }
}
