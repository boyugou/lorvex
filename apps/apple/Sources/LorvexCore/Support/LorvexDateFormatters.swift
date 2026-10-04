import Foundation

/// Shared date formatting for every Lorvex Apple surface, in two kinds.
///
/// **Machine formatters** (``ymd``, ``ymdUTC``, ``hourMinute``, ``iso8601``,
/// ``iso8601Fractional``) write and parse day keys and wire timestamps. They
/// are pinned to POSIX and the Gregorian calendar, so the strings they produce
/// never drift with the device's language, region, or calendar (a Thai
/// Buddhist or Japanese-era calendar would otherwise write `yyyy-MM-dd` in the
/// wrong year).
///
/// **Display functions** write dates for people. Each takes the time zone the
/// date is shown in and a `locale` that defaults to
/// ``LorvexClockFormat/displayLocale``: the app's language with the user's
/// region conventions, calendar, digits, and the clock chosen in Settings. The
/// default is read on every call, so a change of region, calendar, or clock
/// applies to the next label without a relaunch. Dates are written in the
/// locale's own calendar — Gregorian in most regions, Buddhist years in
/// Thailand, Persian months in Iran — the calendar ``displayCalendar(timeZone:locale:)``
/// lays out month grids and date pickers in. Stored day keys stay Gregorian;
/// ``PlannedDayBridge`` converts between the two.
///
/// Formatters are cached by everything that changes their output, because
/// creating a `DateFormatter` costs far more than using one.
/// `nonisolated(unsafe)`: `DateFormatter` / `ISO8601DateFormatter` are
/// documented thread-safe for `string(from:)` / `date(from:)` once configured;
/// the cached ones are configured once and never mutated.
public enum LorvexDateFormatters {
  /// Gregorian calendar in an explicit time zone, for arithmetic on stored
  /// days and on wall-clock times: hours and minutes, the weekday of a day
  /// key, the interval EventKit queries. Its locale gives week rules (first
  /// weekday) only; dates shown to the user use ``displayCalendar(timeZone:locale:)``.
  public static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .autoupdatingCurrent
    calendar.timeZone = timeZone
    return calendar
  }

  /// The calendar dates are shown in: `locale`'s own calendar (Gregorian for
  /// most regions, Buddhist in Thailand, Persian in Iran, or whichever
  /// calendar the user chose), with its first weekday, in `timeZone`. Month
  /// grids and day pickers lay out days in it, the way the display functions
  /// write them.
  public static func displayCalendar(
    timeZone: TimeZone, locale: Locale = LorvexClockFormat.displayLocale
  ) -> Calendar {
    var calendar = locale.calendar
    calendar.locale = locale
    calendar.timeZone = timeZone
    return calendar
  }

  // MARK: - Machine formatters

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
  /// device-local values. Provider-event mapping uses the event's own zone.
  public static let hourMinute: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .autoupdatingCurrent
    f.dateFormat = "HH:mm"
    return f
  }()

  /// ISO-8601 with internet date-time (no fractional seconds) in UTC — the
  /// canonical wire timestamp.
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

  // MARK: - Display functions

  /// `date` written from a localized template, which names the fields and
  /// lets the locale order and punctuate them: "EEE" writes "Mon" / "周一",
  /// "MMMd" writes "Sep 29" / "9月29日", "yyyyMMMM" writes "September 2026" /
  /// "2026年9月". Spanish, French, Italian, Portuguese, Russian, Ukrainian,
  /// Polish, Dutch, and Romanian write weekday and month names in lowercase;
  /// `position` `.leading` is for a date that opens a title, heading, or
  /// label, which takes a capital where the language capitalizes the start of
  /// a sentence ("Septiembre de 2026"). `.inline`, the default, keeps the
  /// language's lowercase.
  public static func string(
    _ date: Date, template: String, timeZone: TimeZone,
    locale: Locale = LorvexClockFormat.displayLocale,
    position: LorvexDayPhrase.Position = .inline
  ) -> String {
    displayFormatters.formatter(.template(template, position), timeZone: timeZone, locale: locale)
      .string(from: date)
  }

  /// `date` in one of the locale's date styles: `.medium` writes "Sep 29,
  /// 2026" / "2026年9月29日", `.full` writes "Tuesday, September 29, 2026".
  public static func string(
    _ date: Date, dateStyle: DateFormatter.Style, timeZone: TimeZone,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    displayFormatters.formatter(.styles(date: dateStyle, time: .none), timeZone: timeZone, locale: locale)
      .string(from: date)
  }

  /// The day of the month as a bare numeral in the locale's calendar and
  /// digits ("29"; "٢٩" in Arabic), for a day cell or a column header. A
  /// localized day template would add the suffix some languages write after
  /// the number ("29日"), which a day cell cannot hold.
  public static func dayNumber(
    _ date: Date, timeZone: TimeZone, locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    displayFormatters.formatter(.fixed("d"), timeZone: timeZone, locale: locale).string(from: date)
  }

  /// The days from `start` to `end` written from a localized template, with
  /// the fields both share written once: "MMMd" writes "Sep 22 – 28" within a
  /// month and "Sep 27 – Oct 3" across two. `position` is as for
  /// ``string(_:template:timeZone:locale:position:)``; an interval formatter
  /// has no capitalization context, so a `.leading` range has its first
  /// letter uppercased in `locale`.
  public static func range(
    from start: Date, to end: Date, template: String, timeZone: TimeZone,
    locale: Locale = LorvexClockFormat.displayLocale,
    position: LorvexDayPhrase.Position = .inline
  ) -> String {
    let text = displayFormatters.intervalFormatter(
      template: template, timeZone: timeZone, locale: locale
    ).string(from: start, to: end)
    guard position == .leading else { return text }
    return String(text.prefix(1)).uppercased(with: locale) + text.dropFirst()
  }

  /// `date`'s clock time in the locale's standard short time pattern: "9:45 AM"
  /// where the clock is 12-hour, "09:45" where it is 24-hour. This is the
  /// pattern the span format of ``lorvexClockRangeLabel(startMinutes:endMinutes:)``
  /// pads its ends to, so a single time and a span on one screen agree.
  /// `Date.FormatStyle`'s `.shortened` time is not used: it drops the leading
  /// zero of a 24-hour hour ("9:45") while spans keep it.
  public static func clockTime(
    _ date: Date, timeZone: TimeZone = .autoupdatingCurrent,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    displayFormatters.formatter(.styles(date: .none, time: .short), timeZone: timeZone, locale: locale)
      .string(from: date)
  }

  /// `date` as its day and clock time ("Sep 29, 2026 at 9:45 AM", "2026年9月29日
  /// 09:45"): the locale's medium date, then the clock time of
  /// ``clockTime(_:timeZone:locale:)``.
  public static func dayAndClockTime(
    _ date: Date, timeZone: TimeZone = .autoupdatingCurrent,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    displayFormatters.formatter(.styles(date: .medium, time: .short), timeZone: timeZone, locale: locale)
      .string(from: date)
  }

  /// `date`'s hour alone in the locale's hour pattern ("9 AM", "21", "上午9时"),
  /// as a time grid labels its rows.
  public static func hourLabel(
    _ date: Date, timeZone: TimeZone = .autoupdatingCurrent,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    displayFormatters.formatter(.template("j", .inline), timeZone: timeZone, locale: locale)
      .string(from: date)
  }

  /// `date` relative to `reference`: "4 minutes ago" or "in 2 hours" with
  /// `.full` units, "4 min. ago" with `.abbreviated`; a `.named` style writes
  /// "yesterday" or "now" where the language has a word for the distance.
  /// Where a language's `.abbreviated` style does not read as a phrase (a bare
  /// signed number, "-4 j", or a clipped word, Malay's "semlm"), the short
  /// style's phrase is used instead. The phrase starts in lowercase in every
  /// language, so it continues a sentence or labels a lowercase chip.
  public static func relative(
    _ date: Date, to reference: Date,
    unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .full,
    dateTimeStyle: RelativeDateTimeFormatter.DateTimeStyle = .named,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    relativePhrase(unitsStyle: unitsStyle, dateTimeStyle: dateTimeStyle, locale: locale) {
      $0.localizedString(for: date, relativeTo: reference)
    }
  }

  /// A whole number of days from today, named where the language has a word
  /// for it: "today", "tomorrow", "3 days ago"; "in 3d" with `.abbreviated`
  /// units. Counting whole days keeps a due date later today reading "today"
  /// rather than "in 5 hours". Where a language's `.abbreviated` style does
  /// not read as a phrase (a bare signed number, "-3 j", or a clipped word,
  /// Malay's "semlm"), the short style's phrase is used instead. The phrase
  /// starts in lowercase in every language, so it continues a sentence or
  /// labels a lowercase chip.
  public static func relativeDays(
    _ days: Int, unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .full,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    relativePhrase(unitsStyle: unitsStyle, dateTimeStyle: .named, locale: locale) {
      $0.localizedString(from: DateComponents(day: days))
    }
  }

  /// How long ago something happened, given its age in seconds, in the
  /// largest whole unit: "5 min. ago" under an hour, "2 hr. ago" under a day,
  /// then "3 days ago"; never less than a minute. The system words the whole
  /// phrase, so each language keeps its own grammar ("vor 3 Tagen",
  /// "hace 2 h", "3天前").
  public static func elapsed(
    seconds: Int, unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .short,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    let components =
      if seconds >= 86_400 {
        DateComponents(day: -(seconds / 86_400))
      } else if seconds >= 3_600 {
        DateComponents(hour: -(seconds / 3_600))
      } else {
        DateComponents(minute: -max(1, seconds / 60))
      }
    return relativePhrase(unitsStyle: unitsStyle, dateTimeStyle: .numeric, locale: locale) {
      $0.localizedString(from: components)
    }
  }

  /// The phrase `phrase` reads from the cached relative formatter for
  /// `unitsStyle`, adjusted in three languages whose system data does not read
  /// as a phrase a sentence continues with or a lowercase chip shows:
  ///
  /// - French, Russian, and Romanian write the abbreviated style as a bare
  ///   signed number ("-3 j", "-3 дн", "-45 zile"), which reads as arithmetic
  ///   rather than a time, while their short style keeps the whole phrase
  ///   ("il y a 3 j"); a result that starts with a sign is therefore written
  ///   again in the short style.
  /// - Malay writes "yesterday" abbreviated as "semlm" and every other
  ///   abbreviated phrase exactly as its short style, so Malay uses the short
  ///   style throughout.
  /// - Vietnamese capitalizes its day words ("Hôm qua", "Ngày kia"), so the
  ///   first letter of a phrase is lowercased.
  private static func relativePhrase(
    unitsStyle: RelativeDateTimeFormatter.UnitsStyle,
    dateTimeStyle: RelativeDateTimeFormatter.DateTimeStyle, locale: Locale,
    phrase: (RelativeDateTimeFormatter) -> String
  ) -> String {
    let style: RelativeDateTimeFormatter.UnitsStyle =
      unitsStyle == .abbreviated && locale.language.languageCode?.identifier == "ms" ? .short : unitsStyle
    var result = phrase(
      displayFormatters.relativeFormatter(unitsStyle: style, dateTimeStyle: dateTimeStyle, locale: locale))
    if style == .abbreviated,
      let first = result.first(where: { !directionMarks.contains($0) }),
      "-\u{2212}+".contains(first)
    {
      result = phrase(
        displayFormatters.relativeFormatter(unitsStyle: .short, dateTimeStyle: dateTimeStyle, locale: locale))
    }
    return loweringFirstLetter(of: result)
  }

  /// The invisible marks a right-to-left phrase may open with.
  private static let directionMarks: Set<Character> = ["\u{200E}", "\u{200F}", "\u{061C}"]

  /// `text` with its first character lowercased when that is an uppercase
  /// letter; a leading direction mark is skipped.
  private static func loweringFirstLetter(of text: String) -> String {
    guard let index = text.firstIndex(where: { !directionMarks.contains($0) }),
      text[index].isUppercase
    else { return text }
    var lowered = text
    lowered.replaceSubrange(index...index, with: text[index].lowercased())
    return lowered
  }

  private static let displayFormatters = DisplayFormatterCache()

  /// The display patterns a cached `DateFormatter` is built from.
  fileprivate enum Pattern {
    case template(String, LorvexDayPhrase.Position)
    case styles(date: DateFormatter.Style, time: DateFormatter.Style)
    case fixed(String)

    /// The pattern's part of a cache key.
    var key: String {
      switch self {
      case .template(let template, let position):
        "template:\(template):\(position == .leading ? "leading" : "inline")"
      case .styles(let date, let time): "styles:\(date.rawValue):\(time.rawValue)"
      case .fixed(let format): "fixed:\(format)"
      }
    }
  }

  /// Display formatters keyed by what changes their output: the locale's
  /// identifier, calendar, digits, and hour cycle, the time zone, and the
  /// pattern. The key reads the locale at call time, so a formatter built for
  /// the autoupdating locale is replaced, rather than reused, once the user's
  /// region, calendar, digits, or 12/24-hour setting changes. The formatters
  /// are thread-safe once configured; the lock guards only the dictionaries.
  private final class DisplayFormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var dateFormatters: [String: DateFormatter] = [:]
    private var intervalFormatters: [String: DateIntervalFormatter] = [:]
    private var relativeFormatters: [String: RelativeDateTimeFormatter] = [:]

    /// A process meets a handful of keys; a full cache means settings churned.
    private static let capacity = 64

    private static func key(_ locale: Locale, _ parts: String...) -> String {
      ([
        locale.identifier, "\(locale.calendar.identifier)",
        locale.numberingSystem.identifier, "\(locale.hourCycle)",
      ] + parts).joined(separator: "|")
    }

    func formatter(_ pattern: Pattern, timeZone: TimeZone, locale: Locale) -> DateFormatter {
      let key = Self.key(locale, timeZone.identifier, pattern.key)
      return lock.withLock {
        if let formatter = dateFormatters[key] { return formatter }
        let formatter = DateFormatter()
        // Assigning the locale also gives the formatter the locale's calendar.
        formatter.locale = locale
        formatter.timeZone = timeZone
        switch pattern {
        case .template(let template, let position):
          formatter.setLocalizedDateFormatFromTemplate(template)
          if position == .leading { formatter.formattingContext = .beginningOfSentence }
        case .styles(let date, let time):
          formatter.dateStyle = date
          formatter.timeStyle = time
        case .fixed(let format):
          formatter.dateFormat = format
        }
        if dateFormatters.count >= Self.capacity { dateFormatters.removeAll() }
        dateFormatters[key] = formatter
        return formatter
      }
    }

    func intervalFormatter(template: String, timeZone: TimeZone, locale: Locale)
      -> DateIntervalFormatter
    {
      let key = Self.key(locale, timeZone.identifier, template)
      return lock.withLock {
        if let formatter = intervalFormatters[key] { return formatter }
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = LorvexDateFormatters.displayCalendar(timeZone: timeZone, locale: locale)
        formatter.timeZone = timeZone
        formatter.dateTemplate = template
        if intervalFormatters.count >= Self.capacity { intervalFormatters.removeAll() }
        intervalFormatters[key] = formatter
        return formatter
      }
    }

    func relativeFormatter(
      unitsStyle: RelativeDateTimeFormatter.UnitsStyle,
      dateTimeStyle: RelativeDateTimeFormatter.DateTimeStyle, locale: Locale
    ) -> RelativeDateTimeFormatter {
      let key = Self.key(locale, "\(unitsStyle.rawValue)", "\(dateTimeStyle.rawValue)")
      return lock.withLock {
        if let formatter = relativeFormatters[key] { return formatter }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = unitsStyle
        formatter.dateTimeStyle = dateTimeStyle
        if relativeFormatters.count >= Self.capacity { relativeFormatters.removeAll() }
        relativeFormatters[key] = formatter
        return formatter
      }
    }
  }

  // MARK: - Day keys

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
