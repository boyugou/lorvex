import AppIntents
import Foundation
import LorvexCore
import Testing

@testable import LorvexSystemIntents

@Test
func checklistItemAndTaskReminderIdentifiersJoinTheTaskAndTheChild() {
  let item = LorvexChecklistItemEntity.identifier(taskID: "task-1", itemID: "item-1")
  #expect(item == "task-1/item-1")
  #expect(LorvexChecklistItemEntity.components(of: item)?.taskID == "task-1")
  #expect(LorvexChecklistItemEntity.components(of: item)?.itemID == "item-1")
  #expect(LorvexChecklistItemEntity.components(of: "item-1") == nil)
  #expect(LorvexChecklistItemEntity.components(of: "/item-1") == nil)
  #expect(LorvexChecklistItemEntity.components(of: "task-1/") == nil)
  #expect(LorvexChecklistItemEntity.components(of: "a/b/c") == nil)

  let reminder = LorvexTaskReminderEntity.identifier(taskID: "task-1", reminderID: "rem-1")
  #expect(LorvexTaskReminderEntity.components(of: reminder)?.taskID == "task-1")
  #expect(LorvexTaskReminderEntity.components(of: reminder)?.reminderID == "rem-1")
  #expect(LorvexTaskReminderEntity.components(of: "rem-1") == nil)
}

@Test
func checklistItemPickerOffersItemsOfTasksStillInPlayAndFindsSavedOnes() async throws {
  let core = try await makeSeededInMemoryCore()
  let trip = try await core.createTask(title: "Pack for the trip", notes: "")
  _ = try await core.addTaskChecklistItem(taskID: trip.id, text: "Passport")
  let packed = try await core.addTaskChecklistItem(taskID: trip.id, text: "Charger")
  let errand = try await core.createTask(title: "Finished errand", notes: "")
  let closed = try await core.addTaskChecklistItem(taskID: errand.id, text: "Receipt")
  _ = try await core.completeTask(id: errand.id)

  let suggested = try await LorvexChecklistItemEntityQuery.suggestedEntities(core: core)
  let tripItems = suggested.filter { $0.taskID == trip.id }
  #expect(tripItems.map(\.text) == ["Passport", "Charger"])
  #expect(tripItems.allSatisfy { $0.taskTitle == "Pack for the trip" && !$0.completed })
  // A finished task's checklist is not offered.
  #expect(!suggested.contains { $0.taskID == errand.id })

  // A saved shortcut finds its item by reading the item's own task, whatever
  // that task's status, and skips identifiers that no longer name an item.
  let charger = try #require(packed.checklistItems.first { $0.text == "Charger" })
  let receipt = try #require(closed.checklistItems.first { $0.text == "Receipt" })
  let resolved = try await LorvexChecklistItemEntityQuery.entities(
    for: [
      LorvexChecklistItemEntity.identifier(taskID: trip.id, itemID: charger.id),
      LorvexChecklistItemEntity.identifier(taskID: errand.id, itemID: receipt.id),
      "\(trip.id)/missing-item",
      "not-an-identifier",
    ],
    core: core)
  #expect(resolved.map(\.text) == ["Charger", "Receipt"])

  let matches = try await LorvexChecklistItemEntityQuery.entities(
    matching: "pack for", core: core)
  #expect(matches.map(\.text) == ["Passport", "Charger"])
}

@Test
func taskReminderPickerOffersUpcomingRemindersInTheConfiguredZone() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Call the dentist", notes: "")
  let fireAt = LorvexDateFormatters.iso8601.string(from: Date().addingTimeInterval(3 * 86_400))
  let withReminder = try await core.addTaskReminder(taskID: task.id, reminderAt: fireAt)
  let reminder = try #require(withReminder.reminders.first)

  let suggested = try await LorvexTaskReminderEntityQuery.suggestedEntities(core: core)
  let entity = try #require(suggested.first { $0.reminderID == reminder.id })
  #expect(entity.taskID == task.id)
  #expect(entity.taskTitle == "Call the dentist")
  #expect(entity.timeZoneIdentifier == (try await core.getSessionContext().timezone))

  let resolved = try await LorvexTaskReminderEntityQuery.entities(
    for: [entity.id, "\(task.id)/missing-reminder"], core: core)
  #expect(resolved.map(\.reminderID) == [reminder.id])

  let matches = try await LorvexTaskReminderEntityQuery.entities(matching: "dentist", core: core)
  #expect(matches.map(\.reminderID) == [reminder.id])
}

@Test
func habitReminderPickerListsRemindersHabitByHabitThenByTime() async throws {
  let core = try await makeSeededInMemoryCore()
  let walk = try await core.createHabit(name: "Walk", cue: nil, targetCount: 1)
  let read = try await core.createHabit(name: "Read", cue: nil, targetCount: 1)
  for (habit, time, enabled) in [(walk, "18:00", true), (read, "21:30", false), (walk, "07:00", true)] {
    _ = try await core.upsertHabitReminderPolicy(
      id: habit.id,
      policy: HabitReminderPolicy(
        id: "", habitID: habit.id, habitName: habit.name, reminderTime: time, enabled: enabled,
        createdAt: "", updatedAt: ""))
  }

  let suggested = try await LorvexHabitReminderEntityQuery.suggestedEntities(core: core)
    .filter { [walk.id, read.id].contains($0.habitID) }
  #expect(suggested.map(\.habitName) == ["Read", "Walk", "Walk"])
  #expect(suggested.map(\.reminderTime) == ["21:30", "07:00", "18:00"])
  #expect(suggested.map(\.enabled) == [false, true, true])

  let resolved = try await LorvexHabitReminderEntityQuery.entities(
    for: [suggested[2].id, "missing-policy"], core: core)
  #expect(resolved.map(\.reminderTime) == ["18:00"])

  let matches = try await LorvexHabitReminderEntityQuery.entities(matching: "wal", core: core)
  #expect(matches.filter { $0.habitID == walk.id }.map(\.reminderTime) == ["07:00", "18:00"])
  #expect(!matches.contains { $0.habitID == read.id })
}

@Test
func habitReminderIntentsAddRetimeAndTurnOffOneReminder() async throws {
  try await withIsolatedAppIntentDatabase {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let habit = try await core.createHabit(name: "Stretch", cue: nil, targetCount: 1)
    let calendar = Calendar.current
    let sevenThirty = try #require(calendar.date(bySettingHour: 7, minute: 30, second: 0, of: .now))
    let nineFifteen = try #require(calendar.date(bySettingHour: 9, minute: 15, second: 0, of: .now))

    _ = try await AddLorvexHabitReminderIntent(
      habit: LorvexHabitEntity(habit: habit), reminderTime: sevenThirty
    ).perform()
    let added = try await core.getHabitReminderPolicies(id: habit.id)
    #expect(added.map(\.reminderTime) == ["07:30"])
    #expect(added.map(\.enabled) == [true])

    // Turning it off keeps its time.
    _ = try await UpdateLorvexHabitReminderIntent(
      reminder: LorvexHabitReminderEntity(policy: added[0]), enabled: false
    ).perform()
    let off = try await core.getHabitReminderPolicies(id: habit.id)
    #expect(off.map(\.reminderTime) == ["07:30"])
    #expect(off.map(\.enabled) == [false])

    // Moving it keeps it off, and edits the same reminder rather than adding one.
    _ = try await UpdateLorvexHabitReminderIntent(
      reminder: LorvexHabitReminderEntity(policy: off[0]), reminderTime: nineFifteen
    ).perform()
    let moved = try await core.getHabitReminderPolicies(id: habit.id)
    #expect(moved.map(\.id) == [added[0].id])
    #expect(moved.map(\.reminderTime) == ["09:15"])
    #expect(moved.map(\.enabled) == [false])
  }
}

@Test
func updateTaskIntentReplacesAndClearsDependenciesFromPickedTasks() async throws {
  try await withIsolatedAppIntentDatabase {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let task = try await core.createTask(title: "Ship the release", notes: "")
    let tests = try await core.createTask(title: "Run the tests", notes: "")
    let notes = try await core.createTask(title: "Write the notes", notes: "")

    _ = try await UpdateLorvexTaskIntent(
      task: LorvexTaskEntity(task: task),
      dependsOn: [LorvexTaskEntity(task: tests), LorvexTaskEntity(task: notes)]
    ).perform()
    #expect(Set(try await core.loadTask(id: task.id).dependsOn) == [tests.id, notes.id])

    // Leaving the list empty keeps the dependencies; the switch clears them.
    _ = try await UpdateLorvexTaskIntent(
      task: LorvexTaskEntity(task: task), title: "Ship the 1.0 release"
    ).perform()
    #expect(Set(try await core.loadTask(id: task.id).dependsOn) == [tests.id, notes.id])
    _ = try await UpdateLorvexTaskIntent(
      task: LorvexTaskEntity(task: task), removesDependencies: true
    ).perform()
    #expect(try await core.loadTask(id: task.id).dependsOn.isEmpty)
  }
}
