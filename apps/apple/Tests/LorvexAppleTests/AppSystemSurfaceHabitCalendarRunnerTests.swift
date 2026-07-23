import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func taskIntentRunnerHandlesHabitAndCalendarActions() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(title: "Shortcut calendar linked task", notes: "")
  let habit = try await LorvexTaskIntentRunner.createHabit(
    name: "  Shortcut habit  ",
    cue: "  After coffee  ",
    targetCount: 2,
    core: core
  )
  #expect(habit.name == "Shortcut habit")
  #expect(habit.cue == "After coffee")
  #expect(habit.targetCount == 2)
  let updatedHabit = try await LorvexTaskIntentRunner.updateHabit(
    id: " \(habit.id) ",
    name: "  Renamed shortcut habit  ",
    cue: "  After lunch  ",
    targetCount: 3,
    core: core
  )
  #expect(updatedHabit.id == habit.id)
  #expect(updatedHabit.name == "Renamed shortcut habit")
  #expect(updatedHabit.cue == "After lunch")
  #expect(updatedHabit.targetCount == 3)

  let completedHabit = try await LorvexTaskIntentRunner.completeHabit(
    id: " \(habit.id) ",
    date: " 2026-05-24 ",
    core: core
  )
  #expect(completedHabit.id == habit.id)
  #expect(completedHabit.completionsToday == 1)
  let stats = try await LorvexTaskIntentRunner.readHabitStats(id: " \(habit.id) ", core: core)
  #expect(stats.totalCompletions >= 1)
  let batchHabits = try await LorvexTaskIntentRunner.batchCompleteHabits(
    habitIDs: [habit.id],
    date: " 2026-05-25 ",
    core: core
  )
  #expect(batchHabits.habits.first { $0.id == habit.id }?.totalCompletions ?? 0 >= 2)
  let completions = try await LorvexTaskIntentRunner.readHabitCompletions(
    id: " \(habit.id) ",
    from: " 2026-05-25 ",
    to: " 2026-05-25 ",
    core: core
  )
  #expect(completions.completions.count == 1)
  let policy = try await LorvexTaskIntentRunner.upsertHabitReminderPolicy(
    id: " \(habit.id) ",
    reminderTime: " 18:30 ",
    enabled: true,
    core: core
  )
  #expect(policy.reminderTime == "18:30")
  let policies = try await LorvexTaskIntentRunner.readHabitReminderPolicies(
    id: " \(habit.id) ",
    core: core
  )
  #expect(policies.map(\.id).contains(policy.id))

  let resetHabit = try await LorvexTaskIntentRunner.uncompleteHabit(
    id: " \(habit.id) ",
    date: " 2026-05-24 ",
    core: core
  )
  #expect(resetHabit.id == habit.id)
  #expect(resetHabit.completionsToday == 0)
  let deletedHabitID = try await LorvexTaskIntentRunner.deleteHabit(
    id: " \(habit.id) ",
    core: core
  )
  #expect(deletedHabitID == habit.id)
  #expect(!((try await core.loadHabits(date: "2026-05-24")).habits.contains {
    $0.id == habit.id
  }))

  let event = try await LorvexTaskIntentRunner.createCalendarEvent(
    title: "  Shortcut event  ",
    startDate: " 2026-05-24 ",
    startTime: " 09:00 ",
    endTime: " 09:30 ",
    allDay: false,
    location: "  Desk  ",
    notes: "  Plan from Shortcuts  ",
    core: core
  )
  #expect(event.title == "Shortcut event")
  #expect(event.startDate == "2026-05-24")
  #expect(event.startTime == "09:00")
  #expect(event.endTime == "09:30")
  #expect(event.location == "Desk")
  let updatedEvent = try await LorvexTaskIntentRunner.updateCalendarEvent(
    id: " \(event.id) ",
    title: "  Updated shortcut event  ",
    startDate: " 2026-05-25 ",
    startTime: " 10:00 ",
    endTime: " 10:45 ",
    allDay: false,
    location: "  Room 2  ",
    notes: "  Revised from Shortcuts  ",
    core: core
  )
  #expect(updatedEvent.id == event.id)
  #expect(updatedEvent.title == "Updated shortcut event")
  #expect(updatedEvent.startDate == "2026-05-25")
  #expect(updatedEvent.startTime == "10:00")
  #expect(updatedEvent.endTime == "10:45")
  #expect(updatedEvent.location == "Room 2")
  let timeline = try await LorvexTaskIntentRunner.readCalendarTimeline(
    from: " 2026-05-25 ",
    to: " 2026-05-25 ",
    core: core
  )
  #expect(timeline.events.contains { $0.id == event.id })
  let matchingEvents = try await LorvexTaskIntentRunner.searchCalendarEvents(
    query: " shortcut ",
    from: " 2026-05-25 ",
    to: " 2026-05-25 ",
    limit: 5,
    core: core
  )
  #expect(matchingEvents.map(\.id).contains(event.id))
  // Provider links reference the EventKit provider mirror, not Lorvex-owned
  // canonical events, and require the scope enabled + refreshed. Ingest a
  // mirrored provider event first — the same state a real EventKit refresh
  // leaves behind.
  _ = try await core.setPreference(
    key: PreferenceKeys.devCalendarAiAccessMode,
    value: CalendarAiAccessMode.fullDetails.asString)
  _ = try core.ingestEventKitEvents(
    EventKitIngest.providerRows(
      from: [
        EventKitFetchedEvent(
          key: "ek-shortcut-1", title: "Mirrored standup", notes: nil,
          startDate: "2026-05-25", startTime: "09:00", endDate: "2026-05-25",
          endTime: "09:15", allDay: false, location: nil, timezone: nil)
      ],
      scope: "device", accessMode: .fullDetails),
    builtAtMode: .fullDetails, windowStart: "2026-05-25", windowEnd: "2026-05-25")
  let providerEventID = "ek-shortcut-1"
  let linkedEventTimelineID = "eventkit:device:ek-shortcut-1"
  let eventLink = try await LorvexTaskIntentRunner.linkTaskToProviderEvent(
    taskID: " \(created.id) ",
    providerEventID: " \(providerEventID) ",
    providerSource: " eventkit ",
    core: core
  )
  #expect(eventLink.taskID == created.id)
  #expect(eventLink.providerEventID == providerEventID)
  let linkedEvents = try await LorvexTaskIntentRunner.readLinkedEventsForTask(
    taskID: " \(created.id) ",
    core: core
  )
  #expect(linkedEvents.map(\.id).contains(linkedEventTimelineID))
  let linkedTasks = try await LorvexTaskIntentRunner.readLinkedTasksForEvent(
    eventID: " \(linkedEventTimelineID) ",
    core: core
  )
  #expect(linkedTasks.map(\.id).contains(created.id))
  try await LorvexTaskIntentRunner.unlinkTaskFromProviderEvent(
    taskID: " \(created.id) ",
    providerEventID: " \(providerEventID) ",
    core: core
  )
  #expect(
    try await LorvexTaskIntentRunner.readLinkedTasksForEvent(
      eventID: linkedEventTimelineID, core: core
    ) == [])
  let deletedEventID = try await LorvexTaskIntentRunner.deleteCalendarEvent(
    id: " \(event.id) ",
    core: core
  )
  #expect(deletedEventID == event.id)
  #expect(!((try await core.loadCalendarTimeline(from: "2026-05-25", to: "2026-05-25")).events
    .contains { $0.id == event.id }))
}
