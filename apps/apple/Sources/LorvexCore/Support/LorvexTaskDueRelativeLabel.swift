import Foundation

extension LorvexTask {
  /// A short, system-localized relative label for the due date — "today" /
  /// "tomorrow" / "yesterday" / "in 3d" / "3d ago", or `nil` when the task has
  /// no due date. Comparison is day-granular, so a due date later today still
  /// reads "today" rather than "in 5 hours". The whole-day difference goes
  /// through the formatter's day unit: two equal instants would format as
  /// "now", the seconds unit, instead of "today". Uses the shared read-only
  /// relative formatter to avoid per-row allocations.
  public func cachedDueRelativeLabel(now: Date = Date(), calendar: Calendar = .current) -> String? {
    guard let dueDate else { return nil }
    let startDue = dueDayStart(of: dueDate, in: calendar)
    let startNow = calendar.startOfDay(for: now)
    let days = calendar.dateComponents([.day], from: startNow, to: startDue).day ?? 0
    return LorvexDateFormatters.namedAbbreviatedRelative.localizedString(from: DateComponents(day: days))
  }
}
