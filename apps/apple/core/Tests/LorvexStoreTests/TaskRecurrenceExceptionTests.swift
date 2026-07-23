import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `repositories/task/recurrence/tests.rs`.
final class TaskRecurrenceExceptionTests: XCTestCase {

  private func tid(_ id: String) -> TaskId { TaskId(trusted: id) }

  private func seedList(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES ('list-1', 'Test List', '0000000000000_0000_a0a0a0a0a0a0a0a0', \
        '2026-03-20T00:00:00Z', '2026-03-20T00:00:00Z')
        """)
  }

  /// Seed a recurring task. The schema CHECK requires `due_date`,
  /// `recurrence_group_id`, and `canonical_occurrence_date` whenever
  /// `recurrence` is set, so all four are written together.
  private func seedRecurringTask(
    _ store: LorvexStore, id: String, recurrence: String,
    dueDate: String, canonical: String
  ) throws {
    try store.writer.write { db in
      try self.seedList(db)
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, \
          recurrence_group_id, canonical_occurrence_date, version, created_at, updated_at) \
          VALUES (?, 'Daily Review', 'open', 'list-1', ?, ?, 'group-1', ?, \
          '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-20T00:00:00Z', '2026-03-20T00:00:00Z')
          """,
        arguments: [id, dueDate, recurrence, canonical])
    }
  }

  private func seedNonRecurringTask(_ store: LorvexStore, id: String) throws {
    try store.writer.write { db in
      try self.seedList(db)
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, due_date, version, created_at, updated_at) \
          VALUES (?, 'One-off Task', 'open', 'list-1', '2026-03-25', \
          '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-25T00:00:00Z', '2026-03-25T00:00:00Z')
          """,
        arguments: [id])
    }
  }

  private func exceptionsBlob(_ store: LorvexStore, _ taskId: String) throws -> String? {
    try store.writer.read { db in
      try String.fetchOne(
        db,
        sql: """
          SELECT (SELECT NULLIF(json_group_array(exception_date), '[]') \
          FROM (SELECT exception_date FROM task_recurrence_exceptions WHERE task_id = tasks.id ORDER BY exception_date)) \
          FROM tasks WHERE id = ?
          """,
        arguments: [taskId])
    }
  }

  private func setupDaily(_ store: LorvexStore) throws {
    try seedRecurringTask(
      store, id: "task-r1", recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
      dueDate: "2026-03-20", canonical: "2026-03-20")
  }

  func testAddExceptionToRecurringTask() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    let json = try TaskRepo.Recurrence.addTaskRecurrenceException(
      store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
      version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    XCTAssertEqual(json, #"["2026-03-25"]"#)

    let (exc, ver): (String?, String) = try store.writer.read { db in
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT (SELECT NULLIF(json_group_array(exception_date), '[]') \
          FROM (SELECT exception_date FROM task_recurrence_exceptions WHERE task_id = tasks.id ORDER BY exception_date)), \
          version FROM tasks WHERE id = 'task-r1'
          """)!
      return (row[0], row[1])
    }
    XCTAssertEqual(exc, json)
    XCTAssertEqual(ver, "0000000000001_0000_0000000000000001")
  }

  func testAddExceptionSortsAndDeduplicates() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    _ = try TaskRepo.Recurrence.addTaskRecurrenceException(
      store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
      version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    _ = try TaskRepo.Recurrence.addTaskRecurrenceException(
      store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-22",
      version: "0000000000002_0000_0000000000000002", now: "2026-03-27T12:01:00Z")
    XCTAssertEqual(try exceptionsBlob(store, "task-r1"), #"["2026-03-22","2026-03-25"]"#)
  }

  func testAddDuplicateExceptionReturnsError() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    _ = try TaskRepo.Recurrence.addTaskRecurrenceException(
      store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
      version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.addTaskRecurrenceException(
        store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T12:01:00Z")
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("Exception already exists"))
    }
  }

  func testAddExceptionToNonRecurringReturnsError() throws {
    let store = try TestSupport.freshStore()
    try seedNonRecurringTask(store, id: "task-nr1")
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.addTaskRecurrenceException(
        store.writer, taskId: tid("task-nr1"), exceptionDate: "2026-03-25",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("not recurring"))
    }
  }

  func testAddExceptionBeforeAnchorDateReturnsError() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.addTaskRecurrenceException(
        store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-19",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("task canonical occurrence date"))
    }
  }

  func testAddExceptionForNonexistentTaskReturnsError() throws {
    let store = try TestSupport.freshStore()
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.addTaskRecurrenceException(
        store.writer, taskId: tid("nonexistent"), exceptionDate: "2026-03-25",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.notFound(entity, _) = error else { return XCTFail("\(error)") }
      XCTAssertEqual(entity, EntityName.task)
    }
  }

  func testAddExceptionInvalidDateFormatReturnsError() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.addTaskRecurrenceException(
        store.writer, taskId: tid("task-r1"), exceptionDate: "not-a-date",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("invalid date format"))
    }
  }

  func testAddExceptionNonOccurrenceReturnsError() throws {
    let store = try TestSupport.freshStore()
    try seedRecurringTask(
      store, id: "task-weekly", recurrence: #"{"FREQ":"WEEKLY","INTERVAL":1}"#,
      dueDate: "2026-03-20", canonical: "2026-03-20")
    // 2026-03-25 is a Wednesday, not a Friday occurrence.
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.addTaskRecurrenceException(
        store.writer, taskId: tid("task-weekly"), exceptionDate: "2026-03-25",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("not a valid occurrence of the recurrence pattern"))
    }
  }

  func testRemoveExceptionSucceeds() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    _ = try TaskRepo.Recurrence.addTaskRecurrenceException(
      store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
      version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    _ = try TaskRepo.Recurrence.addTaskRecurrenceException(
      store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-22",
      version: "0000000000002_0000_0000000000000002", now: "2026-03-27T12:01:00Z")
    let json = try TaskRepo.Recurrence.removeTaskRecurrenceException(
      store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
      version: "0000000000003_0000_0000000000000003", now: "2026-03-27T12:02:00Z")
    XCTAssertEqual(json, #"["2026-03-22"]"#)
  }

  func testRemoveLastExceptionSetsNull() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    _ = try TaskRepo.Recurrence.addTaskRecurrenceException(
      store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
      version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    let json = try TaskRepo.Recurrence.removeTaskRecurrenceException(
      store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
      version: "0000000000002_0000_0000000000000002", now: "2026-03-27T12:01:00Z")
    XCTAssertNil(json)
    XCTAssertNil(try exceptionsBlob(store, "task-r1"))
  }

  func testRemoveNonexistentExceptionReturnsError() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.removeTaskRecurrenceException(
        store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("not in the exceptions list"))
    }
  }

  func testRemoveFromNonexistentTaskReturnsError() throws {
    let store = try TestSupport.freshStore()
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.removeTaskRecurrenceException(
        store.writer, taskId: tid("nonexistent"), exceptionDate: "2026-03-25",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.notFound(entity, _) = error else { return XCTFail("\(error)") }
      XCTAssertEqual(entity, EntityName.task)
    }
  }

  func testEmptyVersionRejected() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    for version in ["", "  "] {
      XCTAssertThrowsError(
        try TaskRepo.Recurrence.addTaskRecurrenceException(
          store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
          version: version, now: "2026-03-28T00:00:00Z")
      ) { error in
        guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
        XCTAssertTrue(m.contains("version must not be empty"))
      }
    }
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.removeTaskRecurrenceException(
        store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
        version: "", now: "2026-03-28T00:00:00Z")
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("version must not be empty"))
    }
  }

  func testRemoveExceptionRejectsMalformedWhenUnused() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.removeTaskRecurrenceException(
        store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-21",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("not in the exceptions list"))
    }
  }

  func testAddExceptionWithStaleVersionReturnsStaleVersionError() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = 'task-r1'",
        arguments: ["9999913599999_0099_bee0000000000000"])
    }
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.addTaskRecurrenceException(
        store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
        version: "0000000000001_0001_10ca1de000000000", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.staleVersion(entity, id) = error else { return XCTFail("\(error)") }
      XCTAssertEqual(entity, EntityName.task)
      XCTAssertEqual(id, "task-r1")
    }
    let current = try store.writer.read { db in
      try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = 'task-r1'")
    }
    XCTAssertEqual(current, "9999913599999_0099_bee0000000000000")
  }

  func testRemoveExceptionWithStaleVersionReturnsStaleVersionError() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    try store.writer.write { db in
      try RecurrenceExceptionsRepo.replaceTaskExceptionsFromJSON(
        db, taskId: "task-r1", json: #"["2026-03-25"]"#)
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = 'task-r1'",
        arguments: ["9999913599999_0099_bee0000000000000"])
    }
    XCTAssertThrowsError(
      try TaskRepo.Recurrence.removeTaskRecurrenceException(
        store.writer, taskId: tid("task-r1"), exceptionDate: "2026-03-25",
        version: "0000000000001_0001_10ca1de000000000", now: "2026-03-27T12:00:00Z")
    ) { error in
      guard case let StoreError.staleVersion(entity, _) = error else { return XCTFail("\(error)") }
      XCTAssertEqual(entity, EntityName.task)
    }
  }

  // MARK: - Storage-boundary EXDATE validation (DB-2)

  /// The EXDATE JSON wire form is an unescaped string concat, so a stray quote /
  /// backslash / control char in a stored date would forge malformed JSON. The
  /// storage choke point must hard-reject any non-`YYYY-MM-DD` value before it
  /// reaches `task_recurrence_exceptions`.
  func testReplaceTaskExceptionsRejectsJSONUnsafeDateAtStorageBoundary() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    XCTAssertThrowsError(
      try store.writer.write { db in
        try RecurrenceExceptionsRepo.replaceTaskExceptions(
          db, taskId: "task-r1", dates: [#"2026-03-25","x"#])
      }
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("invalid date format"))
    }
    XCTAssertNil(try exceptionsBlob(store, "task-r1"))
  }

  /// A JSON array whose single element embeds quotes (`2026-03-25","x`) would,
  /// without a storage-boundary guard, round-trip back out as a forged
  /// two-element array. The `FromJSON` path must reject it before storage.
  func testReplaceTaskExceptionsFromJSONRejectsForgedArrayInjection() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    XCTAssertThrowsError(
      try store.writer.write { db in
        try RecurrenceExceptionsRepo.replaceTaskExceptionsFromJSON(
          db, taskId: "task-r1", json: #"["2026-03-25\",\"x"]"#)
      }
    ) { error in
      guard case let StoreError.validation(m) = error else { return XCTFail("\(error)") }
      XCTAssertTrue(m.contains("invalid date format"))
    }
    XCTAssertNil(try exceptionsBlob(store, "task-r1"))
  }

  /// Valid `YYYY-MM-DD` dates still write and re-emit byte-identically.
  func testReplaceTaskExceptionsValidDatesRoundTrip() throws {
    let store = try TestSupport.freshStore()
    try setupDaily(store)
    try store.writer.write { db in
      try RecurrenceExceptionsRepo.replaceTaskExceptions(
        db, taskId: "task-r1", dates: ["2026-03-25", "2026-03-22"])
    }
    XCTAssertEqual(try exceptionsBlob(store, "task-r1"), #"["2026-03-22","2026-03-25"]"#)
    let json = try store.writer.read { db in
      try RecurrenceExceptionsRepo.loadTaskExceptionsJSON(db, taskId: "task-r1")
    }
    XCTAssertEqual(json, #"["2026-03-22","2026-03-25"]"#)
  }
}
