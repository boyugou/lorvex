import Foundation

extension LorvexTask {
  /// A short, system-localized relative label for the due date — "today" /
  /// "tomorrow" / "yesterday" / "in 3 days" / "3 days ago", or `nil` when the
  /// task has no due date. Comparison is day-granular, so a due date later
  /// today still reads "today" rather than "in 5 hours". Uses the shared
  /// read-only relative formatter to avoid per-row allocations.
  public func cachedDueRelativeLabel(now: Date = Date(), calendar: Calendar = .current) -> String? {
    guard let dueDate else { return nil }
    let startDue = dueDayStart(of: dueDate, in: calendar)
    let startNow = calendar.startOfDay(for: now)
    return LorvexDateFormatters.namedAbbreviatedRelative.localizedString(
      for: startDue,
      relativeTo: startNow
    )
  }
}
