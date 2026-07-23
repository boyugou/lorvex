import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity port of `lorvex_workflow::lifecycle::tests::recurrence`,
/// `cancel_series` (spawn-side), `focus_rewire`, plus the recurring-task
/// cases from `transitions`. Covers the real
/// ``LifecycleRecurrenceSpawnHandler`` end-to-end.
final class LifecycleSpawnSuccessorTests: XCTestCase {
  private func tid(_ s: String) -> TaskId { TaskId(trusted: s) }

  // MARK: - test seeders

  private struct SeedTask {
    var id: String
    var title: String = "Seed"
    var status: String = "open"
    var listId: String? = nil
    var dueDate: String? = nil
    var plannedDate: String? = nil
    var canonicalOccurrenceDate: String? = nil
    var recurrence: String? = nil
    var recurrenceGroupId: String? = nil
    var recurrenceInstanceKey: String? = nil
    var recurrenceExceptions: [String] = []
    var spawnedFrom: String? = nil
    var spawnedFromVersion: String? = nil
    var completedAt: String? = nil
    var recurrenceRolloverState: String? = nil
    var recurrenceSuccessorId: String? = nil
    var version: String = "0000000000000_0000_0000000000000000"
    var createdAt: String = "2026-01-01T00:00:00Z"
  }

  private func seedTask(_ writer: any DatabaseWriter, _ t: SeedTask) throws {
    let terminal = t.status == "completed" || t.status == "cancelled"
    let rolloverState = t.recurrenceRolloverState
      ?? ((terminal && t.recurrence != nil) ? "ended" : "none")
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks ("
          + "id, title, status, list_id, due_date, planned_date, "
          + "canonical_occurrence_date, recurrence, recurrence_group_id, "
          + "recurrence_instance_key, spawned_from, spawned_from_version, completed_at, "
          + "content_version, schedule_version, lifecycle_version, archive_version, "
          + "recurrence_rollover_state, recurrence_successor_id, "
          + "version, created_at, updated_at"
          + ") VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, "
          + "?14, ?14, ?14, ?14, ?15, ?16, ?14, ?17, ?17)",
        arguments: [
          t.id, t.title, t.status, t.listId ?? "inbox", t.dueDate, t.plannedDate,
          t.canonicalOccurrenceDate, t.recurrence, t.recurrenceGroupId,
          t.recurrenceInstanceKey, t.spawnedFrom,
          t.spawnedFrom.map { _ in t.spawnedFromVersion ?? t.version }, t.completedAt,
          t.version, rolloverState, t.recurrenceSuccessorId,
          t.createdAt,
        ])
      for date in t.recurrenceExceptions {
        try db.execute(
          sql:
            "INSERT INTO task_recurrence_exceptions (task_id, exception_date) "
            + "VALUES (?1, ?2)",
          arguments: [t.id, date])
      }
    }
  }

  private func seedList(
    _ writer: any DatabaseWriter, id: String, name: String = "Inbox"
  ) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES (?1, ?2, '0000000000000_0000_0000000000000aaa', "
          + "        '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        arguments: [id, name])
    }
  }

  private func seedTimezonePreference(
    _ writer: any DatabaseWriter, _ ianaName: String
  ) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO preferences (key, value, version, updated_at) "
          + "VALUES ('timezone', ?1, "
          + "        '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        arguments: ["\"\(ianaName)\""])
    }
  }

  private func seedActiveReminder(
    _ writer: any DatabaseWriter, id: String, taskId: String, reminderAt: String
  ) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at) "
          + "VALUES (?1, ?2, ?3, '0000000000000_0000_0000000000000abc', "
          + "        '2026-01-01T00:00:00Z')",
        arguments: [id, taskId, reminderAt])
    }
  }

  private func runCompletion(
    _ store: LorvexStore, taskId: String, now: String, version: String
  ) throws -> CompletionLifecycleTransitionResult {
    try store.writer.write { db in
      try LifecycleTransitions.applyCompletionTransition(
        db, taskId: tid(taskId), now: now, reminderVersion: version)
    }
  }

  private func runReopen(
    _ store: LorvexStore, taskId: String, oldStatus: TaskStatus, now: String,
    version: String
  ) throws -> ReopenLifecycleTransitionResult {
    try store.writer.write { db in
      try LifecycleTransitions.applyReopenTransition(
        db, taskId: tid(taskId), oldStatus: oldStatus, now: now,
        reminderVersion: version)
    }
  }

  // MARK: - recurrence.rs ports

  func testCadenceUsesCanonicalOccurrenceDateNotDeferredDueDate() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "monthly-task", title: "Monthly Report",
        dueDate: "2026-03-25",
        canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"FREQ":"MONTHLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-monthly",
        createdAt: "2026-03-10T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "monthly-task",
      now: "2026-03-25T10:00:00Z",
      version: "0000000000000_0000_0000000000000001")
    XCTAssertTrue(result.updated)
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    XCTAssertEqual(
      succId,
      TaskRecurrenceSuccessorID.make(
        parentTaskId: "monthly-task", recurrenceGroupId: "grp-monthly"))
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT due_date, canonical_occurrence_date, recurrence_instance_key, "
          + "spawned_from FROM tasks WHERE id = ?1",
        arguments: [succId])
    }
    let r = try XCTUnwrap(row)
    XCTAssertEqual(r[0] as String, "2026-04-15")
    XCTAssertEqual(r[1] as String, "2026-04-15")
    XCTAssertEqual(r[2] as String?, "grp-monthly:2026-04-15")
    XCTAssertEqual(r[3] as String?, "monthly-task")
  }

  /// R-3 (B): a schedule-anchored monthly task whose cadence anchor is the
  /// month-end (Jan-31) spawns its successor on the next month's last day
  /// (Feb-28) and stores BYMONTHDAY=-1, not a positive day. The successor rule
  /// is the synced canonical truth, so it must be the RFC-faithful, exportable
  /// form — never a clamped positive month-end day.
  func testScheduleAnchoredMonthEndInjectsNegativeBymonthday() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "month-end-task", title: "Month-end Report",
        dueDate: "2026-01-31",
        canonicalOccurrenceDate: "2026-01-31",
        recurrence: #"{"FREQ":"MONTHLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-month-end",
        createdAt: "2026-01-10T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "month-end-task",
      now: "2026-01-31T10:00:00Z",
      version: "0000000000000_0000_00000000000000e1")
    XCTAssertTrue(result.updated)
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT due_date, canonical_occurrence_date, recurrence FROM tasks WHERE id = ?1",
        arguments: [succId])
    }
    let r = try XCTUnwrap(row)
    XCTAssertEqual(r[0] as String, "2026-02-28")
    XCTAssertEqual(r[1] as String, "2026-02-28")
    XCTAssertEqual(r[2] as String, #"{"BYMONTHDAY":[-1],"FREQ":"MONTHLY","INTERVAL":1}"#)
  }

  /// Completion-anchored rule: the successor's due date is INTERVAL units after
  /// the *completion day*, not the canonical cadence. Here the task is due
  /// 2026-03-15 but completed late on 2026-03-25; a 1-week completion anchor
  /// lands the next occurrence on 2026-04-01 (completion + 7 days), proving the
  /// cadence anchor is ignored.
  func testCompletionAnchoredSpawnsRelativeToCompletionDay() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "after-completion", title: "Water the plant",
        dueDate: "2026-03-15",
        canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"ANCHOR":"completion","FREQ":"WEEKLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-ac",
        createdAt: "2026-03-10T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "after-completion",
      now: "2026-03-25T10:00:00Z",
      version: "0000000000000_0000_ac00000000000001")
    XCTAssertTrue(result.updated)
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT due_date, canonical_occurrence_date, recurrence "
          + "FROM tasks WHERE id = ?1",
        arguments: [succId])
    }
    let r = try XCTUnwrap(row)
    XCTAssertEqual(r[0] as String, "2026-04-01")
    XCTAssertEqual(r[1] as String, "2026-04-01")
    XCTAssertTrue((r[2] as String).contains("\"ANCHOR\":\"completion\""))
  }

  /// A monthly completion-anchored rule advances by whole months from the
  /// completion day, clamping the day-of-month against shorter months.
  func testCompletionAnchoredMonthlyAdvancesByMonths() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "ac-monthly", title: "Replace filter",
        dueDate: "2026-01-31",
        canonicalOccurrenceDate: "2026-01-31",
        recurrence: #"{"ANCHOR":"completion","FREQ":"MONTHLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-ac-m",
        createdAt: "2026-01-10T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "ac-monthly",
      now: "2026-01-31T10:00:00Z",
      version: "0000000000000_0000_ac00000000000002")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let due = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?1", arguments: [succId])
    }
    // Jan 31 + 1 month clamps to Feb 28 (2026 is not a leap year).
    XCTAssertEqual(due, "2026-02-28")
  }

  /// Concurrent completion addresses the same deterministic successor row even
  /// when completion-anchored devices calculated different dates.
  func testCompletionAnchoredSpawnReusesDeterministicPeerSuccessor() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTimezonePreference(store.writer, "UTC")
    try seedTask(
      store.writer,
      SeedTask(
        id: "ac-parent-dedup", title: "Water the plant",
        dueDate: "2026-03-15",
        canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"ANCHOR":"completion","FREQ":"WEEKLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-ac-dedup",
        createdAt: "2026-03-10T00:00:00Z"))
    let successorId = TaskRecurrenceSuccessorID.make(
      parentTaskId: "ac-parent-dedup", recurrenceGroupId: "grp-ac-dedup")
    // Peer's open successor: completed 2026-03-24 → due 2026-03-31. This
    // completion is later in HLC order and refreshes the generated schedule on
    // that same identity instead of creating a second branch.
    try seedTask(
      store.writer,
      SeedTask(
        id: successorId, title: "Water the plant",
        dueDate: "2026-03-31",
        canonicalOccurrenceDate: "2026-03-31",
        recurrence: #"{"ANCHOR":"completion","FREQ":"WEEKLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-ac-dedup",
        recurrenceInstanceKey: "grp-ac-dedup:2026-03-31",
        spawnedFrom: "ac-parent-dedup",
        version: "0000000000000_0000_0000000000000001",
        createdAt: "2026-03-24T00:00:00Z"))

    let result = try runCompletion(
      store, taskId: "ac-parent-dedup",
      now: "2026-03-20T10:00:00Z",
      version: "0000000000000_0000_acded00000000001")
    XCTAssertTrue(result.updated)
    XCTAssertEqual(result.spawnedSuccessorId, successorId)
    let openCount = try store.writer.read { db in
      try Int.fetchOne(
        db,
        sql:
          "SELECT COUNT(*) FROM tasks WHERE spawned_from = 'ac-parent-dedup' AND status = 'open'")
    }
    XCTAssertEqual(openCount, 1)
    let due = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?1", arguments: [successorId])
    }
    XCTAssertEqual(due, "2026-03-27")
  }

  /// COUNT still decrements on completion-anchored rules and terminates the
  /// series when exhausted.
  func testCompletionAnchoredHonorsCount() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "ac-count", title: "Twice",
        dueDate: "2026-04-04",
        canonicalOccurrenceDate: "2026-04-04",
        recurrence: #"{"ANCHOR":"completion","COUNT":2,"FREQ":"DAILY","INTERVAL":3}"#,
        recurrenceGroupId: "grp-ac-c",
        createdAt: "2026-04-01T00:00:00Z"))
    let r1 = try runCompletion(
      store, taskId: "ac-count",
      now: "2026-04-04T18:00:00Z",
      version: "0000000000000_0000_ac00000000000003")
    let succ1 = try XCTUnwrap(r1.spawnedSuccessorId)
    let (due1, rec1) = try store.writer.read { db -> (String, String) in
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT due_date, recurrence FROM tasks WHERE id = ?1",
          arguments: [succ1]))
      return (row[0], row[1])
    }
    XCTAssertEqual(due1, "2026-04-07")
    XCTAssertTrue(rec1.contains("\"COUNT\":1"))

    let r2 = try runCompletion(
      store, taskId: succ1,
      now: "2026-04-07T18:00:00Z",
      version: "0000000000000_0000_ac00000000000004")
    XCTAssertTrue(r2.updated)
    XCTAssertNil(r2.spawnedSuccessorId)
    let rollover = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT recurrence_rollover_state, recurrence_successor_id "
          + "FROM tasks WHERE id = ?1",
        arguments: [succ1])
    }
    XCTAssertEqual(rollover?[0] as String?, "ended")
    XCTAssertNil(rollover?[1] as String?)
  }

  func testCompletionTransitionDoesNotSpawnWhenNoRecurrence() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(id: "non-recurring", title: "One-off", createdAt: "2026-03-10T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "non-recurring",
      now: "2026-03-25T10:00:00Z",
      version: "0000000000000_0000_0000000000000002")
    XCTAssertTrue(result.updated)
    XCTAssertNil(result.spawnedSuccessorId)
  }

  func testSpawnSkipsExdateDates() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "daily-exdate", title: "Daily w/ exception",
        dueDate: "2026-04-04",
        canonicalOccurrenceDate: "2026-04-04",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-daily-exdate",
        recurrenceExceptions: ["2026-04-05"],
        createdAt: "2026-04-01T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "daily-exdate",
      now: "2026-04-04T18:00:00Z",
      version: "0000000000000_0000_0000000000000010")
    XCTAssertTrue(result.updated)
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let due = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?1",
        arguments: [succId])
    }
    XCTAssertEqual(due, "2026-04-06")
  }

  /// A future-dated EXDATE (not the immediate next slot) must be carried onto
  /// the spawned successor so a later generation still honours the skip.
  /// Regression for the successor losing all recurrence exceptions on spawn.
  func testSpawnCarriesRecurrenceExceptionsToSuccessor() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "weekly-sat", title: "Weekly w/ future exception",
        dueDate: "2026-06-20",
        canonicalOccurrenceDate: "2026-06-20",
        recurrence: #"{"FREQ":"WEEKLY","BYDAY":["SA"],"INTERVAL":1}"#,
        recurrenceGroupId: "grp-weekly-sat",
        recurrenceExceptions: ["2026-07-04"],
        createdAt: "2026-06-01T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "weekly-sat",
      now: "2026-06-20T18:00:00Z",
      version: "0000000000000_0000_0000000000000011")
    XCTAssertTrue(result.updated)
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    // Successor lands on the next Saturday (07-04 is still future, not skipped yet)...
    let due = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?1", arguments: [succId])
    }
    XCTAssertEqual(due, "2026-06-27")
    // ...and the future EXDATE is carried forward to the successor.
    let exceptions = try store.writer.read { db in
      try String.fetchAll(
        db,
        sql:
          "SELECT exception_date FROM task_recurrence_exceptions WHERE task_id = ?1 "
          + "ORDER BY exception_date",
        arguments: [succId])
    }
    XCTAssertEqual(exceptions, ["2026-07-04"])
  }

  // MARK: - reminder copy across DST

  /// A reminder copied to a recurrence successor must keep its *local
  /// wall-clock* time across a DST transition that falls between the parent and
  /// successor due dates. A WEEKLY parent due 2026-03-07 (America/New_York) with
  /// a 09:00 EST reminder (14:00Z) spawns a successor due 2026-03-14 — after US
  /// spring-forward (2026-03-08) — so the copy must land at 09:00 EDT (13:00Z),
  /// not the 14:00Z / "10:00" a fixed `days * 86400` UTC shift produces.
  func testSpawnCopiesReminderPreservingLocalWallClockAcrossSpringForward() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTimezonePreference(store.writer, "America/New_York")
    try seedTask(
      store.writer,
      SeedTask(
        id: "weekly-dst-spring", title: "Weekly across spring-forward",
        dueDate: "2026-03-07",
        canonicalOccurrenceDate: "2026-03-07",
        recurrence: #"{"FREQ":"WEEKLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-weekly-dst-spring",
        createdAt: "2026-03-01T00:00:00Z"))
    try seedActiveReminder(
      store.writer, id: "rem-spring", taskId: "weekly-dst-spring",
      reminderAt: "2026-03-07T14:00:00.000Z")  // 09:00 EST
    let result = try runCompletion(
      store, taskId: "weekly-dst-spring",
      now: "2026-03-07T18:00:00Z",
      version: "0000000000000_0000_d570000000000001")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let due = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?1", arguments: [succId])
    }
    XCTAssertEqual(due, "2026-03-14")
    let reminder = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT reminder_at, original_local_time, original_tz "
          + "FROM task_reminders WHERE task_id = ?1",
        arguments: [succId])
    }
    let r = try XCTUnwrap(reminder)
    XCTAssertEqual(r[0] as String, "2026-03-14T13:00:00.000Z")  // 09:00 EDT
    XCTAssertEqual(r[1] as String?, "09:00")
    XCTAssertEqual(r[2] as String?, "America/New_York")
  }

  /// Fall-back mirror of the spring-forward case, asserting the opposite (−1h)
  /// drift is corrected too. A WEEKLY parent due 2026-10-31 (America/New_York)
  /// with a 09:00 EDT reminder (13:00Z) spawns a successor due 2026-11-07 —
  /// after US fall-back (2026-11-01) — so the copy must stay at 09:00 EST
  /// (14:00Z), not the 13:00Z / "08:00" a fixed-seconds shift yields.
  func testSpawnCopiesReminderPreservingLocalWallClockAcrossFallBack() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTimezonePreference(store.writer, "America/New_York")
    try seedTask(
      store.writer,
      SeedTask(
        id: "weekly-dst-fall", title: "Weekly across fall-back",
        dueDate: "2026-10-31",
        canonicalOccurrenceDate: "2026-10-31",
        recurrence: #"{"FREQ":"WEEKLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-weekly-dst-fall",
        createdAt: "2026-10-01T00:00:00Z"))
    try seedActiveReminder(
      store.writer, id: "rem-fall", taskId: "weekly-dst-fall",
      reminderAt: "2026-10-31T13:00:00.000Z")  // 09:00 EDT
    let result = try runCompletion(
      store, taskId: "weekly-dst-fall",
      now: "2026-10-31T18:00:00Z",
      version: "0000000000000_0000_d570000000000002")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let due = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?1", arguments: [succId])
    }
    XCTAssertEqual(due, "2026-11-07")
    let reminder = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT reminder_at, original_local_time, original_tz "
          + "FROM task_reminders WHERE task_id = ?1",
        arguments: [succId])
    }
    let r = try XCTUnwrap(reminder)
    XCTAssertEqual(r[0] as String, "2026-11-07T14:00:00.000Z")  // 09:00 EST
    XCTAssertEqual(r[1] as String?, "09:00")
    XCTAssertEqual(r[2] as String?, "America/New_York")
  }

  func testSpawnWithCountDecrements() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "count-3", title: "Count-limited",
        dueDate: "2026-04-04",
        canonicalOccurrenceDate: "2026-04-04",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":3}"#,
        recurrenceGroupId: "grp-count",
        createdAt: "2026-04-01T00:00:00Z"))
    let r1 = try runCompletion(
      store, taskId: "count-3",
      now: "2026-04-04T18:00:00Z",
      version: "0000000000000_0000_0000000000000020")
    let succ1 = try XCTUnwrap(r1.spawnedSuccessorId)
    let rec1 = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT recurrence FROM tasks WHERE id = ?1",
        arguments: [succ1])
    }
    XCTAssertTrue(rec1?.contains("\"COUNT\":2") ?? false, "got: \(rec1 ?? "nil")")

    let r2 = try runCompletion(
      store, taskId: succ1,
      now: "2026-04-05T18:00:00Z",
      version: "0000000000000_0000_0000000000000021")
    let succ2 = try XCTUnwrap(r2.spawnedSuccessorId)
    let rec2 = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT recurrence FROM tasks WHERE id = ?1",
        arguments: [succ2])
    }
    XCTAssertTrue(rec2?.contains("\"COUNT\":1") ?? false)

    let r3 = try runCompletion(
      store, taskId: succ2,
      now: "2026-04-06T18:00:00Z",
      version: "0000000000000_0000_0000000000000022")
    XCTAssertTrue(r3.updated)
    XCTAssertNil(r3.spawnedSuccessorId)
  }

  func testSpawnWithUncappedCountDecrements() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "count-1001", title: "Long count",
        dueDate: "2026-04-04",
        canonicalOccurrenceDate: "2026-04-04",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":1001}"#,
        recurrenceGroupId: "grp-count-large",
        createdAt: "2026-04-01T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "count-1001",
      now: "2026-04-04T18:00:00Z",
      version: "0000000000000_0000_0000000000000023")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let rec = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT recurrence FROM tasks WHERE id = ?1",
        arguments: [succId])
    }
    XCTAssertTrue(rec?.contains("\"COUNT\":1000") ?? false, "got: \(rec ?? "nil")")
  }

  func testSpawnPreservesCanonicalOccurrenceDateIndependence() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "weekly-deferred", title: "Weekly Deferred",
        dueDate: "2026-03-25",
        canonicalOccurrenceDate: "2026-03-20",
        recurrence: #"{"FREQ":"WEEKLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-weekly-defer",
        createdAt: "2026-03-10T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "weekly-deferred",
      now: "2026-03-25T18:00:00Z",
      version: "0000000000000_0000_0000000000000030")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT due_date, canonical_occurrence_date FROM tasks WHERE id = ?1",
        arguments: [succId])
    }
    let r = try XCTUnwrap(row)
    XCTAssertEqual(r[0] as String, "2026-03-27")
    XCTAssertEqual(r[1] as String, "2026-03-27")
  }

  func testSpawnWithUntilStopsAfterBound() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "until-task", title: "Until Limited",
        dueDate: "2026-04-04",
        canonicalOccurrenceDate: "2026-04-04",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-04-06"}"#,
        recurrenceGroupId: "grp-until",
        createdAt: "2026-04-01T00:00:00Z"))
    let r1 = try runCompletion(
      store, taskId: "until-task",
      now: "2026-04-04T18:00:00Z",
      version: "0000000000000_0000_0000000000000040")
    let s1 = try XCTUnwrap(r1.spawnedSuccessorId)
    let due1 = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?1", arguments: [s1])
    }
    XCTAssertEqual(due1, "2026-04-05")

    let r2 = try runCompletion(
      store, taskId: s1,
      now: "2026-04-05T18:00:00Z",
      version: "0000000000000_0000_0000000000000041")
    let s2 = try XCTUnwrap(r2.spawnedSuccessorId)
    let due2 = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?1", arguments: [s2])
    }
    XCTAssertEqual(due2, "2026-04-06")

    let r3 = try runCompletion(
      store, taskId: s2,
      now: "2026-04-06T18:00:00Z",
      version: "0000000000000_0000_0000000000000042")
    XCTAssertTrue(r3.updated)
    XCTAssertNil(r3.spawnedSuccessorId)
  }

  func testSpawnPreservesPlannedDateOffset() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "offset-task", title: "Offset",
        dueDate: "2026-04-06",
        plannedDate: "2026-04-03",
        canonicalOccurrenceDate: "2026-04-06",
        recurrence: #"{"FREQ":"WEEKLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-offset",
        createdAt: "2026-03-30T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "offset-task",
      now: "2026-04-04T10:00:00Z",
      version: "0000000000000_0000_0000000000000050")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT due_date, planned_date FROM tasks WHERE id = ?1",
        arguments: [succId])
    }
    let r = try XCTUnwrap(row)
    XCTAssertEqual(r[0] as String, "2026-04-13")
    XCTAssertEqual(r[1] as String?, "2026-04-10")
  }

  func testSpawnWithoutPlannedDateLeavesNull() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "no-plan", title: "No plan",
        dueDate: "2026-04-06",
        canonicalOccurrenceDate: "2026-04-06",
        recurrence: #"{"FREQ":"WEEKLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-noplan",
        createdAt: "2026-03-30T00:00:00Z"))
    let result = try runCompletion(
      store, taskId: "no-plan",
      now: "2026-04-06T10:00:00Z",
      version: "0000000000000_0000_0000000000000051")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let planned = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT planned_date FROM tasks WHERE id = ?1",
        arguments: [succId])
    }
    XCTAssertNil(planned)
  }

  // MARK: - reopen lineage tests

  func testReopenDoesNotCancelUnrelatedSameTitleRecurringTask() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedList(store.writer, id: "list-X")
    try seedTask(
      store.writer,
      SeedTask(
        id: "parent-A", title: "Daily standup",
        status: "completed",
        listId: "list-X",
        dueDate: "2026-04-04",
        canonicalOccurrenceDate: "2026-04-04",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-project-A",
        completedAt: "2026-04-04T08:00:00Z",
        createdAt: "2026-04-01T00:00:00Z"))
    try seedTask(
      store.writer,
      SeedTask(
        id: "unrelated-B", title: "Daily standup",
        listId: "list-X",
        dueDate: "2026-04-05",
        canonicalOccurrenceDate: "2026-04-05",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-project-B",
        version: "0000000000000_0000_0000000000000001",
        createdAt: "2026-04-01T00:00:00Z"))
    let result = try runReopen(
      store, taskId: "parent-A", oldStatus: .completed,
      now: "2026-04-05T10:00:00Z",
      version: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    XCTAssertTrue(result.updated)
    XCTAssertTrue(result.transition.cancelledSuccessorIds.isEmpty)
    let status = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = 'unrelated-B'")
    }
    XCTAssertEqual(status, "open")
  }

  func testReopenIgnoresSameGroupTaskWithoutSpawnedFrom() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedList(store.writer, id: "list-Y")
    try seedTask(
      store.writer,
      SeedTask(
        id: "parent-A2", title: "Daily standup",
        status: "completed",
        listId: "list-Y",
        dueDate: "2026-04-10",
        canonicalOccurrenceDate: "2026-04-10",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-project-shared",
        completedAt: "2026-04-10T08:00:00Z",
        version: "0000000000000_0000_0000000000000010",
        createdAt: "2026-04-08T00:00:00Z"))
    try seedTask(
      store.writer,
      SeedTask(
        id: "legacy-succ", title: "Daily standup",
        listId: "list-Y",
        dueDate: "2026-04-11",
        canonicalOccurrenceDate: "2026-04-11",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-project-shared",
        version: "0000000000000_0000_0000000000000011",
        createdAt: "2026-04-08T00:00:00Z"))
    let result = try runReopen(
      store, taskId: "parent-A2", oldStatus: .completed,
      now: "2026-04-11T10:00:00Z",
      version: "0000000000000_0000_b0b0b0b0b0b0b0b0")
    XCTAssertTrue(result.updated)
    XCTAssertTrue(result.transition.cancelledSuccessorIds.isEmpty)
    let status = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = 'legacy-succ'")
    }
    XCTAssertEqual(status, "open")
  }

  /// Reopening a completed recurring parent must cancel its spawned successor
  /// even when the successor's due date is not strictly after the parent's.
  /// A completion-anchored WEEKLY task due Mar 15, completed early on Mar 1,
  /// spawns a successor due Mar 8 (completion + 7 days) — earlier than the
  /// parent's own Mar 15. The cancel query must scope by `spawned_from` +
  /// `status`, not `due_date > parent`, or the successor is stranded open.
  func testReopenCancelsSuccessorDuedOnOrBeforeParentDueDate() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTimezonePreference(store.writer, "UTC")
    try seedTask(
      store.writer,
      SeedTask(
        id: "ac-parent", title: "Weekly after completion",
        dueDate: "2026-03-15",
        canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"ANCHOR":"completion","FREQ":"WEEKLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-ac-reopen",
        createdAt: "2026-03-01T00:00:00Z"))
    // Complete early: successor lands on completion (Mar 1) + 7 days = Mar 8,
    // strictly before the parent's own Mar 15 due date.
    let completion = try runCompletion(
      store, taskId: "ac-parent",
      now: "2026-03-01T10:00:00Z",
      version: "0000000000000_0000_ac0e000000000001")
    let succId = try XCTUnwrap(completion.spawnedSuccessorId)
    let succDue = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?1", arguments: [succId])
    }
    XCTAssertEqual(succDue, "2026-03-08")

    let reopen = try runReopen(
      store, taskId: "ac-parent", oldStatus: .completed,
      now: "2026-03-02T10:00:00Z",
      version: "0000000000000_0000_ac0e000000000002")
    XCTAssertTrue(reopen.updated)
    XCTAssertEqual(reopen.transition.cancelledSuccessorIds, [succId])
    let statuses = try store.writer.read { db -> (String?, String?) in
      let parent = try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = 'ac-parent'")
      let succ = try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?1", arguments: [succId])
      return (parent, succ)
    }
    XCTAssertEqual(statuses.0, "open")
    XCTAssertEqual(statuses.1, "cancelled")
  }

  func testRecompleteRevivesSameSuccessorAndPreservesUserContent() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTimezonePreference(store.writer, "UTC")
    try seedTask(
      store.writer,
      SeedTask(
        id: "stable-parent", title: "Original title",
        dueDate: "2026-04-01",
        canonicalOccurrenceDate: "2026-04-01",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        recurrenceGroupId: "stable-group"))
    try seedActiveReminder(
      store.writer, id: "stable-parent-reminder", taskId: "stable-parent",
      reminderAt: "2026-04-01T09:00:00Z")

    let firstVersion = "0000000000001_0000_1111111111111111"
    let first = try runCompletion(
      store, taskId: "stable-parent", now: "2026-04-01T10:00:00Z",
      version: firstVersion)
    let successorId = try XCTUnwrap(first.spawnedSuccessorId)
    let successorReminderId = try XCTUnwrap(first.spawnedSuccessorReminderIds.first)

    let contentVersion = "0000000000002_0000_1111111111111111"
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET title = 'User title', body = 'User body', "
          + "content_version = ?1, version = ?1 WHERE id = ?2",
        arguments: [contentVersion, successorId])
    }

    let reopenVersion = "0000000000003_0000_1111111111111111"
    let reopen = try runReopen(
      store, taskId: "stable-parent", oldStatus: .completed,
      now: "2026-04-01T11:00:00Z", version: reopenVersion)
    XCTAssertEqual(reopen.transition.cancelledSuccessorIds, [successorId])
    XCTAssertTrue(reopen.transition.successorCancelSideEffects.cancelledReminderIds.contains(
      successorReminderId))
    // Simulate convergence preserving a successor as an independent root.
    // Re-completion is still allowed to re-authorize this reserved
    // deterministic id; user-authored content remains untouched.
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET spawned_from = NULL, spawned_from_version = NULL, "
          + "schedule_version = ?1, version = ?1 WHERE id = ?2",
        arguments: [reopenVersion, successorId])
    }

    let recompleteVersion = "0000000000004_0000_1111111111111111"
    let recomplete = try runCompletion(
      store, taskId: "stable-parent", now: "2026-04-01T12:00:00Z",
      version: recompleteVersion)
    XCTAssertEqual(recomplete.spawnedSuccessorId, successorId)
    XCTAssertTrue(recomplete.spawnedSuccessorChecklistItemIds.isEmpty)
    XCTAssertEqual(recomplete.spawnedSuccessorReminderIds, [successorReminderId])

    let rows = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT s.title, s.body, s.status, s.content_version, "
          + "s.spawned_from_version, p.recurrence_rollover_state, "
          + "p.recurrence_successor_id "
          + "FROM tasks s JOIN tasks p ON p.id = 'stable-parent' "
          + "WHERE s.id = ?1",
        arguments: [successorId])
    }
    let row = try XCTUnwrap(rows)
    XCTAssertEqual(row[0] as String, "User title")
    XCTAssertEqual(row[1] as String?, "User body")
    XCTAssertEqual(row[2] as String, "open")
    XCTAssertEqual(row[3] as String, contentVersion)
    XCTAssertEqual(row[4] as String?, recompleteVersion)
    XCTAssertEqual(row[5] as String, "authorized")
    XCTAssertEqual(row[6] as String?, successorId)
    let revivedReminder = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT cancelled_at, version FROM task_reminders WHERE id = ?1",
        arguments: [successorReminderId])
    }
    XCTAssertNil(revivedReminder?[0] as String?)
    XCTAssertEqual(revivedReminder?[1] as String?, recompleteVersion)
  }

  func testReopenRejectsAlreadyAdvancedSuccessorWithoutForking() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTimezonePreference(store.writer, "UTC")
    try seedTask(
      store.writer,
      SeedTask(
        id: "advanced-parent", title: "Parent",
        dueDate: "2026-04-01",
        canonicalOccurrenceDate: "2026-04-01",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        recurrenceGroupId: "advanced-group"))
    let parentCompletion = try runCompletion(
      store, taskId: "advanced-parent", now: "2026-04-01T10:00:00Z",
      version: "0000000000001_0000_2222222222222222")
    let successorId = try XCTUnwrap(parentCompletion.spawnedSuccessorId)
    _ = try runCompletion(
      store, taskId: successorId, now: "2026-04-02T10:00:00Z",
      version: "0000000000002_0000_2222222222222222")

    XCTAssertThrowsError(
      try runReopen(
        store, taskId: "advanced-parent", oldStatus: .completed,
        now: "2026-04-02T11:00:00Z",
        version: "0000000000003_0000_2222222222222222")
    ) { error in
      guard case StoreError.validation(let message) = error else {
        XCTFail("expected validation, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("already advanced"))
    }

    let parent = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT status, recurrence_rollover_state, recurrence_successor_id "
          + "FROM tasks WHERE id = 'advanced-parent'")
    }
    XCTAssertEqual(parent?[0] as String?, "completed")
    XCTAssertEqual(parent?[1] as String?, "authorized")
    XCTAssertEqual(parent?[2] as String?, successorId)
  }

  func testSomedaySuccessorIsRewindableAndCancelled() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTimezonePreference(store.writer, "UTC")
    try seedTask(
      store.writer,
      SeedTask(
        id: "someday-parent", title: "Parent",
        dueDate: "2026-04-01",
        canonicalOccurrenceDate: "2026-04-01",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        recurrenceGroupId: "someday-group"))
    let first = try runCompletion(
      store, taskId: "someday-parent", now: "2026-04-01T10:00:00Z",
      version: "0000000000001_0000_3333333333333333")
    let successorId = try XCTUnwrap(first.spawnedSuccessorId)
    try store.writer.write { db in
      let parkedVersion = "0000000000002_0000_3333333333333333"
      try db.execute(
        sql:
          "UPDATE tasks SET status = 'someday', lifecycle_version = ?1, "
          + "version = ?1 WHERE id = ?2",
        arguments: [parkedVersion, successorId])
    }

    let reopen = try runReopen(
      store, taskId: "someday-parent", oldStatus: .completed,
      now: "2026-04-01T11:00:00Z",
      version: "0000000000003_0000_3333333333333333")
    XCTAssertEqual(reopen.transition.cancelledSuccessorIds, [successorId])
    let status = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?1", arguments: [successorId])
    }
    XCTAssertEqual(status, "cancelled")
  }

  // MARK: - transitions.rs recurring cases

  func testApplyReopenTransitionCancelsSpawnedSuccessorAndCollectsSideEffects() throws {
    let store = try WorkflowTestSupport.freshStore()
    let successorId = TaskRecurrenceSuccessorID.make(
      parentTaskId: "parent", recurrenceGroupId: "grp-parent")
    try seedTask(
      store.writer,
      SeedTask(
        id: "parent", title: "Recurring Parent",
        status: "completed",
        dueDate: "2026-03-25",
        canonicalOccurrenceDate: "2026-03-25",
        recurrence: #"{"freq":"daily"}"#,
        recurrenceGroupId: "grp-parent",
        completedAt: "2026-03-25T08:00:00Z",
        recurrenceRolloverState: "authorized",
        recurrenceSuccessorId: successorId,
        createdAt: "2026-03-20T00:00:00Z"))
    try seedTask(
      store.writer,
      SeedTask(
        id: successorId, title: "Recurring Parent",
        dueDate: "2026-03-26",
        canonicalOccurrenceDate: "2026-03-26",
        recurrence: #"{"freq":"daily"}"#,
        recurrenceGroupId: "grp-parent",
        spawnedFrom: "parent",
        spawnedFromVersion: "0000000000000_0000_0000000000000000",
        version: "0000000000000_0000_0000000000000001",
        createdAt: "2026-03-20T00:00:00Z"))
    try seedTask(
      store.writer,
      SeedTask(
        id: "prereq", title: "Prereq",
        version: "0000000000000_0000_0000000000000002",
        createdAt: "2026-03-20T00:00:00Z"))
    try seedTask(
      store.writer,
      SeedTask(
        id: "dependent", title: "Dependent",
        version: "0000000000000_0000_0000000000000003",
        createdAt: "2026-03-20T00:00:00Z"))
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at) "
          + "VALUES ('rem-succ', ?1, '2026-03-26T09:00:00Z', "
          + "        '0000000000000_0000_0000000000000004', '2026-03-20T00:00:00Z')",
        arguments: [successorId])
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES (?1, 'prereq', '0000000000000_0000_0000000000000005', '2026-03-20T00:00:00Z')",
        arguments: [successorId])
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES ('dependent', ?1, '0000000000000_0000_0000000000000006', '2026-03-20T00:00:00Z')",
        arguments: [successorId])
    }
    let result = try runReopen(
      store, taskId: "parent", oldStatus: .completed,
      now: "2026-03-27T10:00:00Z",
      version: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    XCTAssertTrue(result.updated)
    XCTAssertEqual(result.transition.cancelledSuccessorIds, [successorId])
    XCTAssertEqual(
      result.transition.successorCancelSideEffects.cancelledReminderIds,
      ["rem-succ"])
    XCTAssertEqual(
      result.transition.successorCancelSideEffects.affectedDependentIds,
      ["dependent"])
    XCTAssertEqual(
      result.transition.successorCancelSideEffects.deletedDependencyEdges.count, 2)
    let successorStatus = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?1", arguments: [successorId])
    }
    XCTAssertEqual(successorStatus, "cancelled")
    let remaining = try store.writer.read { db in
      try Int.fetchOne(
        db,
        sql:
          "SELECT COUNT(*) FROM task_dependencies "
          + "WHERE task_id IN (?1, 'dependent') "
          + "OR depends_on_task_id IN (?1, 'dependent')",
        arguments: [successorId])
    }
    XCTAssertEqual(remaining, 0)
  }

  func testCompletionTransitionPropagatesSuccessorTagCopyFailures() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "recurring", title: "Recurring",
        dueDate: "2026-03-25",
        canonicalOccurrenceDate: "2026-03-25",
        recurrence: #"{"FREQ":"DAILY"}"#,
        recurrenceGroupId: "grp-recurring",
        createdAt: "2026-03-10T00:00:00Z"))
    try store.writer.write { db in
      try db.execute(sql: "DROP TABLE task_tags")
    }
    XCTAssertThrowsError(
      try runCompletion(
        store, taskId: "recurring",
        now: "2026-03-25T10:00:00Z",
        version: "0000000000000_0000_0000000000000003")
    ) { error in
      // GRDB surfaces missing tables as DatabaseError (Rust's StoreError::Sql
      // wraps rusqlite::Error; the Swift port lets DatabaseError propagate
      // as-is rather than wrapping it).
      XCTAssertTrue(error is DatabaseError, "expected DatabaseError, got \(error)")
    }
  }

  func testReopenTransitionPropagatesSuccessorCancelFailures() throws {
    let store = try WorkflowTestSupport.freshStore()
    let successorId = TaskRecurrenceSuccessorID.make(
      parentTaskId: "parent", recurrenceGroupId: "grp-parent")
    try seedTask(
      store.writer,
      SeedTask(
        id: "parent", title: "Recurring Parent",
        status: "completed",
        dueDate: "2026-03-25",
        canonicalOccurrenceDate: "2026-03-25",
        recurrence: #"{"FREQ":"DAILY"}"#,
        recurrenceGroupId: "grp-parent",
        completedAt: "2026-03-25T08:00:00Z",
        recurrenceRolloverState: "authorized",
        recurrenceSuccessorId: successorId,
        createdAt: "2026-03-20T00:00:00Z"))
    try seedTask(
      store.writer,
      SeedTask(
        id: successorId, title: "Recurring Parent",
        dueDate: "2026-03-26",
        canonicalOccurrenceDate: "2026-03-26",
        recurrence: #"{"FREQ":"DAILY"}"#,
        recurrenceGroupId: "grp-parent",
        spawnedFrom: "parent",
        spawnedFromVersion: "0000000000000_0000_0000000000000000",
        version: "0000000000000_0000_0000000000000001",
        createdAt: "2026-03-20T00:00:00Z"))
    try store.writer.write { db in
      try db.execute(sql: "DROP TABLE task_dependencies")
    }
    XCTAssertThrowsError(
      try runReopen(
        store, taskId: "parent", oldStatus: .completed,
        now: "2026-03-27T10:00:00Z",
        version: "0000000000000_0000_0000000000000004")
    ) { error in
      XCTAssertTrue(error is DatabaseError, "expected DatabaseError, got \(error)")
    }
  }

  func testCompletionTransitionSurfacesTimezonePreferenceLookupFailures() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "recurring", title: "Recurring",
        dueDate: "2026-03-25",
        canonicalOccurrenceDate: "2026-03-25",
        recurrence: #"{"FREQ":"DAILY"}"#,
        recurrenceGroupId: "grp-recurring",
        createdAt: "2026-03-10T00:00:00Z"))
    try store.writer.write { db in
      try db.execute(sql: "DROP TABLE preferences")
    }
    XCTAssertThrowsError(
      try runCompletion(
        store, taskId: "recurring",
        now: "2026-03-25T10:00:00Z",
        version: "0000000000000_0000_0000000000000004")
    ) { error in
      XCTAssertTrue(error is DatabaseError, "expected DatabaseError, got \(error)")
    }
  }

  func testCompletionTransitionRejectsMalformedTimezonePreference() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "recurring", title: "Recurring",
        dueDate: "2026-03-25",
        canonicalOccurrenceDate: "2026-03-25",
        recurrence: #"{"FREQ":"DAILY"}"#,
        recurrenceGroupId: "grp-recurring",
        createdAt: "2026-03-10T00:00:00Z"))
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO preferences (key, value, version, updated_at) "
          + "VALUES ('timezone', '\"definitely-not-a-timezone\"', "
          + "        '0000000000000_0000_0000000000000001', '2026-03-10T00:00:00Z')")
    }
    XCTAssertThrowsError(
      try runCompletion(
        store, taskId: "recurring",
        now: "2026-03-25T10:00:00Z",
        version: "0000000000000_0000_0000000000000005")
    ) { error in
      guard case StoreError.validation = error else {
        XCTFail("expected validation, got \(error)")
        return
      }
    }
  }

  func testCompletionTransitionRejectsInvalidNowTimestamp() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(
      store.writer,
      SeedTask(
        id: "recurring", title: "Recurring",
        dueDate: "2026-03-25",
        canonicalOccurrenceDate: "2026-03-25",
        recurrence: #"{"FREQ":"DAILY"}"#,
        recurrenceGroupId: "grp-recurring",
        createdAt: "2026-03-10T00:00:00Z"))
    XCTAssertThrowsError(
      try runCompletion(
        store, taskId: "recurring",
        now: "not-a-timestamp",
        version: "0000000000000_0000_0000000000000006")
    ) { error in
      guard case StoreError.validation = error else {
        XCTFail("expected validation, got \(error)")
        return
      }
    }
  }

  // MARK: - focus_rewire.rs ports

  private func seedDailyParent(
    _ writer: any DatabaseWriter, taskId: String, dueDate: String, createdAt: String
  ) throws {
    try seedTask(
      writer,
      SeedTask(
        id: taskId, title: "Daily",
        dueDate: dueDate,
        canonicalOccurrenceDate: dueDate,
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-rewire",
        createdAt: createdAt))
  }

  private func seedCurrentFocusItem(
    _ writer: any DatabaseWriter, date: String, taskId: String
  ) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO current_focus "
          + "(date, briefing, timezone, version, created_at, updated_at) "
          + "VALUES (?1, NULL, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', "
          + "        '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        arguments: [date])
      try db.execute(
        sql:
          "INSERT INTO current_focus_items (date, position, task_id) "
          + "VALUES (?1, 0, ?2)",
        arguments: [date, taskId])
    }
  }

  private func seedFocusScheduleBlock(
    _ writer: any DatabaseWriter, planDate: String, taskId: String
  ) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO focus_schedule "
          + "(date, rationale, timezone, version, created_at, updated_at) "
          + "VALUES (?1, NULL, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', "
          + "        '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        arguments: [planDate])
      try db.execute(
        sql:
          "INSERT INTO focus_schedule_blocks "
          + "(date, position, block_type, start_minutes, end_minutes, "
          + " task_id, calendar_event_id, title) "
          + "VALUES (?1, 0, 'task', 540, 600, ?2, NULL, 'Morning slot')",
        arguments: [planDate, taskId])
    }
  }

  func testSpawnRecurrenceSuccessorRewiresCurrentFocusItems() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedDailyParent(
      store.writer, taskId: "daily-rewire-a",
      dueDate: "2026-04-04", createdAt: "2026-04-01T00:00:00Z")
    try seedCurrentFocusItem(store.writer, date: "2026-04-04", taskId: "daily-rewire-a")
    let result = try runCompletion(
      store, taskId: "daily-rewire-a",
      now: "2026-04-04T18:00:00Z",
      version: "0000000000000_0000_2352a00000000001")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let rewired = try store.writer.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT task_id FROM current_focus_items "
          + "WHERE date = '2026-04-04' AND position = 0")
    }
    XCTAssertEqual(rewired, succId)
    XCTAssertEqual(result.rewiredCurrentFocusDates, ["2026-04-04"])
    XCTAssertTrue(result.rewiredFocusScheduleDates.isEmpty)
  }

  func testSpawnRecurrenceSuccessorRewiresFocusScheduleBlocksForTodayAndLater() throws {
    let store = try WorkflowTestSupport.freshStore()
    let parentID = "00000000-0000-7000-8000-00000000000b"
    try seedDailyParent(
      store.writer, taskId: parentID,
      dueDate: "2026-04-04", createdAt: "2026-04-01T00:00:00Z")
    try seedFocusScheduleBlock(store.writer, planDate: "2026-04-04", taskId: parentID)
    try seedFocusScheduleBlock(store.writer, planDate: "2026-04-05", taskId: parentID)
    let result = try runCompletion(
      store, taskId: parentID,
      now: "2026-04-04T18:00:00Z",
      version: "0000000000000_0000_2352b00000000001")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let pair = try store.writer.read { db in
      try Row.fetchAll(
        db,
        sql:
          "SELECT date, task_id FROM focus_schedule_blocks "
          + "WHERE position = 0 ORDER BY date ASC")
    }
    XCTAssertEqual(pair.count, 2)
    XCTAssertEqual(pair[0][0] as String, "2026-04-04")
    XCTAssertEqual(pair[0][1] as String, succId)
    XCTAssertEqual(pair[1][0] as String, "2026-04-05")
    XCTAssertEqual(pair[1][1] as String, succId)
    XCTAssertEqual(
      result.rewiredFocusScheduleDates, ["2026-04-04", "2026-04-05"])
  }

  func testSpawnRecurrenceSuccessorPreservesHistoricalFocusBlocks() throws {
    let store = try WorkflowTestSupport.freshStore()
    let parentID = "00000000-0000-7000-8000-00000000000c"
    try seedDailyParent(
      store.writer, taskId: parentID,
      dueDate: "2026-04-04", createdAt: "2026-04-01T00:00:00Z")
    try seedFocusScheduleBlock(store.writer, planDate: "2026-04-03", taskId: parentID)
    try seedCurrentFocusItem(store.writer, date: "2026-04-02", taskId: parentID)
    try seedFocusScheduleBlock(store.writer, planDate: "2026-04-04", taskId: parentID)
    let result = try runCompletion(
      store, taskId: parentID,
      now: "2026-04-04T18:00:00Z",
      version: "0000000000000_0000_2352c00000000001")
    let succId = try XCTUnwrap(result.spawnedSuccessorId)
    let histBlock = try store.writer.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT task_id FROM focus_schedule_blocks "
          + "WHERE date = '2026-04-03' AND position = 0")
    }
    XCTAssertEqual(histBlock, parentID)
    let histItem = try store.writer.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT task_id FROM current_focus_items "
          + "WHERE date = '2026-04-02' AND position = 0")
    }
    XCTAssertEqual(histItem, parentID)
    let todayBlock = try store.writer.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT task_id FROM focus_schedule_blocks "
          + "WHERE date = '2026-04-04' AND position = 0")
    }
    XCTAssertEqual(todayBlock, succId)
    XCTAssertEqual(result.rewiredFocusScheduleDates, ["2026-04-04"])
    XCTAssertTrue(result.rewiredCurrentFocusDates.isEmpty)
  }

  func testReopenRestoresSuccessorFocusReferencesToParent() throws {
    let store = try WorkflowTestSupport.freshStore()
    let parentId = "00000000-0000-7000-8000-00000000000d"
    try seedDailyParent(
      store.writer, taskId: parentId,
      dueDate: "2026-04-04", createdAt: "2026-04-01T00:00:00Z")
    try seedCurrentFocusItem(
      store.writer, date: "2026-04-04", taskId: parentId)
    try seedCurrentFocusItem(
      store.writer, date: "2026-04-05", taskId: parentId)
    try seedFocusScheduleBlock(
      store.writer, planDate: "2026-04-04", taskId: parentId)

    let completion = try runCompletion(
      store, taskId: parentId,
      now: "2026-04-04T18:00:00Z",
      version: "0000000000001_0000_2352d00000000001")
    let successorId = try XCTUnwrap(completion.spawnedSuccessorId)

    // Simulate the parent being independently added to the same day's focus
    // after spawn. Rewind must not violate the per-day task uniqueness index.
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO current_focus_items (date, position, task_id) "
          + "VALUES ('2026-04-04', 1, ?1)",
        arguments: [parentId])
    }

    let reopen = try runReopen(
      store, taskId: parentId, oldStatus: .completed,
      now: "2026-04-04T19:00:00Z",
      version: "0000000000002_0000_2352d00000000001")

    XCTAssertEqual(reopen.transition.cancelledSuccessorIds, [successorId])
    XCTAssertEqual(
      reopen.transition.rewiredCurrentFocusDates,
      ["2026-04-04", "2026-04-05"])
    XCTAssertEqual(
      reopen.transition.rewiredFocusScheduleDates,
      ["2026-04-04"])

    let currentRows = try store.writer.read { db in
      try Row.fetchAll(
        db,
        sql:
          "SELECT date, task_id FROM current_focus_items "
          + "WHERE date IN ('2026-04-04', '2026-04-05') "
          + "ORDER BY date ASC, position ASC")
    }
    XCTAssertEqual(currentRows.count, 2)
    XCTAssertEqual(currentRows[0][0] as String, "2026-04-04")
    XCTAssertEqual(currentRows[0][1] as String, parentId)
    XCTAssertEqual(currentRows[1][0] as String, "2026-04-05")
    XCTAssertEqual(currentRows[1][1] as String, parentId)

    let scheduledTaskId = try store.writer.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT task_id FROM focus_schedule_blocks "
          + "WHERE date = '2026-04-04' AND position = 0")
    }
    XCTAssertEqual(scheduledTaskId, parentId)
  }
}
