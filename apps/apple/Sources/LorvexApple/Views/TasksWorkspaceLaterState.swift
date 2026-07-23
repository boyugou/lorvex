import LorvexCore
import SwiftUI

/// The "Later" lane derived state for the Tasks workspace: the priority-filtered
/// Deferred, Scheduled (defer-until / hidden), and Someday buckets that fold
/// under the Later disclosure, plus their combined count. Split out of
/// ``TasksWorkspaceState`` so the growing derived-state surface stays within the
/// per-file line budget.
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

  var visibleLaterTaskCount: Int {
    visibleDeferredTasks.count + visibleScheduledTasks.count + visibleSomedayTasks.count
  }
}
