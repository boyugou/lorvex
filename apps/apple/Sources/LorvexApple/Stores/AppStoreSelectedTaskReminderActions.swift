import Foundation
import LorvexCore

extension AppStore {
  func addReminderToSelectedTask() async {
    guard let taskID = selectedTask?.id else { return }
    await perform {
      let reminderAt = Self.isoDateTimeFormatter.string(from: taskDetailReminderDate)
      let task = try await core.addTaskReminder(taskID: taskID, reminderAt: reminderAt)
      replaceTask(task)
      await rescheduleTodayTaskReminders()
      // Reminders render from `selectedTask` (refreshed by `replaceTask`); a
      // full draft force-sync here would only clobber unsaved title/notes edits.
      // Reset the picker to a fresh future default so a quick second Add doesn't
      // reuse the just-used (now slightly stale) time.
      resetTaskDetailReminderDate()
    }
  }

  func removeReminder(_ reminder: TaskReminder) async {
    guard let taskID = selectedTask?.id else { return }
    await perform {
      let task = try await core.removeTaskReminder(taskID: taskID, reminderID: reminder.id)
      replaceTask(task)
      await rescheduleTodayTaskReminders()
      // Reminders render from `selectedTask` (refreshed by `replaceTask`); a
      // full draft force-sync here would only clobber unsaved title/notes edits.
    }
  }
}
