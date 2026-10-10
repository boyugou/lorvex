import Foundation

extension LorvexTask {
  /// A system-localized relative label for the due date — "today" /
  /// "tomorrow" / "yesterday" / "in 3d" / "3d ago", or `nil` when the task has
  /// no due date. Comparison is day-granular, in whole days from the day `now`
  /// falls on in `timeZone`, so a due date later today still reads "today"
  /// rather than "in 5 hours". The whole-day difference goes through the
  /// formatter's day unit: two equal instants would format as "now", the
  /// seconds unit, instead of "today".
  ///
  /// `unitsStyle` is `.abbreviated` for the compact chip a row draws and
  /// `.full` for speech: VoiceOver spells an abbreviation such as "3d" out
  /// letter by letter, while the full style reads "in 3 days" or "3 days ago".
  public func cachedDueRelativeLabel(
    now: Date = Date(), timeZone: TimeZone = .current,
    unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .abbreviated
  ) -> String? {
    guard let dueDate else { return nil }
    let days = PlannedDayBridge.dayOffset(from: now, toStorageDate: dueDate, timeZone: timeZone)
    return LorvexDateFormatters.relativeDays(days, unitsStyle: unitsStyle)
  }
}
