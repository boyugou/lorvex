import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Tests covering the smaller per-field task workflow mutations ported under
/// `lorvex-workflow/src/{task_ai_notes,task_bookkeeping,
/// task_recurrence,task_checklist,task_deferral}.rs`.
///
/// `task_ai_notes` and `task_deferral` carry inline `#[test]` cases in Rust;
/// the rest pin the typed contract on each helper.
final class TaskSmallOpsTests: XCTestCase {
  // MARK: - HLC + store helpers

  private final class CountingHlcHandle: HlcStateHandle, @unchecked Sendable {
    private var counter: UInt64 = 0
    func generate() -> Hlc {
      defer { counter += 1 }
      return try! Hlc(physicalMs: counter, counter: 0, deviceSuffix: "abcdef0123456789")
    }
  }
  private func makeSession() -> HlcSession { HlcSession(handle: CountingHlcHandle()) }

  private func freshStore() throws -> LorvexStore {
    let s = try WorkflowTestSupport.freshStore()
    try s.writer.write { db in
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('inbox', 'Inbox', '0000000000000_0000_0000000000000aaa', "
          + "        '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')")
    }
    return s
  }

  /// Seed a task via the workflow-level `TaskCreate.createTask` (matches
  /// the project guidance). Uses the supplied `session` so subsequent
  /// HLC stamps in the same test monotonically dominate the row's
  /// seed-time `version` — critical for the LWW-gated parent-task touch.
  private func seedTask(
    _ store: LorvexStore, session: HlcSession, id: String = "task-small-1"
  ) throws -> TaskId {
    let r = try store.writer.write { db in
      try TaskCreate.createTask(
        db, hlc: session,
        input: CreateTaskInput(
          id: id,
          task: TaskCreateInput(title: "Seed", listId: .set("inbox")),
          includeAdvice: false))
    }
    return r.taskId
  }

  private func seedTask(_ store: LorvexStore, id: String = "task-small-1") throws -> TaskId {
    try seedTask(store, session: makeSession(), id: id)
  }

  /// Seed a task and reset its `version` to the canonical low watermark
  /// so any reasonable HLC stamp in the test phase wins the LWW gate.
  /// Use for tests of LWW-gated ops where the seeded version would
  /// otherwise out-dominate fresh-session stamps.
  private func seedTaskWithLowWatermark(
    _ store: LorvexStore, id: String = "task-small-1"
  ) throws -> TaskId {
    let taskId = try seedTask(store, id: id)
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET content_version = ?1, schedule_version = ?1, "
          + "lifecycle_version = ?1, archive_version = ?1, version = ?1 WHERE id = ?2",
        arguments: [
          "0000000000000_0000_0000000000000000", taskId.rawValue,
        ])
    }
    return taskId
  }

  // ==========================================================================
  // task_ai_notes — set_ai_notes_op
  // ==========================================================================

  func testSetAiNotesMissingRowReturnsNotFound() throws {
    let store = try freshStore()
    try store.writer.write { db in
      do {
        try TaskAiNotes.setAiNotesOp(
          db,
          taskId: TaskId(trusted: "01966a3f-7c8b-7d4e-8f3a-000000000002"),
          notes: "note",
          version: "1000000000000_0000_0000000000000000",
          now: "2026-04-01T09:00:00Z")
        XCTFail("expected NotFound")
      } catch let e as StoreError {
        guard case .notFound = e else { XCTFail("expected NotFound, got \(e)"); return }
      }
    }
  }

  func testSetAiNotesExistingRowWithHigherVersionReturnsStaleVersion() throws {
    let store = try freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, priority, defer_count, version, "
          + "created_at, updated_at) VALUES (?, 't', 'open', 3, 0, ?, "
          + "'2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        arguments: [
          "01966a3f-7c8b-7d4e-8f3a-000000000002",
          "9999913599999_0000_ffffffffffffffff",
        ])
      do {
        try TaskAiNotes.setAiNotesOp(
          db,
          taskId: TaskId(trusted: "01966a3f-7c8b-7d4e-8f3a-000000000002"),
          notes: "note",
          version: "0000000000001_0000_0000000000000000",
          now: "2026-04-01T09:00:00Z")
        XCTFail("expected StaleVersion")
      } catch let e as StoreError {
        guard case .staleVersion = e else {
          XCTFail("expected StaleVersion, got \(e)"); return
        }
      }
    }
  }

  func testSetAiNotesAppliesAndBumpsVersion() throws {
    let store = try freshStore()
    let id = try seedTask(store)
    try store.writer.write { db in
      try TaskAiNotes.setAiNotesOp(
        db, taskId: id, notes: "fresh note",
        version: "9999913599999_9999_ffffffffffffffff",
        now: "2026-05-01T00:00:00Z")
    }
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT ai_notes, version, updated_at FROM tasks WHERE id = ?",
        arguments: [id.rawValue])
      XCTAssertEqual(row?["ai_notes"] as String?, "fresh note")
      XCTAssertEqual(row?["version"] as String?, "9999913599999_9999_ffffffffffffffff")
    }
  }

  // ==========================================================================
  // task_recurrence — setTaskRecurrence
  // ==========================================================================

  func testSetTaskRecurrenceAppliesRuleAndDueDateUnchanged() throws {
    let store = try freshStore()
    let id = try seedTaskWithLowWatermark(store, id: "task-rec-1")
    // Recurring tasks require a due_date; set one on the seed.
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET due_date = '2026-05-10' WHERE id = ?",
        arguments: [id.rawValue])
    }
    let session = makeSession()
    let result = try store.writer.write { db in
      try TaskRecurrence.setTaskRecurrence(
        db, hlc: session,
        input: TaskRecurrence.SetTaskRecurrenceInput(
          taskId: id,
          rule: TaskRecurrence.RuleInput(freq: "weekly", interval: 2, byday: ["MO"])
        ))
    }
    XCTAssertEqual(result.taskId, id.asString)
    XCTAssertTrue(result.summary.contains("WEEKLY"))
    XCTAssertTrue(result.summary.contains("every 2"))
    XCTAssertTrue(result.summary.contains("on MO"))
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT recurrence FROM tasks WHERE id = ?",
        arguments: [id.rawValue])
      let rule: String? = row?["recurrence"]
      XCTAssertNotNil(rule)
      XCTAssertTrue(rule?.contains("WEEKLY") ?? false)
    }
  }

  func testSetTaskRecurrenceRejectsInvalidFreq() throws {
    let store = try freshStore()
    let id = try seedTask(store, id: "task-rec-2")
    let session = makeSession()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskRecurrence.setTaskRecurrence(
          db, hlc: session,
          input: TaskRecurrence.SetTaskRecurrenceInput(
            taskId: id,
            rule: TaskRecurrence.RuleInput(freq: "hourly")))
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(m, "freq must be one of daily, weekly, monthly, yearly")
    }
  }

  // ==========================================================================
  // task_checklist
  // ==========================================================================

  func testChecklistAddInsertsAtEnd() throws {
    let store = try freshStore()
    let id = try seedTaskWithLowWatermark(store, id: "task-cl-1")
    let session = makeSession()
    let r = try store.writer.write { db in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.AddInput(taskId: id, text: "First"))
    }
    XCTAssertEqual(r.taskId, id.asString)
    XCTAssertEqual(r.itemSyncChanges.count, 1)
    XCTAssertEqual(r.itemSyncChanges[0].operation, .upsert)
    XCTAssertTrue(r.summary.hasPrefix("Added checklist item 'First' for"))

    try store.writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql:
          "SELECT id, text, position FROM task_checklist_items WHERE task_id = ? "
          + "ORDER BY position",
        arguments: [id.rawValue])
      XCTAssertEqual(rows.count, 1)
      XCTAssertEqual(rows[0]["text"] as String?, "First")
      XCTAssertEqual(rows[0]["position"] as Int64?, 0)
    }
  }

  func testChecklistAddRejectsEmptyText() throws {
    let store = try freshStore()
    let id = try seedTaskWithLowWatermark(store, id: "task-cl-2")
    let session = makeSession()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskChecklist.addTaskChecklistItem(
          db, hlc: session,
          input: TaskChecklist.AddInput(taskId: id, text: "   "))
      }
    ) { e in
      guard case StoreError.validation = e else {
        XCTFail("expected validation, got \(e)"); return
      }
    }
  }

  func testChecklistAddRejectsOutOfRangePosition() throws {
    let store = try freshStore()
    let id = try seedTaskWithLowWatermark(store, id: "task-cl-3")
    let session = makeSession()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskChecklist.addTaskChecklistItem(
          db, hlc: session,
          input: TaskChecklist.AddInput(taskId: id, text: "X", position: 99))
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("got \(e)"); return
      }
      XCTAssertTrue(m.contains("out of range"))
    }
  }

  func testChecklistUpdateRewritesText() throws {
    let store = try freshStore()
    let id = try seedTaskWithLowWatermark(store, id: "task-cl-4")
    let session = makeSession()
    let added = try store.writer.write { db in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.AddInput(taskId: id, text: "Old"))
    }
    let itemId = ChecklistItemId(trusted: added.itemSyncChanges[0].itemId)
    let updated = try store.writer.write { db in
      try TaskChecklist.updateTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.UpdateInput(itemId: itemId, text: "New"))
    }
    XCTAssertTrue(updated.summary.contains("Updated checklist item 'Old'"))
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT text FROM task_checklist_items WHERE id = ?",
        arguments: [itemId.rawValue])
      XCTAssertEqual(row?["text"] as String?, "New")
    }
  }

  func testChecklistToggleSetsAndClearsCompletedAt() throws {
    let store = try freshStore()
    let id = try seedTaskWithLowWatermark(store, id: "task-cl-5")
    let session = makeSession()
    let added = try store.writer.write { db in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.AddInput(taskId: id, text: "Step"))
    }
    let itemId = ChecklistItemId(trusted: added.itemSyncChanges[0].itemId)

    let completedR = try store.writer.write { db in
      try TaskChecklist.toggleTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.ToggleInput(itemId: itemId, completed: true))
    }
    XCTAssertTrue(completedR.summary.contains("Completed"))
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT completed_at FROM task_checklist_items WHERE id = ?",
        arguments: [itemId.rawValue])
      XCTAssertNotNil(row?["completed_at"] as String?)
    }
    let reopenedR = try store.writer.write { db in
      try TaskChecklist.toggleTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.ToggleInput(itemId: itemId, completed: false))
    }
    XCTAssertTrue(reopenedR.summary.contains("Reopened"))
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT completed_at FROM task_checklist_items WHERE id = ?",
        arguments: [itemId.rawValue])
      XCTAssertNil(row?["completed_at"] as String?)
    }
  }

  func testChecklistRemoveRepositionsRemainingAndReportsDelete() throws {
    let store = try freshStore()
    let id = try seedTaskWithLowWatermark(store, id: "task-cl-6")
    let session = makeSession()
    let a = try store.writer.write { db in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.AddInput(taskId: id, text: "A"))
    }
    _ = try store.writer.write { db in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.AddInput(taskId: id, text: "B"))
    }
    let aId = ChecklistItemId(trusted: a.itemSyncChanges[0].itemId)
    let removed = try store.writer.write { db in
      try TaskChecklist.removeTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.RemoveInput(itemId: aId))
    }
    XCTAssertEqual(removed.itemSyncChanges.first?.operation, .delete)
    XCTAssertEqual(removed.itemSyncChanges.first?.itemId, aId.rawValue)
    XCTAssertNotNil(removed.itemSyncChanges.first?.snapshot)
    try store.writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql:
          "SELECT text, position FROM task_checklist_items WHERE task_id = ? "
          + "ORDER BY position",
        arguments: [id.rawValue])
      XCTAssertEqual(rows.count, 1)
      XCTAssertEqual(rows[0]["text"] as String?, "B")
      XCTAssertEqual(rows[0]["position"] as Int64?, 0)
    }
  }

  func testChecklistReorderRejectsWrongCount() throws {
    let store = try freshStore()
    let id = try seedTaskWithLowWatermark(store, id: "task-cl-7")
    let session = makeSession()
    let a = try store.writer.write { db in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.AddInput(taskId: id, text: "A"))
    }
    let _ = try store.writer.write { db in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: session,
        input: TaskChecklist.AddInput(taskId: id, text: "B"))
    }
    let aId = ChecklistItemId(trusted: a.itemSyncChanges[0].itemId)
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskChecklist.reorderTaskChecklistItems(
          db, hlc: session,
          input: TaskChecklist.ReorderInput(taskId: id, itemIds: [aId]))
      }
    ) { e in
      guard case StoreError.validation(let m) = e else { XCTFail("got \(e)"); return }
      XCTAssertTrue(m.contains("requires exactly 2 ids"))
    }
  }

  func testChecklistReorderAppliesNewPositions() throws {
    let store = try freshStore()
    let id = try seedTaskWithLowWatermark(store, id: "task-cl-8")
    let session = makeSession()
    let a = try store.writer.write { db in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: session, input: TaskChecklist.AddInput(taskId: id, text: "A"))
    }
    let b = try store.writer.write { db in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: session, input: TaskChecklist.AddInput(taskId: id, text: "B"))
    }
    let aId = ChecklistItemId(trusted: a.itemSyncChanges[0].itemId)
    // After the second add, `ordered_ids = [A, B_new]` so
    // `item_sync_changes[1]` is the freshly inserted B.
    let bId = ChecklistItemId(trusted: b.itemSyncChanges[1].itemId)
    _ = try store.writer.write { db in
      try TaskChecklist.reorderTaskChecklistItems(
        db, hlc: session,
        input: TaskChecklist.ReorderInput(taskId: id, itemIds: [bId, aId]))
    }
    try store.writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql:
          "SELECT text, position FROM task_checklist_items WHERE task_id = ? "
          + "ORDER BY position",
        arguments: [id.rawValue])
      XCTAssertEqual(rows.map { $0["text"] as String? }, ["B", "A"])
      XCTAssertEqual(rows.map { $0["position"] as Int64? }, [0, 1])
    }
  }

  // ==========================================================================
  // task_deferral — defer_task / reset_task_deferral / restore_task_deferral
  // ==========================================================================

  /// Reminder-version supplier matching the Rust test's
  /// `test_reminder_version()` closure.
  private func reminderVersionSupplier() -> () throws -> String {
    return { "1711712640000_0001_0e1d000000000001" }
  }

  /// Seed a minimal task row at the canonical low watermark used by the
  /// Rust deferral tests so the LWW gate accepts any realistic stamp.
  private func setupDeferralStore() throws -> LorvexStore {
    let store = try freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, priority, defer_count, version, "
          + "created_at, updated_at) VALUES "
          + "('t1', 'Test Task', 'open', 3, 0, "
          + "'0000000000000_0000_0000000000000000', '2026-03-27T00:00:00Z', "
          + "'2026-03-27T00:00:00Z')")
    }
    return store
  }

  private func seedReminder(
    _ store: LorvexStore,
    _ reminderId: String,
    _ reminderAt: String,
    dismissedAt: String? = nil,
    cancelledAt: String? = nil
  ) throws {
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_reminders "
          + "(id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at) "
          + "VALUES (?, 't1', ?, ?, ?, "
          + "'0000000000000_0000_0000000000000000', '2026-03-27T00:00:00Z')",
        arguments: [reminderId, reminderAt, dismissedAt, cancelledAt])
    }
  }

  private func reminderAt(_ store: LorvexStore, _ reminderId: String) throws -> String {
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT reminder_at FROM task_reminders WHERE id = ?",
        arguments: [reminderId])
      return row?["reminder_at"] as String? ?? ""
    }
  }

  func testDeferWithDateUpdatesPlannedDateAndIncrementsCount() throws {
    let store = try setupDeferralStore()
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertTrue(r.updated)
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT planned_date, defer_count, last_deferred_at, version "
          + "FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["planned_date"] as String?, "2026-04-01")
      XCTAssertEqual(row?["defer_count"] as Int64?, 1)
      XCTAssertEqual(row?["last_deferred_at"] as String?, "2026-03-27T12:00:00Z")
      XCTAssertEqual(row?["version"] as String?, "0000000000001_0000_0000000000000001")
    }
  }

  func testDeferWithValidStructuredReasonPersists() throws {
    let store = try setupDeferralStore()
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01", lastDeferReason: "low_energy"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertTrue(r.updated)
    try store.writer.read { db in
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT last_defer_reason FROM tasks WHERE id = 't1'"),
        "low_energy")
    }
  }

  /// SB7: the structured defer-reason allowlist is enforced in the core
  /// `TaskDeferral` writer, not only in the MCP handler, so a non-MCP caller
  /// gets a typed validation error instead of reaching the raw
  /// `CHECK (last_defer_reason IN (...))`.
  func testDeferWithUnknownStructuredReasonThrowsValidation() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      do {
        _ = try TaskDeferral.deferTask(
          db, taskId: TaskId(trusted: "t1"),
          patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01", lastDeferReason: "procrastinated"),
          version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
          nextReminderVersion: reminderVersionSupplier())
        XCTFail("expected StoreError.validation for an unknown defer reason")
      } catch let e as StoreError {
        guard case let .validation(msg) = e else {
          return XCTFail("expected .validation, got \(e)")
        }
        XCTAssertTrue(msg.contains("last_defer_reason"), "got: \(msg)")
      }
      // The rejected defer must not have partially mutated the row.
      let row = try Row.fetchOne(
        db, sql: "SELECT defer_count, last_defer_reason FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["defer_count"] as Int64?, 0)
      XCTAssertNil(row?["last_defer_reason"] as String?)
    }
  }

  func testDeferWithNewPlannedDateShiftsOnlyPendingReminders() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET planned_date = '2030-04-17' WHERE id = 't1'")
    }
    try seedReminder(store, "r-active", "2030-04-17T13:45:00.000000Z")
    try seedReminder(store, "r-past", "2020-01-01T00:00:00.000000Z")
    try seedReminder(
      store, "r-dismissed", "2030-04-17T13:45:00.000000Z",
      dismissedAt: "2026-03-27T00:00:00Z")
    try seedReminder(
      store, "r-cancelled", "2030-04-17T13:45:00.000000Z",
      cancelledAt: "2026-03-27T00:00:00Z")

    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2030-04-20"),
        version: "1711712640000_0001_7a5c000000000001",
        now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertTrue(r.updated)
    XCTAssertEqual(r.shiftedReminderIds, ["r-active"])
    let active = try reminderAt(store, "r-active")
    XCTAssertTrue(
      active.hasPrefix("2030-04-20T13:45:00"),
      "active reminder should move by +3 days; got \(active)")
    XCTAssertEqual(try reminderAt(store, "r-past"), "2020-01-01T00:00:00.000000Z")
    XCTAssertEqual(
      try reminderAt(store, "r-dismissed"), "2030-04-17T13:45:00.000000Z")
    XCTAssertEqual(
      try reminderAt(store, "r-cancelled"), "2030-04-17T13:45:00.000000Z")
  }

  func testDeferUsesDueDateAsReminderShiftAnchorWhenPlannedAbsent() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET due_date = '2030-04-17' WHERE id = 't1'")
    }
    try seedReminder(store, "r-due", "2030-04-17T13:45:00.000000Z")
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2030-04-20"),
        version: "1711712640000_0001_7a5c000000000001",
        now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertEqual(r.shiftedReminderIds, ["r-due"])
    XCTAssertTrue(try reminderAt(store, "r-due").hasPrefix("2030-04-20T13:45:00"))
  }

  func testDeferWithoutExistingDateAnchorDoesNotShiftReminders() throws {
    let store = try setupDeferralStore()
    try seedReminder(store, "r-unanchored", "2030-04-17T13:45:00.000000Z")
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2030-04-20"),
        version: "1711712640000_0001_7a5c000000000001",
        now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertTrue(r.shiftedReminderIds.isEmpty)
    XCTAssertEqual(
      try reminderAt(store, "r-unanchored"), "2030-04-17T13:45:00.000000Z")
  }

  func testDeferWithoutDateLeavesPlannedDateUnchanged() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET planned_date = '2026-03-28' WHERE id = 't1'")
    }
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertTrue(r.updated)
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT planned_date, defer_count FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["planned_date"] as String?, "2026-03-28")
      XCTAssertEqual(row?["defer_count"] as Int64?, 1)
    }
  }

  func testDeferWithAiNotesWritesAtomically() throws {
    let store = try setupDeferralStore()
    _ = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(
          plannedDate: "2026-04-01",
          aiNotes: "Deferred (#1): too busy today"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT ai_notes, defer_count, version "
          + "FROM tasks WHERE id = 't1'")
      XCTAssertEqual(
        row?["ai_notes"] as String?, "Deferred (#1): too busy today")
      XCTAssertEqual(row?["defer_count"] as Int64?, 1)
      XCTAssertEqual(row?["version"] as String?, "0000000000001_0000_0000000000000001")
    }
  }

  func testDeferWithoutAiNotesLeavesExistingNotesUnchanged() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET ai_notes = 'existing notes' WHERE id = 't1'")
    }
    _ = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT ai_notes FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["ai_notes"] as String?, "existing notes")
    }
  }

  func testDeferCompletedTaskReturnsFalse() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          UPDATE tasks
             SET status = 'completed', completed_at = '2026-03-27T12:00:00Z'
           WHERE id = 't1'
          """)
    }
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertFalse(r.updated)
  }

  func testDeferCancelledTaskReturnsFalse() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(sql: "UPDATE tasks SET status = 'cancelled' WHERE id = 't1'")
    }
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertFalse(r.updated)
  }

  func testDeferNonexistentTaskReturnsFalse() throws {
    let store = try setupDeferralStore()
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "nonexistent"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertFalse(r.updated)
  }

  func testDeferIncrementsCountCumulatively() throws {
    let store = try setupDeferralStore()
    _ = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    _ = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-02"),
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T13:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT defer_count FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["defer_count"] as Int64?, 2)
    }
  }

  func testDeferVersionIsProperlyWritten() throws {
    let store = try setupDeferralStore()
    let stamp = "1711712640000_0001_abcdef1200000000"
    _ = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01"),
        version: stamp, now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT version FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["version"] as String?, stamp)
    }
  }

  func testResetTaskDeferralClearsFields() throws {
    let store = try setupDeferralStore()
    _ = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(
          plannedDate: "2026-04-01", lastDeferReason: "not_today"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    let ok = try store.writer.write { db in
      try TaskDeferral.resetTaskDeferral(
        db, taskId: TaskId(trusted: "t1"),
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T14:00:00Z")
    }
    XCTAssertTrue(ok)
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT planned_date, defer_count, last_deferred_at, last_defer_reason, "
          + "version, updated_at FROM tasks WHERE id = 't1'")
      XCTAssertNil(row?["planned_date"] as String?)
      XCTAssertEqual(row?["defer_count"] as Int64?, 0)
      XCTAssertNil(row?["last_deferred_at"] as String?)
      XCTAssertNil(row?["last_defer_reason"] as String?)
      XCTAssertEqual(row?["version"] as String?, "0000000000002_0000_0000000000000002")
      XCTAssertEqual(row?["updated_at"] as String?, "2026-03-27T14:00:00Z")
    }
  }

  func testResetDeferralCompletedTaskReturnsFalse() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          UPDATE tasks
             SET status = 'completed', completed_at = '2026-03-27T12:00:00Z'
           WHERE id = 't1'
          """)
    }
    let ok = try store.writer.write { db in
      try TaskDeferral.resetTaskDeferral(
        db, taskId: TaskId(trusted: "t1"),
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T14:00:00Z")
    }
    XCTAssertFalse(ok)
  }

  func testResetDeferralNonexistentTaskReturnsFalse() throws {
    let store = try setupDeferralStore()
    let ok = try store.writer.write { db in
      try TaskDeferral.resetTaskDeferral(
        db, taskId: TaskId(trusted: "nonexistent"),
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T14:00:00Z")
    }
    XCTAssertFalse(ok)
  }

  func testDeferWithReasonWritesLastDeferReason() throws {
    let store = try setupDeferralStore()
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(
          plannedDate: "2026-04-01", lastDeferReason: "low_energy"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertTrue(r.updated)
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT last_defer_reason FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["last_defer_reason"] as String?, "low_energy")
    }
  }

  func testDeferWithoutReasonLeavesLastDeferReasonUnchanged() throws {
    let store = try setupDeferralStore()
    _ = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(
          plannedDate: "2026-04-01", lastDeferReason: "blocked"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    _ = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-02"),
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T13:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT last_defer_reason FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["last_defer_reason"] as String?, "blocked")
    }
  }

  /// Stale-version stamp used by the LWW-rejection test cases below.
  private static let staleStamp = "1711712640000_0000_0000000000000001"
  private static let newerStamp = "1711712640000_0009_0000000000000009"

  func testDeferWithStaleVersionIsRejected() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET version = ?, planned_date = '2026-05-01', "
          + "defer_count = 4 WHERE id = 't1'",
        arguments: [Self.newerStamp])
    }
    let r = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01"),
        version: Self.staleStamp,
        now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    XCTAssertFalse(r.updated, "stale-version defer must report updated == false")
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT planned_date, defer_count, version FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["planned_date"] as String?, "2026-05-01")
      XCTAssertEqual(row?["defer_count"] as Int64?, 4)
      XCTAssertEqual(row?["version"] as String?, Self.newerStamp)
    }
  }

  func testResetWithStaleVersionIsRejected() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET version = ?, planned_date = '2026-05-01', "
          + "defer_count = 4, last_deferred_at = '2026-04-30T00:00:00Z', "
          + "last_defer_reason = 'blocked' WHERE id = 't1'",
        arguments: [Self.newerStamp])
    }
    let ok = try store.writer.write { db in
      try TaskDeferral.resetTaskDeferral(
        db, taskId: TaskId(trusted: "t1"),
        version: Self.staleStamp, now: "2026-03-27T14:00:00Z")
    }
    XCTAssertFalse(ok)
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT planned_date, defer_count, last_defer_reason, version "
          + "FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["planned_date"] as String?, "2026-05-01")
      XCTAssertEqual(row?["defer_count"] as Int64?, 4)
      XCTAssertEqual(row?["last_defer_reason"] as String?, "blocked")
      XCTAssertEqual(row?["version"] as String?, Self.newerStamp)
    }
  }

  func testRestoreWithStaleVersionIsRejected() throws {
    let store = try setupDeferralStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET version = ?, planned_date = '2026-05-01', "
          + "defer_count = 4 WHERE id = 't1'",
        arguments: [Self.newerStamp])
    }
    let snapshot = TaskDeferral.DeferralSnapshot()
    let ok = try store.writer.write { db in
      try TaskDeferral.restoreTaskDeferral(
        db, taskId: TaskId(trusted: "t1"), snapshot: snapshot,
        version: Self.staleStamp, now: "2026-03-27T15:00:00Z")
    }
    XCTAssertFalse(ok)
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT planned_date, defer_count, version FROM tasks WHERE id = 't1'")
      XCTAssertEqual(row?["planned_date"] as String?, "2026-05-01")
      XCTAssertEqual(row?["defer_count"] as Int64?, 4)
      XCTAssertEqual(row?["version"] as String?, Self.newerStamp)
    }
  }

  func testResetClearsLastDeferReason() throws {
    let store = try setupDeferralStore()
    _ = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: "t1"),
        patch: TaskDeferral.DeferralPatch(
          plannedDate: "2026-04-01", lastDeferReason: "needs_info"),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z",
        nextReminderVersion: reminderVersionSupplier())
    }
    _ = try store.writer.write { db in
      try TaskDeferral.resetTaskDeferral(
        db, taskId: TaskId(trusted: "t1"),
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T14:00:00Z")
    }
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT last_defer_reason FROM tasks WHERE id = 't1'")
      XCTAssertNil(row?["last_defer_reason"] as String?)
    }
  }
}
