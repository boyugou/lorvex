import Foundation

/// The order the days of a week are shown in: from the first day of the week
/// in the user's region settings (Sunday in the United States, Monday in most
/// of Europe, Saturday in Egypt and Iran, or the day the user chose in System
/// Settings), as the Monday-first indices habits and recurrence rules store
/// (0 = Monday … 6 = Sunday).
///
/// Weekday pickers, lists of weekdays, and per-weekday charts use it. Habit
/// periods do not: a habit counts ISO weeks, Monday to Sunday, on every
/// device, so devices set to different regions agree on the week a check-in
/// counts toward, and the habit grids lay out those weeks.
public enum LorvexWeekdayOrder {
  /// The seven Monday-first weekday indices, starting from `calendar`'s first
  /// weekday.
  public static func mondayFirstIndices(
    calendar: Calendar = LorvexDateFormatters.displayCalendar(timeZone: .autoupdatingCurrent)
  ) -> [Int] {
    let start = startIndex(of: calendar)
    return (0..<7).map { (start + $0) % 7 }
  }

  /// `weekdays`, Monday-first indices, in the order `calendar`'s week shows
  /// them.
  public static func sorted<Weekdays: Sequence<Int>>(
    _ weekdays: Weekdays,
    calendar: Calendar = LorvexDateFormatters.displayCalendar(timeZone: .autoupdatingCurrent)
  ) -> [Int] {
    let start = startIndex(of: calendar)
    return weekdays.sorted { position($0, start: start) < position($1, start: start) }
  }

  /// How far into the week that starts on the Monday-first index `start` the
  /// Monday-first `weekday` falls.
  static func position(_ weekday: Int, start: Int) -> Int {
    ((weekday - start) % 7 + 7) % 7
  }

  /// `calendar.firstWeekday` (1 = Sunday … 7 = Saturday) as a Monday-first
  /// index.
  static func startIndex(of calendar: Calendar) -> Int {
    (calendar.firstWeekday + 5) % 7
  }
}
