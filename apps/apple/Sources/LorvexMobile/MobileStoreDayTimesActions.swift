import Foundation
import LorvexCore

/// The schedule's actions on today's times: suggesting times, using or
/// dismissing a suggestion, and clearing the day's times. Using and clearing
/// replace the times of the day's unfinished tasks in one core write
/// (``LorvexDayPlanningServicing/saveDayTimes(date:times:)``).
extension MobileStore {
  /// Suggested times for today's tasks, held in the schedule until the user
  /// uses or dismisses them. Nothing is stored.
  public func suggestDayTimes() async {
    guard !isSuggestingDayTimes, !isSavingDayTimes else { return }
    isSuggestingDayTimes = true
    defer { isSuggestingDayTimes = false }
    do {
      proposedDayTimes = try await core.proposeDayTimes(date: logicalTodayString)
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }

  public func dismissSuggestedDayTimes() {
    proposedDayTimes = nil
  }

  /// Defer the suggestion's tasks that did not fit to tomorrow, so a full
  /// day never ends in a dead-end "Won't fit" row. The rest of the
  /// suggestion stays under review; with nothing placed, it closes.
  public func moveUnscheduledSuggestionToTomorrow() async {
    guard let proposal = proposedDayTimes, !proposal.unscheduled.isEmpty else { return }
    guard await deferTasksToTomorrow(proposal.unscheduled.map(\.id)) else { return }
    if proposal.placements.isEmpty {
      proposedDayTimes = nil
    } else {
      proposedDayTimes?.unscheduled = []
    }
  }

  /// Save the suggestion under review as the day's times.
  public func useSuggestedDayTimes() async {
    guard let proposal = proposedDayTimes else { return }
    await replaceDayTimes(date: proposal.date, with: proposal.times)
  }

  /// Take the times off today's unfinished tasks. The tasks stay on today.
  public func clearDayTimes() async {
    await replaceDayTimes(date: logicalTodayString, with: [])
  }

  /// Replace the times of `date`'s unfinished tasks with `times`, then reload
  /// Today and refresh every loaded copy of a task whose time changed, so the
  /// calendar and the lists draw the new times. A suggestion under review is
  /// dismissed: the day it was drawn against has changed. The saving flag is
  /// released before the surface fan-out, which may wait on a sync cycle.
  func replaceDayTimes(date: String, with times: [LorvexTaskTime]) async {
    guard !isSavingDayTimes else { return }
    isSavingDayTimes = true
    // Loaded tasks timed on `date` before the save; any the save leaves out
    // lose their time.
    let previouslyTimed = Set(
      (snapshot.today.tasks + calendarScheduledTasks).filter { $0.time(on: date) != nil }.map(\.id))
    let timed: [LorvexTask]
    do {
      timed = try await core.saveDayTimes(date: date, times: times)
      proposedDayTimes = nil
      snapshot.today = try await core.loadToday()
      isSavingDayTimes = false
      errorMessage = nil
    } catch {
      isSavingDayTimes = false
      await presentUserFacingError(error)
      return
    }
    for task in timed { replaceKnownTask(task) }
    for id in previouslyTimed.subtracting(timed.map(\.id)) {
      if let task = try? await core.loadTask(id: id) { replaceKnownTask(task) }
    }
    invalidateTaskViews()
    await publishMobileSyncSurfaces()
  }
}
