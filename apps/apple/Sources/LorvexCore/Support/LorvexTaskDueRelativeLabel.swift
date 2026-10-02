import Foundation

extension LorvexTask {
  /// A short, system-localized relative label for the due date — "today" /
  /// "tomorrow" / "yesterday" / "in 3d" / "3d ago", or `nil` when the task has
  /// no due date. Comparison is day-granular, in whole days from the day `now`
  /// falls on in `timeZone`, so a due date later today still reads "today"
  /// rather than "in 5 hours". The whole-day difference goes through the
  /// formatter's day unit: two equal instants would format as "now", the
  /// seconds unit, instead of "today".
  public func cachedDueRelativeLabel(now: Date = Date(), timeZone: TimeZone = .current) -> String? {
    guard let dueDate else { return nil }
    let days = PlannedDayBridge.dayOffset(from: now, toStorageDate: dueDate, timeZone: timeZone)
    return LorvexDateFormatters.relativeDays(days, unitsStyle: .abbreviated)
  }
}
