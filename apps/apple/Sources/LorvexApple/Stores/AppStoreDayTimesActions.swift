import Foundation
import LorvexCore

/// Today's schedule actions on today's times: suggesting times, accepting
/// or dismissing a suggestion, and clearing the day's times. Accepting and
/// clearing replace the times of the day's unfinished tasks in one core write
/// (``LorvexDayPlanningServicing/saveDayTimes(date:times:)``), and ⌘Z puts the
/// times back as they were.
extension AppStore {
  /// Suggested times for today's tasks, held in Today's schedule until the
  /// user accepts or dismisses them. Nothing is stored.
  func suggestDayTimes() async {
    await perform {
      let date = logicalTodayDateString
      let timed = try await core.unfinishedTaskTimes(on: date)
      let proposal = try await core.proposeDayTimes(date: date)
      todayStorage.timesWhenDayTimesWereSuggested = timed
      lorvexAnimated(.snappy(duration: 0.2)) { proposedDayTimes = proposal }
    }
  }

  func dismissSuggestedDayTimes() {
    lorvexAnimated(.snappy(duration: 0.2)) { proposedDayTimes = nil }
  }

  /// Defer the suggestion's tasks that did not fit to tomorrow, so a full
  /// day never ends in a dead-end "Won't fit" row. The rest of the
  /// suggestion stays under review; with nothing placed, it closes.
  func moveUnscheduledSuggestionToTomorrow() async {
    guard let proposal = proposedDayTimes, !proposal.unscheduled.isEmpty else { return }
    await moveTodayTasksToTomorrow(proposal.unscheduled.map(\.id))
    lorvexAnimated(.snappy(duration: 0.2)) {
      if proposal.placements.isEmpty {
        proposedDayTimes = nil
      } else {
        proposedDayTimes?.unscheduled = []
      }
    }
  }

  /// Save the suggestion under review as the day's times, for the day as it
  /// stands now: a time set since the suggestion was drawn is kept, and a task
  /// that has left the day's unfinished work is left out
  /// (``DayTimesProposal/timesToStore(timedWhenSuggested:timedNow:unfinishedToday:)``).
  /// A suggestion drawn for a day that has since ended is dropped.
  func acceptSuggestedDayTimes(undoManager: UndoManager?) async {
    guard let proposal = proposedDayTimes else { return }
    guard proposal.date == logicalTodayDateString else {
      dismissSuggestedDayTimes()
      return
    }
    let times: [LorvexTaskTime]
    do {
      let current = try await core.loadToday()
      times = proposal.timesToStore(
        timedWhenSuggested: todayStorage.timesWhenDayTimesWereSuggested,
        timedNow: try await core.unfinishedTaskTimes(on: proposal.date),
        unfinishedToday: Set((current.tasks + current.inProgressTasks).map(\.id)))
    } catch {
      await presentUserFacingError(error)
      return
    }
    await replaceDayTimes(
      date: proposal.date, with: times, undoManager: undoManager,
      actionName: TodayCalmCopy.undoSuggestedTimes)
  }

  /// Take the times off today's unfinished tasks. The tasks stay on today.
  func clearDayTimes(undoManager: UndoManager?) async {
    await replaceDayTimes(
      date: logicalTodayDateString, with: [], undoManager: undoManager,
      actionName: TodayCalmCopy.clearTimes)
  }

  /// Replace the times of `date`'s unfinished tasks with `times`, and register
  /// the times they had as the undo. The undo re-enters here with the two
  /// swapped, so redo works too. A suggestion under review is dismissed: the
  /// day it was drawn against has changed.
  func replaceDayTimes(
    date: String, with times: [LorvexTaskTime], undoManager: UndoManager?, actionName: String
  ) async {
    await perform {
      let previous = try await core.loadTimedTasks(from: date, through: date)
        .filter(\.status.isActionable)
        .compactMap { task in task.time(on: date).map { LorvexTaskTime(taskID: task.id, time: $0) } }
      _ = try await core.saveDayTimes(date: date, times: times)
      let updatedToday = try await core.loadToday()
      lorvexAnimated(.snappy(duration: 0.2)) {
        proposedDayTimes = nil
        today = updatedToday
      }
      if let undoManager {
        undoManager.registerUndo(withTarget: self) { store in
          Task { @MainActor in
            await store.replaceDayTimes(
              date: date, with: previous, undoManager: undoManager, actionName: actionName)
          }
        }
        undoManager.setActionName(actionName)
      }
      try await refreshCurrentCalendarTimeline()
      await republishSurfacesAfterLocalMutation()
    }
  }
}
