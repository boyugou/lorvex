import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// The planned-time rules through the workflow write paths: a time belongs to
/// its planned day, leaves with the day, and survives only the changes that
/// keep the task on that day.
final class TaskPlannedTimeTests: XCTestCase {
  private final class MonotonicHlc: HlcStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt32 = 1
    func generate() -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      counter &+= 1
      return try! Hlc(
        physicalMs: 1_700_000_000_000, counter: counter, deviceSuffix: "b0b0b0b0b0b0b0b0")
    }
  }

  private struct Stored: Equatable {
    var date: String?
    var start: Int64?
    var end: Int64?
  }

  private let session = HlcSession(handle: MonotonicHlc())

  private func freshStore() throws -> LorvexStore { try WorkflowTestSupport.freshStore() }

  @discardableResult
  private func create(
    _ store: LorvexStore, date: String? = "2026-05-01", start: String? = nil,
    end: String? = nil
  ) throws -> CreateTaskResult {
    try store.writer.write { db in
      try TaskCreate.createTask(
        db, hlc: self.session,
        input: CreateTaskInput(
          task: TaskCreateInput(
            title: "Write the brief",
            plannedDate: date.map { .set($0) } ?? .unset,
            plannedStartTime: start.map { .set($0) } ?? .unset,
            plannedEndTime: end.map { .set($0) } ?? .unset)))
    }
  }

  private func update(_ store: LorvexStore, _ input: TaskUpdateInput) throws {
    _ = try TaskUpdate.updateTask(store.writer, hlc: session, input: input)
  }

  private func stored(_ store: LorvexStore, _ id: TaskId) throws -> Stored {
    try store.writer.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT planned_date, planned_start_minutes, planned_end_minutes FROM tasks WHERE id = ?",
          arguments: [id.rawValue]))
      return Stored(date: row[0], start: row[1], end: row[2])
    }
  }

  private func timedTask(_ store: LorvexStore) throws -> TaskId {
    try create(store, date: "2026-05-01", start: "09:00", end: "10:30").taskId
  }

  private func assertValidation<T>(
    _ body: @autoclosure () throws -> T, containing needle: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try body(), file: file, line: line) { error in
      guard case StoreError.validation(let message) = error else {
        return XCTFail("expected a validation error, got \(error)", file: file, line: line)
      }
      XCTAssertTrue(message.contains(needle), message, file: file, line: line)
    }
  }

  // MARK: - Create

  func testCreateStoresTheTimeOnItsDayAndReturnsIt() throws {
    let store = try freshStore()
    let result = try create(store, date: "2026-05-01", start: "09:00", end: "10:30")
    XCTAssertEqual(try stored(store, result.taskId), Stored(date: "2026-05-01", start: 540, end: 630))
    guard case .object(let task) = result.task else { return XCTFail("task JSON") }
    XCTAssertEqual(task["planned_start_time"], .string("09:00"))
    XCTAssertEqual(task["planned_end_time"], .string("10:30"))
  }

  func testCreateAcceptsAnEndOfMidnight() throws {
    let store = try freshStore()
    let result = try create(store, date: "2026-05-01", start: "23:00", end: "24:00")
    XCTAssertEqual(try stored(store, result.taskId), Stored(date: "2026-05-01", start: 1380, end: 1440))
  }

  func testCreateRejectsATimeWithoutADate() throws {
    let store = try freshStore()
    assertValidation(
      try create(store, date: nil, start: "09:00", end: "10:00"), containing: "planned date")
  }

  func testCreateRejectsAnUnpairedOrBackwardTime() throws {
    let store = try freshStore()
    assertValidation(try create(store, start: "09:00"), containing: "go together")
    assertValidation(try create(store, start: "10:00", end: "09:00"), containing: "after")
    assertValidation(try create(store, start: "9am", end: "10:00"), containing: "HH:MM")
  }

  // MARK: - Update

  func testUpdateSetsATimeOnTheTasksExistingDay() throws {
    let store = try freshStore()
    let id = try create(store).taskId
    try update(
      store, TaskUpdateInput(id: id.rawValue, plannedStartTime: .set("14:00"), plannedEndTime: .set("14:45")))
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-01", start: 840, end: 885))
  }

  func testUpdateRejectsATimeOnAnUndatedTask() throws {
    let store = try freshStore()
    let id = try create(store, date: nil).taskId
    assertValidation(
      try update(
        store,
        TaskUpdateInput(id: id.rawValue, plannedStartTime: .set("14:00"), plannedEndTime: .set("15:00"))),
      containing: "planned date")
  }

  func testMovingToAnotherDayClearsTheTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(store, TaskUpdateInput(id: id.rawValue, plannedDate: .set("2026-05-02")))
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-02", start: nil, end: nil))
  }

  func testSettingTheSameDayKeepsTheTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(store, TaskUpdateInput(id: id.rawValue, plannedDate: .set("2026-05-01")))
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-01", start: 540, end: 630))
  }

  func testMovingTheDayWithANewTimeKeepsTheNewTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(
      store,
      TaskUpdateInput(
        id: id.rawValue, plannedDate: .set("2026-05-03"), plannedStartTime: .set("16:00"),
        plannedEndTime: .set("17:00")))
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-03", start: 960, end: 1020))
  }

  func testClearingTheDayClearsTheTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(store, TaskUpdateInput(id: id.rawValue, plannedDate: .clear))
    XCTAssertEqual(try stored(store, id), Stored(date: nil, start: nil, end: nil))
  }

  func testClearingTheTimeKeepsTheDay() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(
      store, TaskUpdateInput(id: id.rawValue, plannedStartTime: .clear, plannedEndTime: .clear))
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-01", start: nil, end: nil))
  }

  func testClearingHalfTheTimeIsRejected() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    assertValidation(
      try update(store, TaskUpdateInput(id: id.rawValue, plannedStartTime: .clear)),
      containing: "go together")
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-01", start: 540, end: 630))
  }

  // MARK: - Status changes

  func testCompletingKeepsTheTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(store, TaskUpdateInput(id: id.rawValue, status: .set(StatusName.completed)))
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-01", start: 540, end: 630))
  }

  func testUncompletingKeepsTheDayAndTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(store, TaskUpdateInput(id: id.rawValue, status: .set(StatusName.completed)))
    try update(store, TaskUpdateInput(id: id.rawValue, status: .set(StatusName.open)))
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-01", start: 540, end: 630))
  }

  func testReopeningACancelledTaskClearsItsDayAndTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(store, TaskUpdateInput(id: id.rawValue, status: .set(StatusName.cancelled)))
    try update(store, TaskUpdateInput(id: id.rawValue, status: .set(StatusName.open)))
    XCTAssertEqual(try stored(store, id), Stored(date: nil, start: nil, end: nil))
  }

  func testReopeningASomedayTaskClearsItsDayAndTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(store, TaskUpdateInput(id: id.rawValue, status: .set(StatusName.someday)))
    try update(store, TaskUpdateInput(id: id.rawValue, status: .set(StatusName.open)))
    XCTAssertEqual(try stored(store, id), Stored(date: nil, start: nil, end: nil))
  }

  func testPausingKeepsTheDayAndTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    try update(store, TaskUpdateInput(id: id.rawValue, status: .set(StatusName.inProgress)))
    try update(store, TaskUpdateInput(id: id.rawValue, status: .set(StatusName.open)))
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-01", start: 540, end: 630))
  }

  func testDeferringClearsTheTime() throws {
    let store = try freshStore()
    let id = try timedTask(store)
    let result = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: id, patch: TaskDeferral.DeferralPatch(plannedDate: "2026-05-02"),
        version: "1700000000001_0099_b0b0b0b0b0b0b0b0", now: "2026-05-01T12:00:00Z",
        nextReminderVersion: { "1700000000001_0100_b0b0b0b0b0b0b0b0" })
    }
    XCTAssertTrue(result.updated)
    XCTAssertEqual(try stored(store, id), Stored(date: "2026-05-02", start: nil, end: nil))
  }
}
