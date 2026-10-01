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

  /// Named relative dates with the unit spelled out ("4 minutes ago",
  /// "yesterday") for status rows that have the room. Configured once, then
  /// used read-only.
  public nonisolated(unsafe) static let namedRelative: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.dateTimeStyle = .named
    return f
  }()

  /// Abbreviated relative intervals ("3m", "2h") used by status surfaces.
  public nonisolated(unsafe) static let abbreviatedRelative: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
  }()

  /// `date`'s clock time in the locale's standard short time pattern: "9:45 AM"
  /// where the clock is 12-hour, "09:45" where it is 24-hour. This is the
  /// pattern the span format of ``lorvexClockRangeLabel(startMinutes:endMinutes:)``
  /// pads its ends to, so a single time and a span on one screen agree.
  /// `Date.FormatStyle`'s `.shortened` time is not used: it drops the leading
  /// zero of a 24-hour hour ("9:45") while spans keep it.
  ///
  /// `locale` defaults to ``LorvexClockFormat/displayLocale``, read on every
  /// call, so a change of region, of the system's 12/24-hour setting, or of
  /// the app's clock choice applies to the next label.
  public static func clockTime(
    _ date: Date, timeZone: TimeZone = .autoupdatingCurrent,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    clockTimeFormatters.formatter(dateStyle: .none, timeZone: timeZone, locale: locale)
      .string(from: date)
  }

  /// `date` as its day and clock time ("Sep 29, 2026 at 9:45 AM", "2026年9月29日
  /// 09:45"): the locale's medium date on the Gregorian calendar, then the clock
  /// time of ``clockTime(_:timeZone:locale:)``.
  public static func dayAndClockTime(
    _ date: Date, timeZone: TimeZone = .autoupdatingCurrent,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    clockTimeFormatters.formatter(dateStyle: .medium, timeZone: timeZone, locale: locale)
      .string(from: date)
  }

  private static let clockTimeFormatters = ClockTimeFormatterCache()

  /// `date`'s hour alone in the locale's hour pattern ("9 AM", "21", "上午9时"),
  /// as a time grid labels its rows. `locale` defaults to
  /// ``LorvexClockFormat/displayLocale``, read on every call, so the label
  /// follows the clock the user chose.
  public static func hourLabel(
    _ date: Date, timeZone: TimeZone = .autoupdatingCurrent,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    hourFormatters.formatter(timeZone: timeZone, locale: locale).string(from: date)
  }

  private static let hourFormatters = HourFormatterCache()

  /// Hour-only formatters by locale, hour cycle, and time zone, keyed and
  /// locked like ``ClockTimeFormatterCache``.
  private final class HourFormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func formatter(timeZone: TimeZone, locale: Locale) -> DateFormatter {
      let key = "\(locale.identifier)|\(locale.hourCycle)|\(timeZone.identifier)"
      return lock.withLock {
        if let formatter = formatters[key] { return formatter }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("j")
        if formatters.count >= 32 { formatters.removeAll() }
        formatters[key] = formatter
        return formatter
      }
    }
  }

  /// Short-time formatters by locale, hour cycle, time zone, and date style.
  /// The key reads the locale's identifier and hour cycle at call time, so a
  /// formatter built for the autoupdating locale is replaced, rather than
  /// reused, once the user's region or 12/24-hour setting changes. `DateFormatter`
  /// is thread-safe for `string(from:)` once configured; the lock guards only
  /// the dictionary.
  private final class ClockTimeFormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func formatter(dateStyle: DateFormatter.Style, timeZone: TimeZone, locale: Locale)
      -> DateFormatter
    {
      let key = "\(locale.identifier)|\(locale.hourCycle)|\(timeZone.identifier)|\(dateStyle.rawValue)"
      return lock.withLock {
        if let formatter = formatters[key] { return formatter }
        let formatter = DateFormatter()
        // The locale first: assigning one resets the calendar to the locale's own.
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .short
        // A process meets a handful of keys; a full cache means settings churned.
        if formatters.count >= 32 { formatters.removeAll() }
        formatters[key] = formatter
        return formatter
      }
    }
  }

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
