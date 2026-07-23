import Foundation
import XCTest

@testable import LorvexDomain

final class AllDayEventSpanTests: XCTestCase {
  func testInclusiveAndExclusiveConversionsRoundTripAcrossDaylightSavingBoundary() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let start = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 3, day: 7)))
    let inclusiveEnd = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))

    let exclusiveEnd = AllDayEventSpan.exclusiveEnd(
      start: start, inclusiveEnd: inclusiveEnd, calendar: calendar)

    XCTAssertEqual(
      calendar.dateComponents([.year, .month, .day], from: exclusiveEnd),
      DateComponents(year: 2026, month: 3, day: 9))
    XCTAssertEqual(
      AllDayEventSpan.inclusiveEnd(
        start: start, exclusiveEnd: exclusiveEnd, calendar: calendar),
      inclusiveEnd)
  }

  func testExclusiveEndCannotProduceAnEmptyOrNegativeSpan() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
    let earlier = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))

    let exclusiveEnd = AllDayEventSpan.exclusiveEnd(
      start: start, inclusiveEnd: earlier, calendar: calendar)

    XCTAssertEqual(
      calendar.dateComponents([.year, .month, .day], from: exclusiveEnd),
      DateComponents(year: 2026, month: 7, day: 16))
  }

  func testDayKeyUsesExplicitTimeZoneAndGregorianCalendar() throws {
    let instant = Date(timeIntervalSince1970: 0)
    let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
    let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

    XCTAssertEqual(AllDayEventSpan.dayKey(for: instant, timeZone: utc), "1970-01-01")
    XCTAssertEqual(
      AllDayEventSpan.dayKey(for: instant, timeZone: losAngeles),
      "1969-12-31")
  }
}
