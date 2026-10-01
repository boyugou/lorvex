import Foundation

/// Localized month-day header formatter (`"MMM d"`, in locale element order) for
/// week-range and short-date labels. Cached `static let`s so repeated `body`
/// evaluation does not re-allocate the formatter.
enum LorvexMonthDayFormatter {
  /// A month-and-day range in the current time zone, for headers that show a
  /// span of local days (the calendar week, the review window): the month is
  /// written once when both days share it ("Sep 22 – 28") and twice when they
  /// do not ("Sep 27 – Oct 3").
  static func localRange(from start: Date, to end: Date) -> String {
    localRangeFormatter.string(from: start, to: end)
  }

  private static let localRangeFormatter: DateIntervalFormatter = {
    let formatter = DateIntervalFormatter()
    formatter.dateTemplate = "MMMd"
    return formatter
  }()

  /// Pinned to UTC — for menu-bar due dates, which are stored and compared as
  /// UTC day keys (see ``LorvexDateFormatters/ymdUTC``); a device in a
  /// negative-offset zone would otherwise render them a day early.
  static let utc: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter
  }()
}
