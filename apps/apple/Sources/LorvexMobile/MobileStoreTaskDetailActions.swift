import Foundation
import LorvexCore

extension MobileStore {
  public func toggleChecklistItem(_ item: TaskChecklistItem) async {
    await mutateTaskReturningTask(id: item.taskID) {
      try await core.toggleTaskChecklistItem(
        itemID: item.id,
        completed: item.completedAt == nil
      )
    }
  }

  public func addChecklistItem(taskID: LorvexTask.ID, text: String) async -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return await mutateTaskReturningTask(id: taskID) {
      try await core.addTaskChecklistItem(taskID: taskID, text: trimmed)
    }
  }

  public func removeChecklistItem(_ item: TaskChecklistItem) async -> Bool {
    await mutateTaskReturningTask(id: item.taskID) {
      try await core.removeTaskChecklistItem(itemID: item.id)
    }
  }

  public func addReminder(taskID: LorvexTask.ID, date: Date) async -> Bool {
    let reminderAt = LorvexDateFormatters.iso8601.string(from: date)
    return await mutateTaskReturningTask(id: taskID) {
      try await core.addTaskReminder(taskID: taskID, reminderAt: reminderAt)
    }
  }

  public func removeReminder(taskID: LorvexTask.ID, reminder: TaskReminder) async -> Bool {
    await mutateTaskReturningTask(id: taskID) {
      try await core.removeTaskReminder(taskID: taskID, reminderID: reminder.id)
    }
  }

  public func saveTaskEditDraft(_ draft: MobileTaskEditDraft) async -> Bool {
    guard draft.canSave else { return false }
    return await mutateTaskReturningTask(id: draft.id) {
      try await core.updateTask(draft.coreUpdateDraft)
    }
  }
}
