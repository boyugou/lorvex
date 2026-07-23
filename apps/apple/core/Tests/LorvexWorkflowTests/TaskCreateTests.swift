import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Targeted XCTest coverage for `TaskCreate.createTask` and its preparation
/// chain. The Rust `task_create/` subtree carries no inline tests; this
/// suite pins the parity-sensitive surfaces the Rust implementation implies:
///
/// - title sanitization + visually-empty rejection
/// - status seeding (`open` default, `someday` accepted, other rejected)
/// - tag normalization (trim + lowercase + dedupe)
/// - cap enforcement (tags / depends_on / reminders)
/// - depends_on cycle + existence validation
/// - flexible date parsing (`today`, `tomorrow`, `YYYY-MM-DD`, RFC 3339)
/// - priority 1..=3
/// - recurrence canonicalization + group / canonical-occurrence stamping
/// - summary string format
/// - `completed: true` routing through `LifecycleTransitions`
/// - intake advice (missing_estimate / missing_planned_date)
/// - list-resolution defaults via `default_list_id` preference
final class TaskCreateTests: XCTestCase {
  // MARK: - test helpers

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
    // The schema seed provides the `inbox` list; ensure it's present
    // regardless of seed-file drift via INSERT OR IGNORE.
    try s.writer.write { db in
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('inbox', 'Inbox', '0000000000000_0000_0000000000000aaa', "
          + "        '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')")
    }
    return s
  }

  private func runCreate(
    _ store: LorvexStore, _ input: TaskCreateInput,
    id: String? = nil, includeAdvice: Bool = false
  ) throws -> CreateTaskResult {
    let session = makeSession()
    return try store.writer.write { db in
      try TaskCreate.createTask(
        db, hlc: session,
        input: CreateTaskInput(id: id, task: input, includeAdvice: includeAdvice))
    }
  }

  // MARK: - title

  func testRejectsEmptyTitle() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try runCreate(store, TaskCreateInput(title: "   "))
    ) { e in
      guard case ValidationError.empty(let field) = e else {
        XCTFail("expected empty-title validation, got \(e)"); return
      }
      XCTAssertEqual(field, "title")
    }
  }

  func testCreatesWithExplicitListAndSimpleTitle() throws {
    let store = try freshStore()
    let result = try runCreate(
      store, TaskCreateInput(title: "Plan trip", listId: .set("inbox")))
    XCTAssertEqual(result.summary, "Created task 'Plan trip' in Inbox")
    XCTAssertEqual(result.syncEffects.taskUpsertIds.count, 1)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db, sql: "SELECT title, status, list_id FROM tasks WHERE id = ?",
        arguments: [result.taskId.asString])
    }
    XCTAssertEqual(row?["title"] as String?, "Plan trip")
    XCTAssertEqual(row?["status"] as String?, "open")
    XCTAssertEqual(row?["list_id"] as String?, "inbox")
  }

  // MARK: - status seeding

  func testStatusDefaultsToOpenAndAcceptsSomeday() throws {
    let store = try freshStore()
    let r1 = try runCreate(store, TaskCreateInput(title: "Default", listId: .set("inbox")))
    let s1: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?",
        arguments: [r1.taskId.asString])
    }
    XCTAssertEqual(s1, "open")
    let r2 = try runCreate(
      store,
      TaskCreateInput(
        title: "Someday item", listId: .set("inbox"), status: .set("someday")))
    let s2: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?",
        arguments: [r2.taskId.asString])
    }
    XCTAssertEqual(s2, "someday")
  }

  func testRejectsUnknownStatus() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try runCreate(
        store,
        TaskCreateInput(title: "T", listId: .set("inbox"), status: .set("done")))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(
        m,
        "invalid initial status for task create: 'done' "
          + "(only 'open' or 'someday' accepted)")
    }
  }

  // MARK: - priority + caps

  func testRejectsOutOfRangePriority() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try runCreate(
        store,
        TaskCreateInput(title: "T", listId: .set("inbox"), priority: .set(4)))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(m, "Invalid priority '4'. Expected one of: 1, 2, 3")
    }
  }

  func testRejectsTooManyTags() throws {
    let store = try freshStore()
    let manyTags = (0..<(ValidationLimits.maxTaskTags + 1)).map { "tag\($0)" }
    XCTAssertThrowsError(
      try runCreate(
        store,
        TaskCreateInput(title: "T", listId: .set("inbox"), tags: manyTags))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(
        m,
        "tags supports at most \(ValidationLimits.maxTaskTags) item(s), "
          + "got \(ValidationLimits.maxTaskTags + 1)")
    }
  }

  // MARK: - tag normalization

  func testTagsTrimLowercaseAndDedupe() throws {
    let store = try freshStore()
    let result = try runCreate(
      store,
      TaskCreateInput(
        title: "T", listId: .set("inbox"),
        tags: [" Foo ", "bar", "FOO", "Bar"]))
    XCTAssertEqual(result.syncEffects.taskTagEdgeUpsertIds.count, 2)
    let tags: [String] = try store.writer.read { db in
      try String.fetchAll(
        db,
        sql:
          "SELECT t.display_name FROM tags t "
          + "JOIN task_tags tt ON tt.tag_id = t.id "
          + "WHERE tt.task_id = ? ORDER BY t.display_name",
        arguments: [result.taskId.asString])
    }
    XCTAssertEqual(tags, ["bar", "foo"])
  }

  // MARK: - depends_on

  func testRejectsDependsOnSelfReference() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try runCreate(
        store,
        TaskCreateInput(
          title: "T", listId: .set("inbox"), dependsOn: ["00000000-0000-0000-0000-000000000001"]),
        id: "00000000-0000-0000-0000-000000000001")
    ) { e in
      // Self-reference triggers the cycle validator's self-reference branch.
      guard case StoreError.validation = e else {
        XCTFail("expected validation, got \(e)"); return
      }
    }
  }

  func testRejectsNonExistentDependency() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try runCreate(
        store,
        TaskCreateInput(
          title: "T", listId: .set("inbox"),
          dependsOn: ["00000000-0000-0000-0000-deadbeef0001"]))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(
        m,
        "depends_on references non-existent task "
          + "'00000000-0000-0000-0000-deadbeef0001'")
    }
  }

  // MARK: - flexible dates

  func testDueDateNormalizesToday() throws {
    let store = try freshStore()
    // Pin the timezone preference so today is deterministic relative to UTC.
    try store.writer.write { db in
      try db.execute(
        sql: "INSERT INTO preferences (key, value, version, updated_at) VALUES "
          + "('timezone', '\"UTC\"', '0000000000000_0000_0000000000000aaa', "
          + "'2026-04-01T00:00:00Z')")
    }
    let result = try runCreate(
      store,
      TaskCreateInput(title: "T", listId: .set("inbox"), dueDate: .set("today")))
    let due: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT due_date FROM tasks WHERE id = ?",
        arguments: [result.taskId.asString])
    }
    let expected = try store.writer.read { db in
      try WorkflowTimezone.todayYmdForConn(db)
    }
    XCTAssertEqual(due, expected)
  }

  func testDueDateRejectsGarbage() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try runCreate(
        store,
        TaskCreateInput(title: "T", listId: .set("inbox"), dueDate: .set("not-a-date")))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertTrue(m.hasPrefix("Invalid due_date 'not-a-date'."))
    }
  }

  private func pinUtcTimezone(_ store: LorvexStore) throws {
    try store.writer.write { db in
      try db.execute(
        sql: "INSERT OR REPLACE INTO preferences (key, value, version, updated_at) VALUES "
          + "('timezone', '\"UTC\"', '0000000000000_0000_0000000000000aaa', "
          + "'2026-04-01T00:00:00Z')")
    }
  }

  func testRfc3339DueDateRejectsRolledOverCalendarDays() throws {
    // ISO8601DateFormatter silently normalizes an out-of-range calendar day, so
    // the RFC 3339 due-date path must reject the same days the bare-YYYY-MM-DD
    // path rejects (2026-02-30 → 2026-03-02, 2023-02-29 → 2023-03-01, …).
    let store = try freshStore()
    try pinUtcTimezone(store)
    for bad in [
      "2026-02-30T09:00:00Z",
      "2023-02-29T09:00:00Z",
      "2026-13-01T09:00:00Z",
      "2026-00-10T09:00:00Z",
    ] {
      XCTAssertThrowsError(
        try store.writer.read { db in
          try TaskCreateDateParse.normalizeDueDateInputForConn(db, value: bad)
        }, "expected \(bad) to be rejected"
      ) { e in
        guard case StoreError.validation = e else {
          XCTFail("expected validation for \(bad), got \(e)"); return
        }
      }
    }
  }

  func testRfc3339DueDateAcceptsValidCalendarDays() throws {
    let store = try freshStore()
    try pinUtcTimezone(store)
    let cases: [(String, String)] = [
      ("2024-02-29T09:00:00Z", "2024-02-29"),  // leap day in a leap year
      ("2026-05-01T12:00:00Z", "2026-05-01"),
    ]
    for (input, expected) in cases {
      let out = try store.writer.read { db in
        try TaskCreateDateParse.normalizeDueDateInputForConn(db, value: input)
      }
      XCTAssertEqual(out, expected, "for \(input)")
    }
  }

  // MARK: - recurrence

  func testRecurrenceStampsGroupAndCanonicalOccurrence() throws {
    let store = try freshStore()
    let rule = #"{"FREQ":"DAILY","INTERVAL":1}"#
    let result = try runCreate(
      store,
      TaskCreateInput(
        title: "Daily", listId: .set("inbox"),
        dueDate: .set("2026-05-01"),
        recurrenceJson: .set(rule)))
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT recurrence, recurrence_group_id, "
          + "canonical_occurrence_date, due_date FROM tasks WHERE id = ?",
        arguments: [result.taskId.asString])
    }
    XCTAssertNotNil(row?["recurrence"] as String?)
    XCTAssertNotNil(row?["recurrence_group_id"] as String?)
    XCTAssertEqual(row?["canonical_occurrence_date"] as String?, "2026-05-01")
    XCTAssertEqual(row?["due_date"] as String?, "2026-05-01")
  }

  // MARK: - list resolution

  func testDefaultListPreferenceIsUsedWhenNoExplicitListId() throws {
    let store = try freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT OR REPLACE INTO preferences (key, value, version, updated_at) VALUES "
          + "(?, ?, '0000000000000_0000_0000000000000bbb', '2026-04-01T00:00:00Z')",
        arguments: [PreferenceKeys.prefDefaultListId, "\"inbox\""])
    }
    let result = try runCreate(store, TaskCreateInput(title: "Defaulted"))
    let listId: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT list_id FROM tasks WHERE id = ?",
        arguments: [result.taskId.asString])
    }
    XCTAssertEqual(listId, "inbox")
  }

  func testRejectsMissingExplicitList() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try runCreate(
        store,
        TaskCreateInput(title: "T", listId: .set("does-not-exist")))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(m, "list 'does-not-exist' does not exist")
    }
  }

  func testCreateWithoutListAndWithoutDefaultFallsBackToInbox() throws {
    let store = try freshStore()
    // The schema seeds a `default_list_id` preference; remove it so the resolver
    // hits the no-default branch, which must heal to inbox rather than throw.
    try store.writer.write { db in
      try db.execute(
        sql: "DELETE FROM preferences WHERE key = ?",
        arguments: [PreferenceKeys.prefDefaultListId])
    }
    let result = try runCreate(store, TaskCreateInput(title: "T"))
    let listId: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT list_id FROM tasks WHERE id = ?",
        arguments: [result.taskId.asString])
    }
    XCTAssertEqual(listId, "inbox")
  }

  func testCreateWithDanglingDefaultFallsBackToInbox() throws {
    let store = try freshStore()
    // A default_list_id pointing at a list that does not exist (its list was
    // deleted, or a synced default references a list absent locally) must not
    // fail implicit creation — it heals to inbox.
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT OR REPLACE INTO preferences (key, value, version, updated_at) VALUES "
          + "(?, ?, '0000000000000_0000_0000000000000ccc', '2026-04-01T00:00:00Z')",
        arguments: [PreferenceKeys.prefDefaultListId, "\"gone-list\""])
    }
    let result = try runCreate(store, TaskCreateInput(title: "T"))
    let listId: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT list_id FROM tasks WHERE id = ?",
        arguments: [result.taskId.asString])
    }
    XCTAssertEqual(listId, "inbox")
  }

  // MARK: - completed routing

  func testCompletedTrueRoutesThroughLifecycleAndYieldsCompletedStatus() throws {
    let store = try freshStore()
    let result = try runCreate(
      store,
      TaskCreateInput(title: "Pre-done", listId: .set("inbox"), completed: true))
    let status: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?",
        arguments: [result.taskId.asString])
    }
    XCTAssertEqual(status, "completed")
    XCTAssertTrue(result.summary.hasSuffix("(completed)"))
  }

  // MARK: - summary string

  func testSummaryIncludesListAndDue() throws {
    let store = try freshStore()
    let result = try runCreate(
      store,
      TaskCreateInput(
        title: "Pay rent", listId: .set("inbox"),
        dueDate: .set("2026-06-01")))
    XCTAssertEqual(result.summary, "Created task 'Pay rent' in Inbox, due 2026-06-01")
  }

  // MARK: - intake advice

  func testIntakeAdviceEmitsMissingEstimateAndPlannedDate() throws {
    let store = try freshStore()
    let result = try runCreate(
      store,
      TaskCreateInput(title: "No metadata", listId: .set("inbox")),
      includeAdvice: true)
    let codes = result.advice.compactMap { adv -> String? in
      if case .object(let f) = adv, case .string(let c) = f["code"] ?? .null {
        return c
      }
      return nil
    }
    XCTAssertTrue(codes.contains("missing_estimate"))
    XCTAssertTrue(codes.contains("missing_planned_date"))
  }

  func testIntakeAdviceSkippedWhenNotRequested() throws {
    let store = try freshStore()
    let result = try runCreate(
      store, TaskCreateInput(title: "Q", listId: .set("inbox")),
      includeAdvice: false)
    XCTAssertTrue(result.advice.isEmpty)
  }

  // MARK: - rich response payload

  func testPayloadShapeMatchesEnrichedTaskAndAuxArrays() throws {
    let store = try freshStore()
    let result = try runCreate(
      store, TaskCreateInput(title: "Plain", listId: .set("inbox")))
    guard case .object(let p) = result.payload else {
      XCTFail("payload must be an object"); return
    }
    XCTAssertNotNil(p["task"])
    XCTAssertEqual(p["next_occurrence"], .null)
    if case .array(let a) = p["newly_unblocked"] ?? .null {
      XCTAssertTrue(a.isEmpty)
    } else {
      XCTFail("newly_unblocked must be an array")
    }
    if case .array(let a) = p["advice"] ?? .null {
      XCTAssertTrue(a.isEmpty)
    } else {
      XCTFail("advice must be an array")
    }
  }

  // MARK: - reminders

  func testRemindersInsertWithCanonicalizedTimestamp() throws {
    let store = try freshStore()
    let result = try runCreate(
      store,
      TaskCreateInput(
        title: "T", listId: .set("inbox"),
        reminders: ["2026-12-01T09:00:00Z"]))
    XCTAssertEqual(result.syncEffects.reminderUpsertIds.count, 1)
    let timestamps: [String] = try store.writer.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT reminder_at FROM task_reminders WHERE task_id = ?",
        arguments: [result.taskId.asString])
    }
    // Canonicalization renders with millisecond precision.
    XCTAssertEqual(timestamps, ["2026-12-01T09:00:00.000Z"])
  }

  func testRejectsInvalidReminderTimestamp() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try runCreate(
        store,
        TaskCreateInput(
          title: "T", listId: .set("inbox"),
          reminders: ["not-a-timestamp"]))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertTrue(m.contains("Invalid reminder timestamp"))
    }
  }

  // MARK: - record_raw_input preference

  func testRawInputDroppedWhenPreferenceFalse() throws {
    let store = try freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: "INSERT INTO preferences (key, value, version, updated_at) VALUES "
          + "(?, 'false', '0000000000000_0000_0000000000000ccc', '2026-04-01T00:00:00Z')",
        arguments: [PreferenceKeys.prefRecordRawInput])
    }
    let result = try runCreate(
      store,
      TaskCreateInput(
        title: "T", listId: .set("inbox"),
        rawInput: .set("typed raw")))
    let storedRaw: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT raw_input FROM tasks WHERE id = ?",
        arguments: [result.taskId.asString])
    }
    XCTAssertNil(storedRaw)
  }
}
