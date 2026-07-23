import Foundation
import LorvexCore

extension AppStore {
  /// Started tasks for Today's pinned "In Progress" section, after the search
  /// filter.
  var filteredInProgressTodayTasks: [LorvexTask] {
    filterTasks(inProgressTodayTasks)
  }

  var filteredFocusedTasks: [LorvexTask] {
    filterTasks(focusedTasks)
  }

  var filteredRemainingTodayTasks: [LorvexTask] {
    filterTasks(remainingTodayTasks)
  }

  /// True when the Today workspace renders at least one task row after the
  /// active search filter. The Today empty state must key off this, not
  /// `today.tasks`: a focused task can be scheduled for another day (so absent
  /// from `today.tasks` yet shown in the Focus section), and a today task can
  /// resolve into neither partition — both cases make `today.tasks.isEmpty` the
  /// wrong signal for "nothing is on screen."
  var hasVisibleTodayTasks: Bool {
    !filteredInProgressTodayTasks.isEmpty
      || !filteredFocusedTasks.isEmpty
      || !filteredRemainingTodayTasks.isEmpty
  }

  var filteredScheduledTasks: [LorvexTask] {
    filterTasks(scheduledTasks)
  }

  var filteredSelectedListTasks: [LorvexTask] {
    filterTasks(selectedListDetail?.tasks ?? [])
  }

  func filterTasks(_ tasks: [LorvexTask]) -> [LorvexTask] {
    let query = trimmedSearchText
    guard !query.isEmpty else { return tasks }
    return tasks.filter { task in
      task.matchesSearch(query)
    }
  }
}
