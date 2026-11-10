import Foundation
import LorvexCore

extension AppStore {
  /// Snooze the selected task until `date` — a storage-frame day — by writing
  /// its `available_from`, which hides it from the day surfaces (Today,
  /// Upcoming, the open list) until that day arrives. Distinct from Defer, which
  /// pushes `planned_date`; snoozing leaves the planned day untouched. Inert for
  /// completed / cancelled tasks.
  func snoozeSelectedTask(until date: Date) async {
    guard let id = selectedTask?.id else { return }
    await snoozeTask(id: id, until: date)
  }

  /// Snooze a specific task until `date` by writing `available_from` alone, so
  /// every other field keeps the value stored when the write lands, including
  /// one another process changed after the status check read the task. Used by
  /// the row context menu (`snoozeTask(id:until:)`) and the detail actions menu
  /// (via ``snoozeSelectedTask(until:)``). Inert for resolved (completed /
  /// cancelled) tasks.
  func snoozeTask(id: LorvexTask.ID, until date: Date) async {
    await perform {
      let task = try await core.loadTask(id: id)
      guard !task.status.isResolved else { return }
      let updated = try await core.updateTask(TaskUpdateDraft(id: id, availableFrom: .set(date)))
      replaceTask(updated)
      let refreshed = try await core.loadToday()
      feedbackProvider.playFeedback(.taskDeferred)
      // The task slides out of the day surfaces into the Scheduled lane, so
      // animate the today snapshot the same way a defer does.
      lorvexAnimated(.snappy(duration: 0.18)) { today = refreshed }
      try await afterSelectedTaskMutation()
      syncSelectedTaskDraft()
    }
  }
}
