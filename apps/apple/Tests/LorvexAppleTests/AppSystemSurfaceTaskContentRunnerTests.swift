import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func taskIntentRunnerHandlesTaskContentReminderRecurrenceAndHierarchyActions() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(title: "Shortcut content task", notes: "")
  let bodyAppended = try await LorvexTaskIntentRunner.appendToTaskBody(
    id: " \(created.id) ",
    text: " Shortcut body append ",
    core: core
  )
  #expect(bodyAppended.notes.contains("Shortcut body append"))

  let remindersSet = try await LorvexTaskIntentRunner.setTaskReminders(
    id: created.id,
    remindersText: "2026-05-23T09:00:00Z,\n2026-05-24T10:00:00Z",
    core: core
  )
  // Stored reminder instants carry millisecond precision.
  #expect(remindersSet.reminders.map(\.reminderAt) == [
    "2026-05-23T09:00:00.000Z",
    "2026-05-24T10:00:00.000Z",
  ])
  let singleReminderAdded = try await LorvexTaskIntentRunner.addTaskReminder(
    taskID: " \(created.id) ",
    reminderAt: " 2026-05-25T11:00:00Z ",
    core: core
  )
  let singleReminder = try #require(singleReminderAdded.reminders.last)
  #expect(singleReminder.reminderAt == "2026-05-25T11:00:00.000Z")
  let dueReminders = try await LorvexTaskIntentRunner.readDueTaskReminders(
    asOf: "2026-05-26T00:00:00Z",
    limit: 10,
    core: core
  )
  #expect(dueReminders.map(\.id).contains(singleReminder.id))
  let removedSingleReminder = try await LorvexTaskIntentRunner.removeTaskReminder(
    taskID: created.id,
    reminderID: " \(singleReminder.id) ",
    core: core
  )
  #expect(!removedSingleReminder.reminders.contains { $0.id == singleReminder.id })

  let recurrenceSet = try await LorvexTaskIntentRunner.setTaskRecurrence(
    taskID: created.id,
    frequency: .weekly,
    interval: 2,
    weekdaysText: "MO, WE",
    until: nil,
    count: nil,
    core: core
  )
  #expect(recurrenceSet.recurrence == TaskRecurrenceRule(
    freq: .weekly,
    interval: 2,
    byDay: ["MO", "WE"]
  ))
  let recurrenceSkipped = try await LorvexTaskIntentRunner.addTaskRecurrenceException(
    taskID: " \(created.id) ",
    exceptionDate: " 2026-06-01 ",
    core: core
  )
  #expect(recurrenceSkipped.recurrenceExceptions == ["2026-06-01"])
  let recurrenceRestored = try await LorvexTaskIntentRunner.removeTaskRecurrenceException(
    taskID: created.id,
    exceptionDate: "2026-06-01",
    core: core
  )
  #expect(recurrenceRestored.recurrenceExceptions.isEmpty)
  let recurrenceRemoved = try await LorvexTaskIntentRunner.removeTaskRecurrence(
    taskID: created.id,
    core: core
  )
  #expect(recurrenceRemoved.recurrence == nil)

  let checklistAdded = try await LorvexTaskIntentRunner.addTaskChecklistItem(
    taskID: created.id,
    text: " Confirm shortcut checklist ",
    core: core
  )
  let checklistItem = try #require(checklistAdded.checklistItems.last)
  #expect(checklistItem.text == "Confirm shortcut checklist")
  let checklistToggled = try await LorvexTaskIntentRunner.toggleTaskChecklistItem(
    itemID: checklistItem.id,
    completed: true,
    core: core
  )
  #expect(checklistToggled.checklistItems.first { $0.id == checklistItem.id }?.completedAt != nil)
  let checklistUpdated = try await LorvexTaskIntentRunner.updateTaskChecklistItem(
    itemID: checklistItem.id,
    text: " Confirm updated checklist ",
    core: core
  )
  #expect(checklistUpdated.checklistItems.first { $0.id == checklistItem.id }?.text == "Confirm updated checklist")
  let checklistRemoved = try await LorvexTaskIntentRunner.removeTaskChecklistItem(
    itemID: checklistItem.id,
    core: core
  )
  #expect(!checklistRemoved.checklistItems.contains { $0.id == checklistItem.id })
}
