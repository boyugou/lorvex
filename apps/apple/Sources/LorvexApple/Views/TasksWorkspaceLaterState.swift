import LorvexCore
import SwiftUI

/// The "Later" group's derived state for the Tasks workspace: the
/// priority-filtered Deferred, Snoozed (hidden until a date), and Someday
/// lanes, and the one flat run the Later fold shows.
extension TasksView {
  var visibleDeferredTasks: [LorvexTask] {
    byPriority(store.taskWorkspaceDeferredTasks)
  }

  var visibleScheduledTasks: [LorvexTask] {
    byPriority(store.taskWorkspaceScheduledTasks)
  }

  var visibleSomedayTasks: [LorvexTask] {
    byPriority(store.taskWorkspaceSomedayTasks)
  }

  /// The Later group as one flat run: deferred and snoozed tasks, which carry
  /// a date, before someday tasks, which do not. A task that sits in both
  /// dated lanes appears once.
  var visibleLaterTasks: [LorvexTask] {
    var seen = Set<LorvexTask.ID>()
    return (visibleDeferredTasks + visibleScheduledTasks + visibleSomedayTasks)
      .filter { seen.insert($0.id).inserted }
  }

  var visibleLaterTaskCount: Int {
    visibleLaterTasks.count
  }
}
