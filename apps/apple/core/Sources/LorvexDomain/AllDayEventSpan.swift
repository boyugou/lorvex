import Foundation

/// Converts between Lorvex's inclusive all-day date span and calendar-provider
/// APIs whose end is the first excluded day. Calendar arithmetic is required so
/// daylight-saving transitions never turn a civil-day conversion into a fixed
/// 24-hour offset.
public enum AllDayEventSpan {
  /// The calendar used to interpret an EventKit all-day event's civil dates.
  /// Lorvex's stored day keys are always proleptic Gregorian, independent of
  /// the user's display calendar, but must use the event's local time zone so
  /// midnight does not drift to an adjacent date during projection.
  public static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return calendar
  }

  /// Render an all-day instant as Lorvex's canonical civil-date key without a
  /// shared mutable `DateFormatter`. This is safe under parallel EventKit
  /// ingestion on macOS and iOS and cannot inherit a non-Gregorian user
  /// calendar.
  public static func dayKey(for date: Date, timeZone: TimeZone) -> String {
    let components = gregorianCalendar(timeZone: timeZone)
      .dateComponents([.year, .month, .day], from: date)
    return IsoDate.YMD(
      year: components.year ?? 0,
      month: components.month ?? 0,
      day: components.day ?? 0
    ).canonicalString
  }

  public static func exclusiveEnd(
    start: Date, inclusiveEnd: Date?, calendar: Calendar
  ) -> Date {
    let finalOccupiedDay = max(inclusiveEnd ?? start, start)
    return calendar.date(byAdding: .day, value: 1, to: finalOccupiedDay)
      ?? finalOccupiedDay.addingTimeInterval(24 * 60 * 60)
  }

  public static func inclusiveEnd(
    start: Date, exclusiveEnd: Date, calendar: Calendar
  ) -> Date {
    calendar.date(byAdding: .day, value: -1, to: exclusiveEnd)
      .map { max($0, start) }
      ?? start
  }
}
