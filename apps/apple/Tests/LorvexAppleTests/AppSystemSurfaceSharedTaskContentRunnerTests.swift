import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func sharedSystemIntentRunnerMutatesTaskContentRemindersRecurrenceAndHierarchy() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Shared system content task", notes: "")
  let appended = try await LorvexSystemIntentRunner.appendToTaskBody(
    id: " \(task.id) ", text: " Shared system body append ", core: core)
  #expect(appended.notes.contains("Shared system body append"))
  let reminded = try await LorvexSystemIntentRunner.setTaskReminders(
    id: task.id, remindersText: "2026-05-23T09:00:00Z\n2026-05-24T10:00:00Z", core: core)
  #expect(reminded.reminders.count == 2)
  let reminderProbe = try await core.createTask(title: "Shared system reminder probe", notes: "")
  let singleReminderAdded = try await LorvexSystemIntentRunner.addTaskReminder(
    taskID: " \(reminderProbe.id) ", reminderAt: " 2030-05-23T17:00:00Z ", core: core)
  let singleReminder = try #require(singleReminderAdded.reminders.last)
  // Stored reminder instants carry millisecond precision.
  #expect(singleReminder.reminderAt == "2030-05-23T17:00:00.000Z")
  let upcomingReminders = try await LorvexSystemIntentRunner.readUpcomingTaskReminders(
    hoursAhead: 40_000, limit: 10, core: core)
  #expect(upcomingReminders.map(\.id).contains(singleReminder.id))
  let removedSingleReminder = try await LorvexSystemIntentRunner.removeTaskReminder(
    taskID: reminderProbe.id, reminderID: " \(singleReminder.id) ", core: core)
  #expect(!removedSingleReminder.reminders.contains { $0.id == singleReminder.id })
  let recurrenceSet = try await LorvexSystemIntentRunner.setTaskRecurrence(
    taskID: task.id, frequency: .daily, interval: 1, weekdaysText: nil, until: " 2026-07-01 ",
    count: nil, core: core)
  #expect(
    recurrenceSet.recurrence == TaskRecurrenceRule(freq: .daily, interval: 1, until: "2026-07-01"))
  let recurrenceSkipped = try await LorvexSystemIntentRunner.addTaskRecurrenceException(
    taskID: " \(task.id) ", exceptionDate: " 2026-06-02 ", core: core)
  #expect(recurrenceSkipped.recurrenceExceptions == ["2026-06-02"])
  let recurrenceRestored = try await LorvexSystemIntentRunner.removeTaskRecurrenceException(
    taskID: task.id, exceptionDate: "2026-06-02", core: core)
  #expect(recurrenceRestored.recurrenceExceptions.isEmpty)
  let recurrenceRemoved = try await LorvexSystemIntentRunner.removeTaskRecurrence(
    taskID: task.id, core: core)
  #expect(recurrenceRemoved.recurrence == nil)
  let checklistAdded = try await LorvexSystemIntentRunner.addTaskChecklistItem(
    taskID: task.id, text: " Shared checklist item ", core: core)
  let item = try #require(checklistAdded.checklistItems.last)
  let checklistToggled = try await LorvexSystemIntentRunner.toggleTaskChecklistItem(
    itemID: item.id, completed: true, core: core)
  #expect(checklistToggled.checklistItems.first { $0.id == item.id }?.completedAt != nil)
  let checklistUpdated = try await LorvexSystemIntentRunner.updateTaskChecklistItem(
    itemID: item.id, text: " Shared checklist item updated ", core: core)
  #expect(
    checklistUpdated.checklistItems.first { $0.id == item.id }?.text
      == "Shared checklist item updated")
  let checklistRemoved = try await LorvexSystemIntentRunner.removeTaskChecklistItem(
    itemID: item.id, core: core)
  #expect(!checklistRemoved.checklistItems.contains { $0.id == item.id })
}
