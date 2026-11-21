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
      date: selectedReviewDate, evidence: dayReviewEvidence, taskRevision: taskDataGeneration,
      inboundRevision: reviewReadGeneration)
  }

  /// What the week review page's own reads (``loadWeekAheadAgenda()`` and
  /// ``loadWeekShape()``) follow; the page re-reads when it changes.
  var weekReviewReadKey: WeekReviewReadKey {
    WeekReviewReadKey(
      review: weeklyReview, taskRevision: taskDataGeneration, inboundRevision: reviewReadGeneration)
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

  func arrangeReviewTasks(_ tasks: [ReviewTaskSummary], reviewedOn day: String,
    destination: ReviewTaskDestination, undoManager: UndoManager?) async {
    guard selectedReviewDate == day, dailyReviewIsEditable(date: day) else { return }
    await performTaskArrangement(undoManager: undoManager) {
      try await self.core.arrangeReviewTasks(tasks, reviewedOn: day, destination: destination)
    }
  }

  func moveTodayOverflow(_ tasks: [ReviewTaskSummary], on day: String, undoManager: UndoManager?) async {
    guard day == logicalTodayDateString else { return }
    await performTaskArrangement(undoManager: undoManager) {
      try await self.core.moveTodayOverflow(tasks, on: day)
    }
  }

  private func performTaskArrangement(undoManager: UndoManager?, move: () async throws -> [ReviewTaskChange]) async {
    await perform {
      let changes = try await move()
      if !changes.isEmpty {
        registerReviewUndo(changes, undo: true, manager: undoManager)
        feedbackProvider.playFeedback(.taskDeferred)
      }
      today = try await core.loadToday()
      try await afterSelectedTaskMutation()
    }
  }

  private func registerReviewUndo(_ changes: [ReviewTaskChange], undo: Bool, manager: UndoManager?) {
    guard let manager else { return }
    manager.registerUndo(withTarget: self) { [weak manager] store in
      MainActor.assumeIsolated {
        store.registerReviewUndo(changes, undo: !undo, manager: manager)
        Task { @MainActor in
          await store.perform {
            try await store.core.restoreReviewTasks(changes, undo: undo)
            store.today = try await store.core.loadToday()
            try await store.afterSelectedTaskMutation()
          }
        }
      }
    }
    manager.setActionName(Self.planTaskTitle)
  }
}
