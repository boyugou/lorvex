import Foundation
import LorvexCore

/// The reviews' own reads: the habits as they stood on the reviewed day,
/// tomorrow's agenda for the review of today, and the week review's week
/// ahead and finished count per day.
extension MobileStore {
  /// The active habits with their completions on `date`, or nil when the read
  /// fails, so the page keeps what it shows.
  func loadReviewHabits(date: String) async -> [LorvexHabit]? {
    guard let snapshot = try? await core.loadHabits(date: date) else { return nil }
    return snapshot.habits.filter { !$0.archived }
  }

  /// Tomorrow's events and scheduled tasks, read for the day after the
  /// logical today; nil when a read fails. A tomorrow with nothing on it
  /// comes back as an empty day, which the page words as such.
  func loadTomorrowAgenda() async -> LorvexAgendaDay? {
    try? await LorvexAgendaDay.loadDay(after: logicalTodayString, from: core)
  }

  /// The seven days after today that have something on them, for the week
  /// review's look ahead; nil when the read fails.
  func loadWeekAheadAgenda() async -> [LorvexAgendaDay]? {
    try? await LorvexAgendaDay.loadWeek(after: logicalTodayString, from: core)
  }

  /// How many tasks were finished on each day of the week the review is
  /// viewing; nil when the read fails.
  func loadWeekShape() async -> LorvexWeekShape? {
    try? await LorvexWeekShape.load(
      endingOn: weeklyReviewAnchor ?? logicalTodayString, timeZone: logicalTimeZone, from: core)
  }
}
