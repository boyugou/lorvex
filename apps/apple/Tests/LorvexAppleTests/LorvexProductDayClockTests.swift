import Foundation
import LorvexCore
import Testing

/// The product day's clock: minutes since midnight in the product zone, and
/// only while that zone's date is the product day.
struct LorvexProductDayClockTests {
  private static let shanghai = TimeZone(identifier: "Asia/Shanghai")!
  private static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
  /// 01:30 on 2026-10-02 in Shanghai, and 10:30 on 2026-10-01 in Los Angeles.
  private static let instant = ISO8601DateFormatter().date(from: "2026-10-01T17:30:00Z")!

  @Test("The minutes come from the product zone while its date is the product day")
  func minutesInTheProductZone() {
    #expect(
      LorvexProductDayClock.nowMinutes(on: "2026-10-02", in: Self.shanghai, at: Self.instant) == 90)
    #expect(
      LorvexProductDayClock.nowMinutes(on: "2026-10-01", in: Self.losAngeles, at: Self.instant)
        == 630)
  }

  @Test("A product day the zone's clock is not on has no clock position")
  func anotherDayHasNoClockPosition() {
    #expect(
      LorvexProductDayClock.nowMinutes(on: "2026-10-01", in: Self.shanghai, at: Self.instant) == nil)
    #expect(
      LorvexProductDayClock.nowMinutes(on: "2026-10-02", in: Self.losAngeles, at: Self.instant)
        == nil)
  }

  @Test("A grid's initial scroll follows the product day even when the device is on yesterday")
  func gridFocusUsesTheProductClock() throws {
    var deviceCalendar = Calendar(identifier: .gregorian)
    deviceCalendar.timeZone = Self.losAngeles
    let formatter = DateFormatter()
    formatter.calendar = deviceCalendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = deviceCalendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    let columns = CalendarGridModel.buildDays(
      rangeStart: try #require(formatter.date(from: "2026-10-01")), dayCount: 2,
      calendar: deviceCalendar, events: [], tasks: [], dayKeyFor: formatter.string(from:))
    let shanghai = LorvexProductDayClock(logicalDay: "2026-10-02", timeZone: Self.shanghai)
    let losAngeles = LorvexProductDayClock(logicalDay: "2026-10-01", timeZone: Self.losAngeles)
    #expect(columns.filter { $0.dayKey == shanghai.logicalDay }.map(\.dayKey) == ["2026-10-02"])
    #expect(CalendarGridModel.initialScrollAnchorHour(
      for: columns, todayKey: shanghai.logicalDay, nowMinute: shanghai.nowMinutes(at: Self.instant)) == 0)
    #expect(CalendarGridModel.initialScrollAnchorHour(
      for: columns, todayKey: losAngeles.logicalDay, nowMinute: losAngeles.nowMinutes(at: Self.instant)) == 9)
    // A page that contains the device's today but not the product's today
    // uses its content anchor, never the device clock's current hour.
    #expect(CalendarGridModel.initialScrollAnchorHour(
      for: Array(columns.prefix(1)), todayKey: shanghai.logicalDay,
      nowMinute: shanghai.nowMinutes(at: Self.instant)) == 8)
  }

  @Test("The grid clock reads civil minutes across DST jumps and fractional offsets")
  func gridClockHandlesDaylightSavingAndFractionalOffsets() throws {
    let cases: [(zone: String, instant: String, day: String, minutes: Int)] = [
      ("America/Los_Angeles", "2026-03-08T09:30:00Z", "2026-03-08", 90),
      ("America/Los_Angeles", "2026-03-08T10:30:00Z", "2026-03-08", 210),
      ("America/Los_Angeles", "2026-11-01T08:30:00Z", "2026-11-01", 90),
      ("America/Los_Angeles", "2026-11-01T09:30:00Z", "2026-11-01", 90),
      ("Asia/Kathmandu", "2026-10-01T18:30:00Z", "2026-10-02", 15),
      ("Australia/Adelaide", "2026-10-01T15:00:00Z", "2026-10-02", 30),
    ]
    for example in cases {
      let clock = LorvexProductDayClock(
        logicalDay: example.day, timeZone: try #require(TimeZone(identifier: example.zone)))
      let instant = try #require(ISO8601DateFormatter().date(from: example.instant))
      #expect(clock.nowMinutes(at: instant) == example.minutes, "\(example.zone), \(example.instant)")
    }
    let staleClock = LorvexProductDayClock(logicalDay: "2026-10-01", timeZone: Self.shanghai)
    #expect(staleClock.nowMinutes(at: Self.instant) == nil)
  }
}
