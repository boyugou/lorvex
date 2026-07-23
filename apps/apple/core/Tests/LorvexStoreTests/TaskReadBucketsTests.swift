import XCTest

@testable import LorvexStore

final class TaskReadBucketsTests: XCTestCase {
  func testOverdueBucketPredicate() {
    XCTAssertEqual(
      TaskReadBuckets.overdueBucketPredicate(taskAlias: "tasks", datePlaceholder: "?1"),
      "tasks.due_date < ?1")
  }

  func testTodayPoolBucketPredicate() {
    let p = TaskReadBuckets.todayPoolBucketPredicate(taskAlias: "tasks", datePlaceholder: "?1")
    XCTAssertEqual(
      p,
      "(COALESCE(tasks.planned_date, tasks.due_date) <= ?1"
        + " AND (tasks.due_date IS NULL OR tasks.due_date >= ?1))")
  }

  func testUpcomingBucketPredicate() {
    let p = TaskReadBuckets.upcomingBucketPredicate(
      taskAlias: "tasks", fromPlaceholder: "?1", toPlaceholder: "?2")
    XCTAssertEqual(
      p,
      "((tasks.due_date IS NULL OR tasks.due_date >= ?1)"
        + " AND COALESCE(tasks.planned_date, tasks.due_date) > ?1"
        + " AND COALESCE(tasks.planned_date, tasks.due_date) <= ?2)")
  }

  func testAliasIsRespected() {
    XCTAssertEqual(
      TaskReadBuckets.overdueBucketPredicate(taskAlias: "t", datePlaceholder: ":today"),
      "t.due_date < :today")
  }
}
