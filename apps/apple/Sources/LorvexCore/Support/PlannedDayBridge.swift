import Foundation

/// Bridges between the storage convention for planned days — a timezone-naive
/// `YYYY-MM-DD` materialized at UTC midnight (`LorvexDateFormatters.ymdUTC`) —
/// and the user's local calendar.
///
/// Every `Date` that crosses the planned-date service boundary is formatted or
/// parsed in UTC, while every `Date` a user produces or sees (a date picker,
/// "defer to tomorrow", "plan for today") lives in the local calendar. Passing
/// one frame's instant into the other's formatter shifts the day near
/// midnight: west of UTC an evening "tomorrow" stored via UTC lands two days
/// out, and east of UTC a picker's local midnight stores as the previous day.
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

  /// The instant the storage formatter (`ymdUTC`) renders as the same
  /// `YYYY-MM-DD` that `localInstant` falls on in `calendar` — i.e. the local
  /// calendar day, anchored at UTC midnight. Use for every user-intended day
  /// handed to the service layer.
  public static func storageDate(
    forLocalInstant localInstant: Date, calendar: Calendar = .current
  ) -> Date {
    let day = calendar.dateComponents([.year, .month, .day], from: localInstant)
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

  /// Materialize a canonical product day in the calendar used by a UI surface.
  ///
  /// A logical day is a date *label*, not an instant. Parsing it as UTC and then
  /// handing that instant to a device-local calendar shifts the visible day west
  /// of Greenwich. Copying the UTC date components into `calendar` preserves the
  /// label while still letting the surface use its locale/first-weekday rules.
  public static func displayDate(
    forLogicalDay day: String, calendar: Calendar = .current
  ) -> Date? {
    guard let storageDate = storageDate(forLogicalDay: day) else { return nil }
    return displayDate(forStorageDate: storageDate, calendar: calendar)
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
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    guard
      let start = displayDate(forLogicalDay: from, calendar: calendar),
      let endExclusive = displayDate(forLogicalDay: afterThrough, calendar: calendar),
      start < endExclusive
    else { return nil }
    return LogicalDayInstantRange(start: start, endExclusive: endExclusive)
  }

  /// The instant a local-calendar control (a `DatePicker`) displays as the
  /// same `YYYY-MM-DD` the stored UTC-midnight `storageDate` names — i.e. the
  /// stored day, re-anchored at local midnight. Use for every stored planned
  /// date handed to UI controls.
  public static func displayDate(
    forStorageDate storageDate: Date, calendar: Calendar = .current
  ) -> Date {
    let day = utcCalendar.dateComponents([.year, .month, .day], from: storageDate)
    return calendar.date(from: day) ?? storageDate
  }
}
