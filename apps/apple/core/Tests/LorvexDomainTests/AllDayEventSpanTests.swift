import Foundation
import XCTest

@testable import LorvexDomain

final class AllDayEventSpanTests: XCTestCase {
  /// March 8, 2026 is the US spring-forward day: 23 hours long in Los
  /// Angeles, so a fixed 24-hour offset would land on the wrong second.
  func testEventKitEndIsTheLastDayAt235959AcrossDaylightSavingAndReadsBack() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let start = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 3, day: 7)))
    let lastDay = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))

    let end = AllDayEventSpan.eventKitEnd(start: start, inclusiveEnd: lastDay, calendar: calendar)

    XCTAssertEqual(
      calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
      DateComponents(year: 2026, month: 3, day: 8, hour: 23, minute: 59, second: 59))
    XCTAssertEqual(
      AllDayEventSpan.inclusiveEnd(start: start, eventKitEnd: end, calendar: calendar), lastDay)
  }

  func testEventKitEndCoversAtLeastTheStartDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
    let earlier = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
    let startDayEnd = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 23, minute: 59, second: 59)))

    XCTAssertEqual(
      AllDayEventSpan.eventKitEnd(start: start, inclusiveEnd: earlier, calendar: calendar), startDayEnd)
    XCTAssertEqual(
      AllDayEventSpan.eventKitEnd(start: start, inclusiveEnd: nil, calendar: calendar), startDayEnd)
  }

  /// EventKit reports 23:59:59 of the last day; an exclusive next midnight
  /// names the same last day; a zero-length end reads as the start day.
  func testInclusiveEndReadsEitherEndShape() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
    func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) throws -> Date {
      try XCTUnwrap(
        calendar.date(
          from: DateComponents(year: 2030, month: 5, day: day, hour: hour, minute: minute, second: second)))
    }
    let start = try date(24)

    XCTAssertEqual(
      AllDayEventSpan.inclusiveEnd(start: start, eventKitEnd: try date(26, 23, 59, 59), calendar: calendar),
      try date(26))
    XCTAssertEqual(
      AllDayEventSpan.inclusiveEnd(start: start, eventKitEnd: try date(27), calendar: calendar),
      try date(26))
    XCTAssertEqual(
      AllDayEventSpan.inclusiveEnd(start: start, eventKitEnd: start, calendar: calendar), start)
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
