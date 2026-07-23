import LorvexCore
import SwiftUI

extension TasksView {
  /// The task IDs the Tasks surface actually shows, in display order — honoring
  /// the active priority filter, the table sort, and the section/disclosure
  /// toggles (open backlog, later, history). Drives shift-range selection and
  /// batch-selection pruning so they operate on the visible rows the user sees,
  /// not the full unfiltered pool.
  var visibleOrderedTaskIDs: [LorvexTask.ID] {
    if isTableMode {
      return tableVisibleTaskPool.map(\.id)
    }
    var tasks = visibleReviewQueueTasks
    if usesReviewQueuePreview && showOpenBacklog {
      tasks += visibleOpenBacklogTasks
    }
    if showLater {
      tasks += visibleDeferredTasks + visibleSomedayTasks
    }
    if showHistory {
      tasks += visibleCompletedTasks + visibleCancelledTasks
    }
    return tasks.map(\.id)
  }
}
