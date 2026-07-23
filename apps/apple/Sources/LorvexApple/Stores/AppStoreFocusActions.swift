import Foundation
import LorvexCore
import SwiftUI

extension AppStore {
  /// Adds multiple tasks to the current focus plan in one core call.
  ///
  /// A multi-item drop routes through this single `addToCurrentFocus` write so it
  /// serializes correctly, rather than spawning one Task per ref where each would
  /// overwrite the others' `currentFocus` result.
  func addTasksToCurrentFocus(ids: [LorvexTask.ID]) async {
    guard !ids.isEmpty else { return }
    await perform {
      let updatedFocus = try await core.addToCurrentFocus(
        date: logicalTodayDateString,
        taskIDs: ids,
        briefing: currentFocus?.briefing,
        timezone: logicalTimezoneName
      )
      let updatedToday = try await core.loadToday()
      lorvexAnimated(.snappy(duration: 0.18)) {
        currentFocus = updatedFocus
        today = updatedToday
      }
      pruneFocusWorkspaceSelection()
      await republishSurfacesAfterLocalMutation()
    }
  }

  func focusSelectedTask() async {
    guard let id = selectedTask?.id else { return }
    await perform {
      let updatedFocus = try await core.addToCurrentFocus(
        date: logicalTodayDateString,
        taskIDs: [id],
        briefing: currentFocus?.briefing,
        timezone: logicalTimezoneName
      )
      let updatedToday = try await core.loadToday()
      lorvexAnimated(.snappy(duration: 0.18)) {
        currentFocus = updatedFocus
        today = updatedToday
      }
      pruneFocusWorkspaceSelection()
      await republishSurfacesAfterLocalMutation()
    }
  }

  func toggleSelectedTaskFocus() async {
    if selectedTaskIsFocused {
      await removeSelectedTaskFromFocus()
    } else {
      await focusSelectedTask()
    }
  }

  /// Toggle a specific task's focus membership from a list-row swipe, without
  /// touching `selectedTaskID` — swiping a row to focus it shouldn't yank the
  /// detail inspector onto that task.
  func toggleTaskFocus(_ task: LorvexTask) async {
    await perform {
      let updatedFocus: CurrentFocusPlan?
      if focusedTaskIDSet.contains(task.id) {
        updatedFocus = try await core.removeFromCurrentFocus(
          date: logicalTodayDateString,
          taskID: task.id
        )
      } else {
        updatedFocus = try await core.addToCurrentFocus(
          date: logicalTodayDateString,
          taskIDs: [task.id],
          briefing: currentFocus?.briefing,
          timezone: logicalTimezoneName
        )
      }
      let updatedToday = try await core.loadToday()
      lorvexAnimated(.snappy(duration: 0.18)) {
        currentFocus = updatedFocus
        today = updatedToday
      }
      pruneFocusWorkspaceSelection()
      await republishSurfacesAfterLocalMutation()
    }
  }

  func removeSelectedTaskFromFocus() async {
    guard let id = selectedTask?.id else { return }
    await perform {
      let updatedFocus = try await core.removeFromCurrentFocus(
        date: logicalTodayDateString,
        taskID: id
      )
      let updatedToday = try await core.loadToday()
      lorvexAnimated(.snappy(duration: 0.18)) {
        currentFocus = updatedFocus
        today = updatedToday
      }
      pruneFocusWorkspaceSelection()
      await republishSurfacesAfterLocalMutation()
    }
  }

  func clearCurrentFocus() async {
    await perform {
      let date = logicalTodayDateString
      currentFocus = try await core.clearCurrentFocus(date: date)
      // "Clear Focus Plan" wipes the day's whole plan, so delete the persisted
      // time-block schedule too — nilling only the in-memory copy let it reappear
      // from storage on the next load.
      try await core.clearFocusSchedule(date: date)
      focusSchedule = nil
      proposedFocusSchedule = nil
      today = try await core.loadToday()
      pruneFocusWorkspaceSelection()
      await republishSurfacesAfterLocalMutation()
    }
  }

  func addFocusWorkspaceSelectionToFocus() async {
    let ids =
      focusWorkspaceSelectedTasks
      .filter { !focusedTaskIDSet.contains($0.id) }
      .map(\.id)
    guard !ids.isEmpty else { return }

    await perform {
      let updatedFocus = try await core.addToCurrentFocus(
        date: logicalTodayDateString,
        taskIDs: ids,
        briefing: currentFocus?.briefing,
        timezone: logicalTimezoneName
      )
      let updatedToday = try await core.loadToday()
      lorvexAnimated(.snappy(duration: 0.18)) {
        currentFocus = updatedFocus
        today = updatedToday
      }
      pruneFocusWorkspaceSelection()
      await republishSurfacesAfterLocalMutation()
    }
  }

  func removeFocusWorkspaceSelectionFromFocus() async {
    let ids =
      focusWorkspaceSelectedTasks
      .filter { focusedTaskIDSet.contains($0.id) }
      .map(\.id)
    guard !ids.isEmpty else { return }

    await perform {
      var updatedFocus: CurrentFocusPlan?
      for id in ids {
        updatedFocus = try await core.removeFromCurrentFocus(
          date: logicalTodayDateString,
          taskID: id
        )
      }
      let updatedToday = try await core.loadToday()
      lorvexAnimated(.snappy(duration: 0.18)) {
        currentFocus = updatedFocus
        today = updatedToday
      }
      pruneFocusWorkspaceSelection()
      await republishSurfacesAfterLocalMutation()
    }
  }

  func pruneFocusWorkspaceSelection() {
    let visibleIDs = Set(focusSurfaceOrderedTasks.map(\.id))
    focusStorage.selectedTaskIDs.formIntersection(visibleIDs)
  }
}
