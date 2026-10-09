import LorvexDomain

/// Which habits belong to a given day. A day's lists show the habits that are
/// on for that day rather than every habit there is: a habit kept only on
/// Mondays, Wednesdays and Fridays does not sit open on a Tuesday, a monthly
/// habit appears from its day of the month until it is done, and a
/// times-per-week habit stays until the week's quota is met.
///
/// The two kinds of list ask different questions. Today's habit grid, the menu
/// bar, the widgets and the watch show what is still open
/// (``isListed(on:)``); a day review judges what was due that day
/// (``isReviewed(on:)``), so a habit whose period has no particular day is
/// never counted as missed on a day it was not due.
extension LorvexHabit {
  /// Whether the habit's cadence makes `day` (`YYYY-MM-DD`) a day it is for. A
  /// daily habit is for every day; a weekly habit for its pinned weekdays
  /// (every day when none is pinned); a monthly habit for its day of the month
  /// (the 1st when unset), clamped to the month's last day; a times-per-week
  /// habit for no particular day, since its quota belongs to the week. A habit
  /// whose cadence fields cannot be read, or a `day` that is not a date,
  /// counts as due, so a malformed row never hides a habit.
  public func isDue(on day: String) -> Bool {
    guard case .success(let date) = LorvexDate.parse(day), let cadence = domainCadence else {
      return true
    }
    switch cadence {
    case .daily, .weekly, .monthly:
      return isHabitReminderDay(cadence, date)
    case .timesPerWeek:
      return false
    }
  }

  /// Whether the habit belongs on `day`'s list of open habits. It does when it
  /// was checked in that day, so a check-in stays on the list, can be undone
  /// there, and counts as kept, and when it was skipped that day, so a skip stays
  /// on the list and can be undone there; otherwise by its cadence:
  ///
  /// - a daily habit always;
  /// - a weekly habit on its pinned weekdays (every day when none is pinned);
  /// - a monthly habit from its day of the month, clamped to the month's last
  ///   day, until a day of the month has met its target;
  /// - a times-per-week habit until the week has as many days meeting its
  ///   target as its quota asks.
  ///
  /// `completionsToday` and `periodMetDays` are read against the day the habit
  /// was loaded for, so `day` is that day. A habit whose cadence fields cannot
  /// be read, or a `day` that is not a date, is listed, so a malformed row
  /// never hides a habit.
  public func isListed(on day: String) -> Bool {
    if completionsToday > 0 || isSkipped { return true }
    guard case .success(let date) = LorvexDate.parse(day), let cadence = domainCadence else {
      return true
    }
    switch cadence {
    case .daily, .weekly:
      return isHabitScheduledOnDay(cadence, date)
    case .monthly(let dayOfMonth):
      let reminderDay = effectiveMonthlyDay(
        dayOfMonth, year: date.ymd.year, month: date.ymd.month)
      return date.ymd.day >= reminderDay && periodMetDays == 0
    case .timesPerWeek(let count):
      return Int64(periodMetDays) < max(count, 1)
    }
  }

  /// Whether the habit counts in `day`'s review: it was due that day
  /// (``isDue(on:)``) or it was checked in that day, so a check-in made on a
  /// day the habit was not due is counted as kept, and a day it was not due is
  /// never counted against it. A day the user skipped the habit is excused: it
  /// is not counted, for or against. `completionsToday` and `isSkipped` are read
  /// against the day the habit was loaded for, so `day` is that day.
  public func isReviewed(on day: String) -> Bool {
    completionsToday > 0 || (isDue(on: day) && !isSkipped)
  }

  /// The habit's cadence as the domain type, or nil when its stored fields do
  /// not form a valid one (an unknown frequency type). A weekday outside
  /// 0...6 is dropped, which leaves a weekly habit unpinned.
  private var domainCadence: HabitCadence? {
    try? HabitCadence.fromFields(
      HabitFrequencyFields(
        frequencyType: frequencyType,
        weekdays: weekdays?.compactMap(WeekDay.init(rawValue:)),
        perPeriodTarget: Int64(perPeriodTarget ?? 1),
        dayOfMonth: dayOfMonth))
  }
}

extension Sequence where Element == LorvexHabit {
  /// The habits that belong on `day`'s list of open habits
  /// (``LorvexHabit/isListed(on:)``), in their order.
  public func listed(on day: String) -> [LorvexHabit] {
    filter { $0.isListed(on: day) }
  }

  /// The habits that count in `day`'s review (``LorvexHabit/isReviewed(on:)``),
  /// in their order.
  public func reviewed(on day: String) -> [LorvexHabit] {
    filter { $0.isReviewed(on: day) }
  }
}
