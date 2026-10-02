import Foundation

/// Bridges between the storage convention for planned days — a timezone-naive
/// `YYYY-MM-DD` materialized at UTC midnight (`LorvexDateFormatters.ymdUTC`) —
/// and the user's local days.
///
/// Every `Date` that crosses the planned-date service boundary is formatted or
/// parsed in UTC, while every `Date` a user produces or sees (a date picker,
/// "defer to tomorrow", "plan for today") lives in a local time zone. Passing
/// one frame's instant into the other's formatter shifts the day near
/// midnight: west of UTC an evening "tomorrow" stored via UTC lands two days
/// out, and east of UTC a picker's local midnight stores as the previous day.
///
/// Both sides count days on the Gregorian calendar, the calendar storage keys
/// are written in, whatever calendar the user's region uses: a Thai user's
/// Buddhist year 2569 and a Persian user's 1405 both name 2026. So the local
/// side is described by its time zone alone.
public enum PlannedDayBridge {
  public struct LogicalDayInstantRange: Equatable, Sendable {
    public let start: Date
    public let endExclusive: Date

    public init(start: Date, endExclusive: Date) {
      self.start = start
      self.endExclusive = endExclusive
    }
  }

  private static let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  private static func localCalendar(_ timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  /// The instant the storage formatter (`ymdUTC`) renders as the same
  /// `YYYY-MM-DD` that `localInstant` falls on in `timeZone` — i.e. the local
  /// day, anchored at UTC midnight. Use for every user-intended day handed to
  /// the service layer.
  public static func storageDate(
    forLocalInstant localInstant: Date, timeZone: TimeZone = .current
  ) -> Date {
    let day = localCalendar(timeZone).dateComponents([.year, .month, .day], from: localInstant)
    return utcCalendar.date(from: day) ?? localInstant
  }

  /// Materialize a canonical product day (optionally shifted by whole days) as
  /// the UTC-midnight instant expected by planned/due/available date columns.
  /// This is the correct bridge for semantic actions such as "Today" and
  /// "Tomorrow": their source of truth is the synced logical-day key, not the
  /// device process's current calendar.
  public static func storageDate(forLogicalDay day: String, addingDays days: Int = 0) -> Date? {
    guard let shifted = LorvexDateFormatters.ymdUTCAddingDays(day, days: days) else { return nil }
    return LorvexDateFormatters.ymdUTC.date(from: shifted)
  }

  /// Materialize a canonical product day as midnight in the time zone a UI
  /// surface works in.
  ///
  /// A logical day is a date *label*, not an instant. Parsing it as UTC and then
  /// handing that instant to a device-local calendar shifts the visible day west
  /// of Greenwich. Copying the UTC date components into `timeZone` preserves the
  /// label.
  public static func displayDate(
    forLogicalDay day: String, timeZone: TimeZone = .current
  ) -> Date? {
    guard let storageDate = storageDate(forLogicalDay: day) else { return nil }
    return displayDate(forStorageDate: storageDate, timeZone: timeZone)
  }

  /// Convert an inclusive range of canonical product-day labels into the exact
  /// absolute interval EventKit and other instant-based providers require.
  /// `endExclusive` is midnight after `through`, in the configured product
  /// timezone, so the complete final logical day is covered across DST changes.
  public static func instantRange(
    fromLogicalDay from: String,
    throughLogicalDay through: String,
    timezoneName: String
  ) -> LogicalDayInstantRange? {
    guard from <= through,
      let timezone = TimeZone(identifier: timezoneName),
      let afterThrough = LorvexDateFormatters.ymdUTCAddingDays(through, days: 1)
    else { return nil }
    guard
      let start = displayDate(forLogicalDay: from, timeZone: timezone),
      let endExclusive = displayDate(forLogicalDay: afterThrough, timeZone: timezone),
      start < endExclusive
    else { return nil }
    return LogicalDayInstantRange(start: start, endExclusive: endExclusive)
  }

  /// Whole days from the day `now` falls on in `timeZone` to the stored day
  /// `storageDate` names: 0 for today, 1 for tomorrow, -1 for yesterday.
  public static func dayOffset(
    from now: Date, toStorageDate storageDate: Date, timeZone: TimeZone = .current
  ) -> Int {
    let calendar = localCalendar(timeZone)
    let today = calendar.startOfDay(for: now)
    let day = displayDate(forStorageDate: storageDate, timeZone: timeZone)
    return calendar.dateComponents([.day], from: today, to: day).day ?? 0
  }

  /// The instant a local control (a `DatePicker`) in `timeZone` displays as the
  /// same `YYYY-MM-DD` the stored UTC-midnight `storageDate` names — i.e. the
  /// stored day, re-anchored at local midnight. Use for every stored planned
  /// date handed to UI controls.
  public static func displayDate(
    forStorageDate storageDate: Date, timeZone: TimeZone = .current
  ) -> Date {
    let day = utcCalendar.dateComponents([.year, .month, .day], from: storageDate)
    return localCalendar(timeZone).date(from: day) ?? storageDate
  }
}
