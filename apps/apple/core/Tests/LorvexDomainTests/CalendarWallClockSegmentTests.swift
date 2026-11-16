import Foundation
import XCTest

@testable import LorvexDomain

final class CalendarWallClockSegmentTests: XCTestCase {
  func testTransitionsPreserveElapsedMinutesAndCorrectWallPieces() throws {
    let cases: [(String, String, String, String, [[Int]])] = [
      ("2026-11-01T05:45:00Z", "2026-11-01T06:15:00Z", "2026-11-01", "America/New_York", [[105, 120, -14400], [60, 75, -18000]]),
      ("2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", "2026-11-01", "America/New_York", [[90, 120, -14400], [60, 90, -18000]]),
      ("2026-03-08T06:30:00Z", "2026-03-08T07:30:00Z", "2026-03-08", "America/New_York", [[90, 120, -18000], [180, 210, -14400]]),
      ("2026-04-04T14:50:00Z", "2026-04-04T15:10:00Z", "2026-04-05", "Australia/Lord_Howe", [[110, 120, 39600], [90, 100, 37800]]),
      ("2026-11-01T05:45:00Z", "2026-11-01T06:00:00Z", "2026-11-01", "America/New_York", [[105, 120, -14400]]),
      ("2026-11-01T06:00:00Z", "2026-11-01T06:15:00Z", "2026-11-01", "America/New_York", [[60, 75, -18000]]),
    ]
    for (start, end, day, zone, expected) in cases {
      let pieces = try segments(start, end, day, zone)
      XCTAssertEqual(pieces.map { [$0.startMinutes, $0.endMinutes, $0.secondsFromGMT] }, expected, zone)
      XCTAssertEqual(pieces.reduce(0) { $0 + $1.endMinutes - $1.startMinutes }, Int(date(end).timeIntervalSince(date(start)) / 60))
      XCTAssertEqual(pieces.first?.start, date(start))
      XCTAssertEqual(pieces.last?.end, date(end))
    }
  }

  func testDayClippingHandlesShortLongSkippedAndUnoccupiedDays() throws {
    let long = try segments("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z", "2026-11-01", "America/New_York")
    XCTAssertEqual(long.reduce(0) { $0 + $1.endMinutes - $1.startMinutes }, 1500)
    let short = try segments("2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z", "2026-03-08", "America/New_York")
    XCTAssertEqual(short.reduce(0) { $0 + $1.endMinutes - $1.startMinutes }, 1380)
    XCTAssertTrue(try segments("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z", "2026-11-02", "America/New_York").isEmpty)
    XCTAssertTrue(try segments("2011-12-29T00:00:00Z", "2012-01-01T00:00:00Z", "2011-12-30", "Pacific/Apia").isEmpty)
    XCTAssertTrue(try segments("2026-11-01T06:15:00Z", "2026-11-01T06:15:00Z", "2026-11-01", "America/New_York").isEmpty)
  }

  func testBothReadingsNeedOffsetsIncludingHalfHourFold() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    for instant in ["2026-11-01T05:00:00Z", "2026-11-01T05:59:00Z", "2026-11-01T06:00:00Z", "2026-11-01T06:59:00Z"] {
      XCTAssertTrue(CalendarWallClockSegment.isRepeatedClock(date(instant), in: zone))
    }
    XCTAssertFalse(CalendarWallClockSegment.isRepeatedClock(date("2026-11-01T07:00:00Z"), in: zone))
    let lordHowe = try XCTUnwrap(TimeZone(identifier: "Australia/Lord_Howe"))
    XCTAssertTrue(CalendarWallClockSegment.isRepeatedClock(date("2026-04-04T15:15:00Z"), in: lordHowe))
    XCTAssertFalse(CalendarWallClockSegment.isRepeatedClock(date("2026-04-04T15:30:00Z"), in: lordHowe))
  }

  private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
  private func segments(_ start: String, _ end: String, _ day: String, _ zone: String) throws -> [CalendarWallClockSegment] {
    CalendarWallClockSegment.segments(from: date(start), to: date(end), on: try LorvexDate.parse(day).get(), in: TimeZone(identifier: zone)!)
  }
}
