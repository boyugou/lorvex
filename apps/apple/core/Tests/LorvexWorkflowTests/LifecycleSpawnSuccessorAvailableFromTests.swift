import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Recurrence-successor matrix for the `available_from` (defer-until) column.
///
/// The single invariant under test: on spawn, the successor preserves the
/// day-delta between the parent's `canonical_occurrence_date` and its
/// `available_from` (`successor.available_from = nextDueDate +
/// daysBetween(parent.canonical, parent.available_from)`). Because the
/// successor's `canonical_occurrence_date` is exactly `nextDueDate`, the
/// invariant is equivalent to "the (canonical → available_from) day-delta is
/// identical on parent and successor" — a variant-independent assertion, so one
/// helper exercises every cadence shape (daily, weekly BYDAY, interval > 1,
/// monthly BYMONTHDAY, month-end, BYDAY-ordinal, BYSETPOS, yearly, leap,
/// completion-anchored) without pinning each engine-computed next date.
final class LifecycleSpawnSuccessorAvailableFromTests: XCTestCase {
  private func tid(_ s: String) -> TaskId { TaskId(trusted: s) }

  private struct SeedTask {
    var id: String
    var title: String = "Recurring"
    var status: String = "open"
    var dueDate: String? = nil
    var plannedDate: String? = nil
    var availableFrom: String? = nil
    var canonicalOccurrenceDate: String? = nil
    var recurrence: String? = nil
    var recurrenceGroupId: String? = nil
    var recurrenceExceptions: [String] = []
    var version: String = "0000000000000_0000_0000000000000000"
    var createdAt: String = "2026-01-01T00:00:00Z"
  }

  private func seed(_ store: LorvexStore, _ t: SeedTask) throws {
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, planned_date, "
          + "available_from, canonical_occurrence_date, recurrence, recurrence_group_id, "
          + "version, created_at, updated_at) "
          + "VALUES (?1, ?2, ?3, 'inbox', ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11)",
        arguments: [
          t.id, t.title, t.status, t.dueDate, t.plannedDate, t.availableFrom,
          t.canonicalOccurrenceDate, t.recurrence, t.recurrenceGroupId, t.version, t.createdAt,
        ])
      for date in t.recurrenceExceptions {
        try db.execute(
          sql: "INSERT INTO task_recurrence_exceptions (task_id, exception_date) VALUES (?1, ?2)",
          arguments: [t.id, date])
      }
    }
  }

  private struct SuccessorRow {
    var due: String
    var canonical: String
    var availableFrom: String?
    var plannedDate: String?
  }

  /// Complete `taskId` and return the spawned successor row (or nil when no
  /// successor was spawned).
  private func completeAndReadSuccessor(
    _ store: LorvexStore, taskId: String, now: String
  ) throws -> SuccessorRow? {
    let result = try store.writer.write { db in
      try LifecycleTransitions.applyCompletionTransition(
        db, taskId: tid(taskId), now: now,
        reminderVersion: "0000000000000_0000_50cc000000000001")
    }
    guard let succId = result.spawnedSuccessorId else { return nil }
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT due_date, canonical_occurrence_date, available_from, planned_date "
          + "FROM tasks WHERE id = ?1",
        arguments: [succId])
    }
    let r = try XCTUnwrap(row)
    return SuccessorRow(
      due: r[0], canonical: r[1], availableFrom: r[2], plannedDate: r[3])
  }

  private func dayDelta(from a: String, to b: String) throws -> Int {
    let ya = try XCTUnwrap(ymd(a))
    let yb = try XCTUnwrap(ymd(b))
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let da = try XCTUnwrap(cal.date(from: ya))
    let db = try XCTUnwrap(cal.date(from: yb))
    return try XCTUnwrap(cal.dateComponents([.day], from: da, to: db).day)
  }

  private func ymd(_ s: String) -> DateComponents? {
    let parts = s.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
    else { return nil }
    var c = DateComponents()
    c.year = y
    c.month = m
    c.day = d
    return c
  }

  /// Core assertion for a spawned variant: the (canonical → available_from)
  /// day-delta is identical on parent and successor.
  private func assertDeltaPreserved(
    recurrence: String,
    canonical: String,
    due: String,
    availableFrom: String,
    now: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let store = try WorkflowTestSupport.freshStore()
    try seed(
      store,
      SeedTask(
        id: "rec-1", dueDate: due, availableFrom: availableFrom,
        canonicalOccurrenceDate: canonical, recurrence: recurrence,
        recurrenceGroupId: "grp-1"))
    let succ = try XCTUnwrap(
      try completeAndReadSuccessor(store, taskId: "rec-1", now: now), file: file, line: line)
    let parentDelta = try dayDelta(from: canonical, to: availableFrom)
    let succAvailableFrom = try XCTUnwrap(succ.availableFrom, file: file, line: line)
    let succDelta = try dayDelta(from: succ.canonical, to: succAvailableFrom)
    XCTAssertEqual(
      succDelta, parentDelta,
      "successor canonical→available_from delta must equal parent's", file: file, line: line)
    // The successor's canonical is its due date, so available_from is also
    // exactly `due - (-delta)` relative to the successor due date.
    XCTAssertEqual(
      try dayDelta(from: succ.due, to: succAvailableFrom), parentDelta, file: file, line: line)
  }

  // MARK: - variant matrix (delta preserved)

  func testDailyPreservesLead() throws {
    try assertDeltaPreserved(
      recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
      canonical: "2026-03-15", due: "2026-03-15", availableFrom: "2026-03-14",
      now: "2026-03-15T10:00:00Z")
  }

  func testWeeklyBydayLeadZero() throws {
    // L = 0: available_from == canonical → successor available_from == successor due.
    try assertDeltaPreserved(
      recurrence: #"{"BYDAY":["MO"],"FREQ":"WEEKLY","INTERVAL":1}"#,
      canonical: "2026-03-16", due: "2026-03-16", availableFrom: "2026-03-16",
      now: "2026-03-16T10:00:00Z")
  }

  func testWeeklyBydayLeadTwo() throws {
    try assertDeltaPreserved(
      recurrence: #"{"BYDAY":["MO"],"FREQ":"WEEKLY","INTERVAL":1}"#,
      canonical: "2026-03-16", due: "2026-03-16", availableFrom: "2026-03-14",
      now: "2026-03-16T10:00:00Z")
  }

  func testWeeklyIntervalGreaterThanOne() throws {
    try assertDeltaPreserved(
      recurrence: #"{"FREQ":"WEEKLY","INTERVAL":2}"#,
      canonical: "2026-03-16", due: "2026-03-16", availableFrom: "2026-03-13",
      now: "2026-03-16T10:00:00Z")
  }

  func testMonthlyBymonthday() throws {
    try assertDeltaPreserved(
      recurrence: #"{"FREQ":"MONTHLY","INTERVAL":1}"#,
      canonical: "2026-03-15", due: "2026-03-15", availableFrom: "2026-03-10",
      now: "2026-03-25T10:00:00Z")
  }

  func testMonthlyLastDay() throws {
    // Month-end cadence: canonical Jan-31 → successor Feb-28; the lead survives
    // even though the successor month is shorter.
    try assertDeltaPreserved(
      recurrence: #"{"FREQ":"MONTHLY","INTERVAL":1}"#,
      canonical: "2026-01-31", due: "2026-01-31", availableFrom: "2026-01-30",
      now: "2026-01-31T10:00:00Z")
  }

  func testBydayOrdinal() throws {
    // 3rd Monday of the month.
    try assertDeltaPreserved(
      recurrence: #"{"BYDAY":["+3MO"],"FREQ":"MONTHLY","INTERVAL":1}"#,
      canonical: "2026-03-16", due: "2026-03-16", availableFrom: "2026-03-13",
      now: "2026-03-16T10:00:00Z")
  }

  func testBysetpos() throws {
    // Last weekday of the month via BYSETPOS.
    try assertDeltaPreserved(
      recurrence:
        #"{"BYDAY":["MO","TU","WE","TH","FR"],"BYSETPOS":[-1],"FREQ":"MONTHLY","INTERVAL":1}"#,
      canonical: "2026-03-31", due: "2026-03-31", availableFrom: "2026-03-27",
      now: "2026-03-31T10:00:00Z")
  }

  func testYearly() throws {
    try assertDeltaPreserved(
      recurrence: #"{"FREQ":"YEARLY","INTERVAL":1}"#,
      canonical: "2026-03-15", due: "2026-03-15", availableFrom: "2026-03-08",
      now: "2026-03-15T10:00:00Z")
  }

  func testYearlyLeapDay() throws {
    // Feb-29 cadence resolves to the next Feb-29; the lead survives the clamp.
    try assertDeltaPreserved(
      recurrence: #"{"FREQ":"YEARLY","INTERVAL":1}"#,
      canonical: "2024-02-29", due: "2024-02-29", availableFrom: "2024-02-25",
      now: "2024-02-29T10:00:00Z")
  }

  func testCompletionAnchoredPreservesLead() throws {
    // Completion-anchored: successor due is completion + INTERVAL; the lead is
    // still measured from the (canonical) anchor and re-applied to the new due.
    try assertDeltaPreserved(
      recurrence: #"{"ANCHOR":"completion","FREQ":"WEEKLY","INTERVAL":1}"#,
      canonical: "2026-03-15", due: "2026-03-15", availableFrom: "2026-03-13",
      now: "2026-03-25T10:00:00Z")
  }

  func testExdateSkipStillPreservesLead() throws {
    // The immediate next monthly occurrence (Apr-15) is an EXDATE, so the walk
    // lands on May-15; the lead is preserved relative to that later successor.
    let store = try WorkflowTestSupport.freshStore()
    try seed(
      store,
      SeedTask(
        id: "rec-ex", dueDate: "2026-03-15", availableFrom: "2026-03-10",
        canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"FREQ":"MONTHLY","INTERVAL":1}"#,
        recurrenceGroupId: "grp-ex", recurrenceExceptions: ["2026-04-15"]))
    let succ = try XCTUnwrap(
      try completeAndReadSuccessor(store, taskId: "rec-ex", now: "2026-03-25T10:00:00Z"))
    XCTAssertEqual(succ.canonical, "2026-05-15", "EXDATE Apr-15 skipped to May-15")
    XCTAssertEqual(succ.availableFrom, "2026-05-10", "lead of 5 days preserved onto skipped date")
  }

  // MARK: - nil / independence cases

  func testNilAvailableFromYieldsNilSuccessor() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seed(
      store,
      SeedTask(
        id: "rec-nil", dueDate: "2026-03-15", availableFrom: nil,
        canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"FREQ":"MONTHLY","INTERVAL":1}"#, recurrenceGroupId: "grp-nil"))
    let succ = try XCTUnwrap(
      try completeAndReadSuccessor(store, taskId: "rec-nil", now: "2026-03-25T10:00:00Z"))
    XCTAssertNil(succ.availableFrom, "no parent available_from → successor never hides")
  }

  func testAvailableFromIndependentOfPlannedDate() throws {
    // No planned_date, only due + available_from: the successor's available_from
    // is still computed (independent of planned_date), and planned stays nil.
    let store = try WorkflowTestSupport.freshStore()
    try seed(
      store,
      SeedTask(
        id: "rec-dueonly", dueDate: "2026-03-15", plannedDate: nil,
        availableFrom: "2026-03-12", canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"FREQ":"MONTHLY","INTERVAL":1}"#, recurrenceGroupId: "grp-do"))
    let succ = try XCTUnwrap(
      try completeAndReadSuccessor(store, taskId: "rec-dueonly", now: "2026-03-25T10:00:00Z"))
    XCTAssertNil(succ.plannedDate)
    XCTAssertEqual(succ.availableFrom, "2026-04-12")
  }

  func testPerOccurrenceOverridePropagatesCurrentLead() throws {
    // Propagate-last-lead: the delta is re-derived from THIS occurrence every
    // spawn. A parent whose lead was overridden to 1 day (not the original 5)
    // spawns a successor carrying the 1-day lead, not a series-fixed value.
    let store = try WorkflowTestSupport.freshStore()
    try seed(
      store,
      SeedTask(
        id: "rec-override", dueDate: "2026-03-15", availableFrom: "2026-03-14",
        canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"FREQ":"MONTHLY","INTERVAL":1}"#, recurrenceGroupId: "grp-ov"))
    let succ = try XCTUnwrap(
      try completeAndReadSuccessor(store, taskId: "rec-override", now: "2026-03-25T10:00:00Z"))
    XCTAssertEqual(succ.canonical, "2026-04-15")
    XCTAssertEqual(succ.availableFrom, "2026-04-14", "1-day override lead propagates, not 5")
  }

  func testCountExhaustedDoesNotSpawnDespiteAvailableFrom() throws {
    // COUNT=1 is the last occurrence: no successor, and available_from does not
    // force a spawn.
    let store = try WorkflowTestSupport.freshStore()
    try seed(
      store,
      SeedTask(
        id: "rec-count", dueDate: "2026-03-15", availableFrom: "2026-03-10",
        canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"COUNT":1,"FREQ":"MONTHLY","INTERVAL":1}"#, recurrenceGroupId: "grp-c"))
    let succ = try completeAndReadSuccessor(store, taskId: "rec-count", now: "2026-03-25T10:00:00Z")
    XCTAssertNil(succ, "COUNT exhausted → no successor")
  }

  func testUntilPastDoesNotSpawnDespiteAvailableFrom() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seed(
      store,
      SeedTask(
        id: "rec-until", dueDate: "2026-03-15", availableFrom: "2026-03-10",
        canonicalOccurrenceDate: "2026-03-15",
        recurrence: #"{"FREQ":"MONTHLY","INTERVAL":1,"UNTIL":"2026-03-20"}"#,
        recurrenceGroupId: "grp-u"))
    let succ = try completeAndReadSuccessor(store, taskId: "rec-until", now: "2026-03-25T10:00:00Z")
    XCTAssertNil(succ, "UNTIL in the past → no successor")
  }
}
