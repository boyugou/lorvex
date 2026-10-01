import Foundation

/// Cached user-facing formatters that follow the language selected for the
/// LorvexMobile resource bundle, including per-app language overrides.
enum MobileDateFormatting {
  static let weekdayAbbrev: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = MobileL10n.locale
    formatter.setLocalizedDateFormatFromTemplate("EEE")
    return formatter
  }()

  /// The day of the month as a bare numeral ("30"), for the calendar's day
  /// columns and week strip. A localized template would add the Chinese day
  /// suffix ("30日"), which the week strip's day circle cannot hold.
  static let dayOfMonth: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = MobileL10n.locale
    formatter.dateFormat = "d"
    return formatter
  }()

  /// A `yyyy-MM-dd` product day as a medium localized date ("Sep 17, 2026").
  /// Falls back to the raw string for anything that does not parse.
  static func dayLabel(ymd: String) -> String {
    guard let date = ymdParser.date(from: ymd) else { return ymd }
    return mediumDay.string(from: date)
  }

  private static let ymdParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let mediumDay: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = MobileL10n.locale
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  static func abbreviatedRelativeString(for date: Date, relativeTo referenceDate: Date) -> String {
    makeAbbreviatedRelativeFormatter().localizedString(for: date, relativeTo: referenceDate)
  }

  static func makeAbbreviatedRelativeFormatter() -> RelativeDateTimeFormatter {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = MobileL10n.locale
    formatter.unitsStyle = .abbreviated
    return formatter
  }
}
