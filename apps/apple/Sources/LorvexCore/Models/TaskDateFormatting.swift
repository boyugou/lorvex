import Foundation

public extension LorvexTask {
  /// The due day as an abbreviated localized date ("Sep 17, 2026"). Day-only
  /// dues are stored as UTC midnight, so the day is read in UTC: a local-zone
  /// read shows the previous day anywhere west of Greenwich.
  var dueDateDisplaySummary: String? {
    dueDate.map { Self.dueDayFormat.format($0) }
  }

  private static let dueDayFormat = Date.FormatStyle(
    date: .abbreviated, time: .omitted, timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt)
}
