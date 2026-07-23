import Foundation
import LorvexDomain
import XCTest

@testable import LorvexWorkflow

final class CalendarRecurrenceScopeTests: XCTestCase {
  /// Truncate and return the parsed recurrence object, matching the Rust test
  /// helper that parses the rewritten JSON back before asserting fields.
  private func truncated(_ raw: String, _ split: String, _ start: String) -> [String: JSONValue] {
    switch CalendarRecurrenceScope.truncateRecurrenceBefore(
      rawRecurrence: raw, splitDateYmd: split, seriesStartYmd: start)
    {
    case .truncated(let next):
      guard let parsed = JSONValue.parse(next), case .object(let obj) = parsed else {
        XCTFail("rewritten recurrence was not a JSON object: \(next)")
        return [:]
      }
      return obj
    case let other:
      XCTFail("expected truncation, got \(other)")
      return [:]
    }
  }

  func testTruncatesUnboundedDailyRecurrenceToSplitMinusOne() {
    let next = truncated(#"{"FREQ":"DAILY","INTERVAL":1}"#, "2026-05-10", "2026-05-01")
    XCTAssertEqual(next["UNTIL"], .string("2026-05-09"))
    XCTAssertEqual(next["FREQ"], .string("DAILY"))
  }

  func testMalformedOrNonObjectRecurrenceCollapsesOriginal() {
    XCTAssertEqual(
      CalendarRecurrenceScope.truncateRecurrenceBefore(
        rawRecurrence: nil, splitDateYmd: "2026-05-10", seriesStartYmd: "2026-05-01"), .collapse)
    XCTAssertEqual(
      CalendarRecurrenceScope.truncateRecurrenceBefore(
        rawRecurrence: "not-json", splitDateYmd: "2026-05-10", seriesStartYmd: "2026-05-01"),
      .collapse)
    XCTAssertEqual(
      CalendarRecurrenceScope.truncateRecurrenceBefore(
        rawRecurrence: "[1,2,3]", splitDateYmd: "2026-05-10", seriesStartYmd: "2026-05-01"),
      .collapse)
  }

  func testPreservesEarlierUntilInsteadOfExtendingSeries() {
    let next = truncated(#"{"FREQ":"DAILY","UNTIL":"2026-05-03"}"#, "2026-05-10", "2026-05-01")
    XCTAssertEqual(next["UNTIL"], .string("2026-05-03"))
  }

  func testWeeklyCountBydayInsideRangeClampsAndPreservesGrid() {
    let next = truncated(
      #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"COUNT":10}"#, "2026-02-15", "2026-01-05")
    XCTAssertEqual(next["COUNT"], .int(6))
    XCTAssertEqual(next["BYDAY"], .array([.string("MO")]))
    XCTAssertNil(next["UNTIL"])
  }

  func testWeeklyCountBydayFinishedSeriesIsNoop() {
    XCTAssertEqual(
      CalendarRecurrenceScope.truncateRecurrenceBefore(
        rawRecurrence: #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"COUNT":10}"#,
        splitDateYmd: "2026-03-15", seriesStartYmd: "2026-01-05"), .noop)
  }

  func testCountBoundedMonthEndUsesValidRfcInstances() {
    let next = truncated(
      #"{"FREQ":"MONTHLY","BYMONTHDAY":[-1],"COUNT":3}"#,
      "2026-03-15", "2026-01-31")
    XCTAssertEqual(next["COUNT"], .int(2))
    XCTAssertNil(next["UNTIL"])
  }

  func testYearlyLeapDayCountUsesValidRfcInstances() {
    let next = truncated(
      #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":[29],"COUNT":3}"#,
      "2030-01-01", "2024-02-29")
    XCTAssertEqual(next["COUNT"], .int(2))
    XCTAssertNil(next["UNTIL"])
  }

  func testMonthlyBydayCountUsesTheSharedExpansionGrid() {
    let next = truncated(
      #"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[2],"COUNT":5}"#,
      "2026-04-01", "2026-01-12")
    XCTAssertEqual(next["COUNT"], .int(3))
    XCTAssertEqual(next["BYDAY"], .array([.string("MO")]))
    XCTAssertNil(next["UNTIL"])
  }

  func testCountBoundedFinishedSeriesIsNoop() {
    XCTAssertEqual(
      CalendarRecurrenceScope.truncateRecurrenceBefore(
        rawRecurrence: #"{"FREQ":"DAILY","COUNT":2}"#,
        splitDateYmd: "2026-05-10", seriesStartYmd: "2026-05-01"), .noop)
  }

  func testSplitAtSeriesStartCollapsesOriginal() {
    XCTAssertEqual(
      CalendarRecurrenceScope.truncateRecurrenceBefore(
        rawRecurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        splitDateYmd: "2026-05-01", seriesStartYmd: "2026-05-01"), .collapse)
  }

  func testRebasesMultiDayPayloadDatesToOccurrence() {
    let result = CalendarRecurrenceScope.rebaseDateRangeToOccurrence(
      startDate: "2026-05-01", endDate: "2026-05-03", occurrenceDate: "2026-05-10")
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.0, "2026-05-10")
    XCTAssertEqual(result?.1, "2026-05-12")
  }
}
