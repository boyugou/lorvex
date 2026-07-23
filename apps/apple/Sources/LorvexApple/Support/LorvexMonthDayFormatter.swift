import Foundation

/// Localized month-day header formatter (`"MMM d"`, in locale element order) for
/// week-range and short-date labels. Cached `static let`s so repeated `body`
/// evaluation does not re-allocate the formatter.
enum LorvexMonthDayFormatter {
  /// In the current time zone — for headers that format local-time dates
  /// (calendar week ranges, review windows).
  static let local: DateFormatter = make(timeZone: nil)

  /// Pinned to UTC — for menu-bar due dates, which are stored and compared as
  /// UTC day keys (see ``LorvexDateFormatters/ymdUTC``); a device in a
  /// negative-offset zone would otherwise render them a day early.
  static let utc: DateFormatter = make(timeZone: TimeZone(secondsFromGMT: 0))

  private static func make(timeZone: TimeZone?) -> DateFormatter {
    let formatter = DateFormatter()
    if let timeZone {
      formatter.timeZone = timeZone
    }
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter
  }
}
