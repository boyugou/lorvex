import GRDB
import XCTest

@testable import LorvexStore

/// The day buckets as rules over a task's two dates, evaluated by SQLite on a
/// real `tasks` row.
final class TaskReadBucketsTests: XCTestCase {
  private let today = "2026-03-23"
  private let yesterday = "2026-03-22"
  private let tomorrow = "2026-03-24"
  /// The last day an upcoming window of seven days reaches.
  private let windowEnd = "2026-03-30"
  private let afterWindow = "2026-03-31"

  /// The buckets a task with these dates matches on `today`, with the upcoming
  /// window reaching `windowEnd`. The predicates are built for the alias `t`
  /// and named placeholders, the form the day-surface reads use.
  private func buckets(due: String?, planned: String?) throws -> [String] {
    let store = try TestSupport.freshStore()
    return try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, due_date, planned_date, list_id, \
          version, created_at, updated_at, defer_count) \
          VALUES ('x', 'x', 'open', ?, ?, 'inbox', \
          '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', \
          '2026-01-01T00:00:00.000Z', 0)
          """,
        arguments: [due, planned])
      let overdue = TaskReadBuckets.overdueBucketPredicate(
        taskAlias: "t", datePlaceholder: ":today")
      let todayPool = TaskReadBuckets.todayPoolBucketPredicate(
        taskAlias: "t", datePlaceholder: ":today")
      let upcoming = TaskReadBuckets.upcomingBucketPredicate(
        taskAlias: "t", fromPlaceholder: ":today", toPlaceholder: ":to")
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: "SELECT \(overdue), \(todayPool), \(upcoming) FROM tasks AS t WHERE t.id = 'x'",
          arguments: ["today": self.today, "to": self.windowEnd]))
      let names = ["overdue", "today_pool", "upcoming"]
      return names.indices.filter { (row[$0] as Bool?) == true }.map { names[$0] }
    }
  }

  func testATaskWithNoPlannedDateIsOnTheDayItIsDue() throws {
    XCTAssertEqual(try buckets(due: yesterday, planned: nil), ["overdue"])
    XCTAssertEqual(try buckets(due: today, planned: nil), ["today_pool"])
    XCTAssertEqual(try buckets(due: tomorrow, planned: nil), ["upcoming"])
  }

  func testAPlannedDateDecidesTheDayWhateverTheDeadline() throws {
    XCTAssertEqual(try buckets(due: nil, planned: yesterday), ["today_pool"])
    XCTAssertEqual(try buckets(due: nil, planned: today), ["today_pool"])
    XCTAssertEqual(try buckets(due: nil, planned: tomorrow), ["upcoming"])
    XCTAssertEqual(try buckets(due: tomorrow, planned: yesterday), ["today_pool"])
    XCTAssertEqual(try buckets(due: tomorrow, planned: today), ["today_pool"])
    XCTAssertEqual(try buckets(due: today, planned: tomorrow), ["upcoming"])
  }

  /// A passed deadline keeps a task on the day only until the task is planned
  /// for a later one; it is then upcoming on the day it was planned for.
  func testAnOverdueTaskPlannedForALaterDayIsUpcomingNotOverdue() throws {
    XCTAssertEqual(try buckets(due: yesterday, planned: yesterday), ["overdue"])
    XCTAssertEqual(try buckets(due: yesterday, planned: today), ["overdue"])
    XCTAssertEqual(try buckets(due: yesterday, planned: tomorrow), ["upcoming"])
    XCTAssertEqual(try buckets(due: yesterday, planned: afterWindow), [])
  }

  func testTheUpcomingWindowStartsAfterTheDayAndIncludesItsLastDay() throws {
    XCTAssertEqual(try buckets(due: windowEnd, planned: nil), ["upcoming"])
    XCTAssertEqual(try buckets(due: afterWindow, planned: nil), [])
    XCTAssertEqual(try buckets(due: nil, planned: windowEnd), ["upcoming"])
    XCTAssertEqual(try buckets(due: nil, planned: afterWindow), [])
  }

  func testATaskWithNoDatesIsInNoBucket() throws {
    XCTAssertEqual(try buckets(due: nil, planned: nil), [])
  }
}
