import XCTest

@testable import LorvexDomain

final class QueryTests: XCTestCase {
  private func ymd(_ y: Int, _ m: Int, _ d: Int) -> IsoDate.YMD {
    IsoDate.YMD(year: y, month: m, day: d)
  }

  func testPaginationDefaultValues() {
    let p = Pagination.default
    XCTAssertEqual(p.limit, 100)
    XCTAssertEqual(p.offset, 0)
  }

  func testTodayPredicateHoldsDate() {
    let pred = TodayPredicate(date: ymd(2026, 3, 23))
    XCTAssertEqual(pred.date.canonicalString, "2026-03-23")
  }

  func testUpcomingPredicateHoldsRange() {
    let pred = UpcomingPredicate(fromDate: ymd(2026, 3, 23), days: 7)
    XCTAssertEqual(pred.days, 7)
  }

  func testDeriveOpenTaskLatenessDistinguishesPastPlannedFromOverdueStates() {
    let today = ymd(2026, 4, 4)
    XCTAssertEqual(
      Query.deriveOpenTaskLateness(
        plannedDate: ymd(2026, 4, 3), dueDate: ymd(2026, 4, 7), asOfDate: today),
      .pastPlanned)
    XCTAssertEqual(
      Query.deriveOpenTaskLateness(
        plannedDate: nil, dueDate: ymd(2026, 4, 3), asOfDate: today),
      .overdueUnhandled)
    XCTAssertEqual(
      Query.deriveOpenTaskLateness(
        plannedDate: ymd(2026, 4, 4), dueDate: ymd(2026, 4, 3), asOfDate: today),
      .overdueAcknowledged)
    XCTAssertEqual(
      Query.deriveOpenTaskLateness(
        plannedDate: ymd(2026, 4, 5), dueDate: ymd(2026, 4, 3), asOfDate: today),
      .overdueAcknowledged)
  }

  func testSearchPredicateOptionalFilters() {
    let pred = SearchPredicate(query: "buy groceries")
    XCTAssertNil(pred.statusFilter)
  }
}
