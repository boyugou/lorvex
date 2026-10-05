import Foundation
import XCTest

@testable import LorvexStore

/// RFC 5545 scoping rules the expansion engine follows: where a `BYDAY` ordinal
/// counts from, and which months a negative `BYMONTHDAY` exists in. Expected
/// dates are the occurrences python-dateutil's `rrule` produces for the same
/// rules.
final class CalendarRecurrenceOrdinalScopeTests: XCTestCase {
  private func first(_ rule: String, base: String, target: String) -> String? {
    try! CalendarRecurrence.firstOccurrenceOnOrAfter(
      recurrenceJson: rule, baseDateYmd: base, targetDateYmd: target)
  }

  /// The next `count` occurrences after `base`, each found from the previous one
  /// the way a completed recurring task finds its successor.
  private func successors(_ rule: String, from base: String, count: Int) -> [String] {
    var result: [String] = []
    var current = base
    for _ in 0..<count {
      guard
        let next = try! CalendarRecurrence.calculateNextOccurrenceDate(
          recurrenceJson: rule, baseDateYmd: current)
      else { break }
      result.append(next)
      current = next
    }
    return result
  }

  // MARK: - BYDAY ordinals in YEARLY rules

  func test_yearly_ordinal_weekday_without_bymonth_counts_within_the_year() {
    let twentiethMonday = #"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["20MO"]}"#
    XCTAssertEqual(first(twentiethMonday, base: "2026-01-01", target: "2026-01-01"), "2026-05-18")
    XCTAssertEqual(first(twentiethMonday, base: "2026-01-01", target: "2026-05-19"), "2027-05-17")

    let twentiethFromLast = #"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["-20MO"]}"#
    XCTAssertEqual(first(twentiethFromLast, base: "2026-01-01", target: "2026-01-01"), "2026-08-17")
    XCTAssertEqual(first(twentiethFromLast, base: "2026-01-01", target: "2026-08-18"), "2027-08-16")

    let thirtySeventhTuesday = #"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["37TU"]}"#
    XCTAssertEqual(first(thirtySeventhTuesday, base: "2026-01-01", target: "2026-01-01"), "2026-09-15")
  }

  func test_yearly_fifty_third_weekday_waits_for_a_year_that_has_one() {
    // 2029 is the first year from 2026 whose last day is the 53rd Monday.
    let rule = #"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["53MO"]}"#
    XCTAssertEqual(first(rule, base: "2026-01-01", target: "2026-01-01"), "2029-12-31")
  }

  func test_yearly_ordinal_weekdays_of_mixed_sign_each_count_within_the_year() {
    let rule = #"{"FREQ":"YEARLY","INTERVAL":3,"BYDAY":["-5TU","1FR"]}"#
    XCTAssertEqual(
      successors(#"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["-5TU","1FR"]}"#, from: "2023-04-30", count: 4),
      ["2023-11-28", "2024-01-05", "2024-12-03", "2025-01-03"])
    XCTAssertEqual(first(rule, base: "2023-04-30", target: "2023-03-25"), "2023-11-28")
  }

  func test_yearly_ordinal_weekday_with_bymonth_counts_within_the_month() {
    let rule = #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[3],"BYDAY":["5MO"]}"#
    XCTAssertEqual(first(rule, base: "2026-01-01", target: "2026-01-01"), "2026-03-30")
    XCTAssertEqual(first(rule, base: "2026-01-01", target: "2026-03-31"), "2027-03-29")
  }

  // MARK: - Negative BYMONTHDAY

  func test_negative_month_day_longer_than_the_month_skips_that_month() {
    // -31 is the 1st of a 31-day month and does not exist in any other.
    let thirtyFirstFromEnd = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[-31]}"#
    XCTAssertEqual(first(thirtyFirstFromEnd, base: "2026-01-01", target: "2026-01-02"), "2026-03-01")
    XCTAssertEqual(
      successors(thirtyFirstFromEnd, from: "2026-01-01", count: 5),
      ["2026-03-01", "2026-05-01", "2026-07-01", "2026-08-01", "2026-10-01"])

    let thirtiethFromEnd = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[-30]}"#
    XCTAssertEqual(first(thirtiethFromEnd, base: "2026-01-01", target: "2026-01-03"), "2026-03-02")
  }

  func test_negative_month_day_that_fits_only_a_leap_february_skips_other_februaries() {
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[-29]}"#
    XCTAssertEqual(first(rule, base: "2028-01-01", target: "2028-01-04"), "2028-02-01")
    XCTAssertEqual(first(rule, base: "2027-01-01", target: "2027-01-04"), "2027-03-03")

    let february = #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":[-29]}"#
    XCTAssertEqual(first(february, base: "2026-01-01", target: "2026-01-01"), "2028-02-01")
    let never = #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":[-30]}"#
    XCTAssertNil(first(never, base: "2026-01-01", target: "2026-01-01"))
  }

  func test_last_day_of_the_month_still_resolves_in_every_month() {
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[-1]}"#
    XCTAssertEqual(
      successors(rule, from: "2026-01-31", count: 4),
      ["2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31"])
  }
}
