import Foundation

/// Converts between Lorvex's all-day date span and EventKit's. Lorvex stores an
/// all-day event's first and last occupied days. EventKit reports an all-day
/// `endDate` as the last occupied day at 23:59:59, and while `isAllDay` is set
/// it normalizes any end it is given to 23:59:59 of the day that end falls on,
/// so a next-midnight end silently adds a day. Calendar arithmetic is required
/// so daylight-saving transitions never turn a civil-day conversion into a
/// fixed 24-hour offset.
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

  /// The `endDate` to give EventKit for an all-day event that starts on
  /// `start` and last occupies the day of `inclusiveEnd` (`nil` for a one-day
  /// event): that day at 23:59:59 in `calendar`, EventKit's own
  /// representation, so it is stored and read back unchanged. A last day
  /// before the start day is treated as the start day.
  public static func eventKitEnd(
    start: Date, inclusiveEnd: Date?, calendar: Calendar
  ) -> Date {
    let lastDay = calendar.startOfDay(for: max(inclusiveEnd ?? start, start))
    let nextDay =
      calendar.date(byAdding: .day, value: 1, to: lastDay)
      ?? lastDay.addingTimeInterval(24 * 60 * 60)
    return nextDay.addingTimeInterval(-1)
  }

  /// The last occupied day, as its midnight in `calendar`, of an EventKit
  /// all-day event that starts on `start` and ends at `eventKitEnd`: the day
  /// holding the instant just before that end. EventKit's 23:59:59 names its
  /// own day and a next-midnight end names the day before, so either shape
  /// reads correctly. Never earlier than the start day.
  public static func inclusiveEnd(
    start: Date, eventKitEnd: Date, calendar: Calendar
  ) -> Date {
    calendar.startOfDay(for: max(eventKitEnd.addingTimeInterval(-1), start))
  }
}
