@preconcurrency import EventKit
import Foundation
import XCTest

@testable import LorvexMobile

/// EventKit's unsaved-event normalization uses framework-global state and is
/// not safe to exercise concurrently across multiple `EKEventStore` instances.
/// XCTest runs this bridge probe outside Swift Testing's parallel test phase.
final class MobileEventKitMappingTests: XCTestCase {
  /// EventKit reports an all-day end as the last day at 23:59:59, and turns
  /// a timed event with a next-midnight end into the same shape when it is
  /// flagged all-day. Both read as May 24 through May 26; a one-day event
  /// reads as its one day.
  func testAllDayEndMapsToTheLastOccupiedDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    func day(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) throws -> Date {
      try XCTUnwrap(
        calendar.date(
          from: DateComponents(
            year: 2030, month: 5, day: day, hour: hour, minute: minute, second: second)))
    }
    let stored = EKEvent(eventStore: EKEventStore())
    stored.isAllDay = true
    stored.startDate = try day(24)
    stored.endDate = try day(26, 23, 59, 59)
    let flaggedLater = EKEvent(eventStore: EKEventStore())
    flaggedLater.startDate = try day(24)
    flaggedLater.endDate = try day(27)
    flaggedLater.isAllDay = true
    let oneDay = EKEvent(eventStore: EKEventStore())
    oneDay.isAllDay = true
    oneDay.startDate = try day(24)
    oneDay.endDate = try day(24)

    for event in [stored, flaggedLater] {
      let fetched = MobileLiveEventKitAccess.fetchedEvent(from: event)
      XCTAssertEqual(fetched.startDate, "2030-05-24")
      XCTAssertEqual(fetched.endDate, "2030-05-26")
      XCTAssertNil(fetched.startTime)
      XCTAssertNil(fetched.endTime)
    }
    XCTAssertEqual(MobileLiveEventKitAccess.fetchedEvent(from: oneDay).endDate, "2030-05-24")
  }

  func testTimedEventMapsInItsOwnTimezoneAcrossMidnight() throws {
    let event = EKEvent(eventStore: EKEventStore())
    let reference = Date(timeIntervalSince1970: 1_900_000_000)
    let east = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
    let west = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))
    // At least one fixed-offset candidate differs from the test machine, so
    // this catches accidental fallback to the process-global device timezone.
    let eventTimeZone =
      east.secondsFromGMT(for: reference) != TimeZone.current.secondsFromGMT(for: reference)
      ? east : west
    event.timeZone = eventTimeZone
    event.isAllDay = false
    event.startDate = try date(
      year: 2030, month: 5, day: 24, hour: 23, minute: 30, timeZone: eventTimeZone)
    event.endDate = try date(
      year: 2030, month: 5, day: 25, hour: 0, minute: 30, timeZone: eventTimeZone)

    let fetched = MobileLiveEventKitAccess.fetchedEvent(from: event)

    XCTAssertEqual(fetched.startDate, "2030-05-24")
    XCTAssertEqual(fetched.startTime, "23:30")
    XCTAssertEqual(fetched.endDate, "2030-05-25")
    XCTAssertEqual(fetched.endTime, "00:30")
    XCTAssertEqual(fetched.timezone, eventTimeZone.identifier)
  }

  func testTimedEventMapsAcrossDstGapWithoutChangingItsInstants() throws {
    let event = EKEvent(eventStore: EKEventStore())
    let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    event.timeZone = newYork
    event.isAllDay = false
    event.startDate = try date(
      year: 2024, month: 3, day: 10, hour: 1, minute: 30, timeZone: newYork)
    event.endDate = try date(
      year: 2024, month: 3, day: 10, hour: 3, minute: 30, timeZone: newYork)

    let fetched = MobileLiveEventKitAccess.fetchedEvent(from: event)

    XCTAssertEqual(fetched.startDate, "2024-03-10")
    XCTAssertEqual(fetched.startTime, "01:30")
    XCTAssertEqual(fetched.endDate, "2024-03-10")
    XCTAssertEqual(fetched.endTime, "03:30")
    XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 60 * 60)
  }

  private func date(
    year: Int, month: Int, day: Int, hour: Int, minute: Int, timeZone: TimeZone
  ) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    var components = DateComponents()
    components.timeZone = timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return try XCTUnwrap(calendar.date(from: components))
  }
}
