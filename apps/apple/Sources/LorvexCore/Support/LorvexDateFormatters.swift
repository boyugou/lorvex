import Foundation

/// Shared, cached date formatters used across every Lorvex Apple surface.
///
/// `DateFormatter` / `ISO8601DateFormatter` initialization is expensive
/// (locale + calendar + parser setup) and was being re-allocated per call in
/// ~20 sites — some on per-row / per-task hot paths.
///
/// The day-key and wire formatters are pinned to POSIX + Gregorian so the
/// produced strings never drift with the device's default calendar (a
/// Japanese / Thai-Buddhist locale would otherwise format `yyyy-MM-dd` as a
/// wrong-era string). The user-facing display formatters (``weekdayAbbrev``,
/// ``dayOfMonth``) are the deliberate exception: they use the device locale so
/// calendar headers read in the user's language.
///
/// `nonisolated(unsafe)`: `DateFormatter` is documented thread-safe for
/// `string(from:)` / `date(from:)` once configured; these are configured once
/// at first access and never mutated.
public enum LorvexDateFormatters {
  /// Gregorian calendar for product wall-clock UI in an explicit timezone.
  /// Locale remains user-facing (weekday order and symbols), while calendar
  /// arithmetic stays aligned with Lorvex's Gregorian day-key contract.
  public static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .autoupdatingCurrent
    calendar.timeZone = timeZone
    return calendar
  }

  /// `yyyy-MM-dd` in the autoupdating device time zone. This is for genuinely
  /// device-local UI/calendar conversion only; product day-scoped state uses
  /// the logical day returned by the core. `autoupdatingCurrent` matters for a
  /// long-running app that crosses a travel/system-zone change after this
  /// cached formatter was first initialized.
  public static let ymd: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .autoupdatingCurrent
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  /// `yyyy-MM-dd` in UTC — for day keys that must be timezone-stable (e.g.
  /// values compared against UTC-anchored stored dates).
  public static let ymdUTC: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  /// `HH:mm` (24-hour) in the autoupdating device time zone — for explicitly
  /// device-local display. Provider-event mapping uses the event's own zone.
  public static let hourMinute: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .autoupdatingCurrent
    f.dateFormat = "HH:mm"
    return f
  }()

  /// Abbreviated weekday name ("Mon") in the device locale — for calendar day /
  /// week column headers. Deliberately not POSIX-pinned: this is a user-facing
  /// display string that should localize with the device language.
  public static let weekdayAbbrev: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE"
    return f
  }()

  /// Day-of-month number ("5") in the device locale — for calendar day / week
  /// column headers. Locale-aware for the same reason as ``weekdayAbbrev``.
  public static let dayOfMonth: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d"
    return f
  }()

  /// ISO-8601 with internet date-time (no fractional seconds) in UTC — the
  /// canonical wire timestamp. `nonisolated(unsafe)`: `ISO8601DateFormatter`
  /// is not `Sendable` but is documented thread-safe for formatting after
  /// configuration; configured once and never mutated.
  public nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
  }()

  /// ISO-8601 with fractional seconds in UTC — for sub-second-precision
  /// timestamps (matches the core's canonical millisecond-`Z` shape).
  public nonisolated(unsafe) static let iso8601Fractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
  }()

  /// Named abbreviated relative dates ("today", "tomorrow", "3d ago") used by
  /// task due labels. Configured once, then used read-only.
  public nonisolated(unsafe) static let namedAbbreviatedRelative: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.dateTimeStyle = .named
    f.unitsStyle = .abbreviated
    return f
  }()

  /// Abbreviated relative intervals ("3m", "2h") used by status surfaces.
  public nonisolated(unsafe) static let abbreviatedRelative: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
  }()

  /// Proleptic Gregorian calendar pinned to UTC — the day-arithmetic companion
  /// to ``ymdUTC`` so offsets computed on `yyyy-MM-dd` day keys never drift with
  /// the device time zone or a DST transition.
  private static let ymdUTCCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  /// Shift a canonical `yyyy-MM-dd` day key by whole calendar days, parsing and
  /// reformatting in UTC/Gregorian so the offset is locale- and time-zone-stable.
  /// Returns nil when `day` is not a parseable `yyyy-MM-dd` value.
  public static func ymdUTCAddingDays(_ day: String, days: Int) -> String? {
    guard let base = ymdUTC.date(from: day),
      let shifted = ymdUTCCalendar.date(byAdding: .day, value: days, to: base)
    else { return nil }
    return ymdUTC.string(from: shifted)
  }
}
