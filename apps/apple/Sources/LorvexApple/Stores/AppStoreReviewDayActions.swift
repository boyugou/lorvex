import Foundation
import LorvexCore

/// The day review's own reads and its one task action: the habits as they
/// stood on the reviewed day, tomorrow's agenda for the review of today, and
/// planning the day's still-open tasks for tomorrow.
extension AppStore {
  /// What the day review page's own reads (``loadReviewHabits(date:)`` and
  /// ``loadTomorrowAgenda()``) follow; the page re-reads when it changes.
  var dayReviewReadKey: DayReviewReadKey {
    DayReviewReadKey(
      date: selectedReviewDate, evidence: dayReviewEvidence, taskRevision: taskDataGeneration)
  }

  /// What the week review page's own reads (``loadWeekAheadAgenda()`` and
  /// ``loadWeekShape()``) follow; the page re-reads when it changes.
  var weekReviewReadKey: WeekReviewReadKey {
    WeekReviewReadKey(review: weeklyReview, taskRevision: taskDataGeneration)
  }

  /// The active habits that count in `date`'s review
  /// (``LorvexHabit/isReviewed(on:)``), with their completions that day, or
  /// nil when the read fails, so the page keeps what it shows.
  func loadReviewHabits(date: String) async -> [LorvexHabit]? {
    guard let snapshot = try? await core.loadHabits(date: date) else { return nil }
    return snapshot.habits.filter { !$0.archived }.reviewed(on: date)
  }

  /// Tomorrow's events and scheduled tasks, read for the day after the
  /// logical today; nil when a read fails. A tomorrow with nothing on it
  /// comes back as an empty day, which the page words as such.
  func loadTomorrowAgenda() async -> LorvexAgendaDay? {
    try? await LorvexAgendaDay.loadDay(after: logicalTodayDateString, from: core)
  }

  /// The seven days after today that have something on them, for the week
  /// review's look ahead; nil when the read fails.
  func loadWeekAheadAgenda() async -> [LorvexAgendaDay]? {
    try? await LorvexAgendaDay.loadWeek(after: logicalTodayDateString, from: core)
  }

  /// How many tasks were finished on each day of the week the review is
  /// viewing; nil when the read fails.
  func loadWeekShape() async -> LorvexWeekShape? {
    try? await LorvexWeekShape.load(
      endingOn: weeklyReviewAnchor ?? logicalTodayDateString, timeZone: logicalTimeZone, from: core)
  }

  /// Plan `ids` for tomorrow from the day review, then reload what shows
  /// them, the review's evidence included.
  func moveReviewTasksToTomorrow(ids: [LorvexTask.ID]) async {
    guard !ids.isEmpty else { return }
    await perform {
      let updatedToday = try await core.batchDeferTasks(ids: ids, until: tomorrowDate())
      feedbackProvider.playFeedback(.taskDeferred)
      lorvexAnimated(.snappy(duration: 0.18)) { today = updatedToday }
      try await afterSelectedTaskMutation()
    }
  }
}
