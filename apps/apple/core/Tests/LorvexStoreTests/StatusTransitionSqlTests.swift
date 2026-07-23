import XCTest

@testable import LorvexStore

final class StatusTransitionSqlTests: XCTestCase {
  func testSetValueFragmentsForClosedColumnSet() {
    XCTAssertEqual(StatusTransitionSql.setValueFragment("completed_at"), "completed_at = ?")
    XCTAssertEqual(StatusTransitionSql.setValueFragment("last_deferred_at"), "last_deferred_at = ?")
    XCTAssertEqual(
      StatusTransitionSql.setValueFragment("last_defer_reason"), "last_defer_reason = ?")
    XCTAssertEqual(StatusTransitionSql.setValueFragment("planned_date"), "planned_date = ?")
    XCTAssertEqual(StatusTransitionSql.setValueFragment("defer_count"), "defer_count = ?")
  }

  func testSetNullFragmentsForClosedColumnSet() {
    XCTAssertEqual(StatusTransitionSql.setNullFragment("completed_at"), "completed_at = NULL")
    XCTAssertEqual(
      StatusTransitionSql.setNullFragment("last_deferred_at"), "last_deferred_at = NULL")
    XCTAssertEqual(
      StatusTransitionSql.setNullFragment("last_defer_reason"), "last_defer_reason = NULL")
    XCTAssertEqual(StatusTransitionSql.setNullFragment("planned_date"), "planned_date = NULL")
    XCTAssertEqual(StatusTransitionSql.setNullFragment("defer_count"), "defer_count = NULL")
  }
}
