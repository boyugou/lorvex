import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func sharedSystemIntentRunnerMutatesHabitsAndCalendarEvents() async throws {
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try await core.getSessionContext().date
  let habit = try await LorvexSystemIntentRunner.createHabit(
    name: "  Shared system habit  ", cue: "  After standup  ", targetCount: nil, core: core)
  #expect(habit.name == "Shared system habit")
  #expect(habit.cue == "After standup")
  #expect(habit.targetCount == 1)
  let updatedHabit = try await LorvexSystemIntentRunner.updateHabit(
    id: " \(habit.id) ", name: "  Renamed system habit  ", cue: "  Before shutdown  ",
    targetCount: 2, core: core)
  #expect(updatedHabit.id == habit.id)
  #expect(updatedHabit.name == "Renamed system habit")
  #expect(updatedHabit.cue == "Before shutdown")
  #expect(updatedHabit.targetCount == 2)
  let completedHabit = try await LorvexSystemIntentRunner.completeHabit(
    id: " \(habit.id) ", date: nil, core: core)
  #expect(completedHabit.id == habit.id)
  #expect(completedHabit.completionsToday == 1)
  let resetHabit = try await LorvexSystemIntentRunner.uncompleteHabit(
    id: " \(habit.id) ", date: nil, core: core)
  #expect(resetHabit.id == habit.id)
  #expect(resetHabit.completionsToday == 0)
  let deletedHabitID = try await LorvexSystemIntentRunner.deleteHabit(
    id: " \(habit.id) ", core: core)
  #expect(deletedHabitID == habit.id)
  #expect(!((try await core.loadHabits(date: logicalDay)).habits.contains { $0.id == habit.id }))

  let event = try await LorvexSystemIntentRunner.createCalendarEvent(
    title: "  Shared system event  ", startDate: nil, startTime: nil, endTime: nil, allDay: true,
    location: "   ", notes: nil, core: core)
  #expect(event.title == "Shared system event")
  #expect(event.startDate == logicalDay)
  #expect(event.allDay)
  #expect(event.location == nil)
  let updatedEvent = try await LorvexSystemIntentRunner.updateCalendarEvent(
    id: " \(event.id) ", title: "  Updated system event  ", startDate: " 2026-05-23 ",
    startTime: " 11:00 ", endTime: " 11:30 ", allDay: false, location: "  Conference room  ",
    notes: "  Revised through shared runner  ", core: core)
  #expect(updatedEvent.id == event.id)
  #expect(updatedEvent.title == "Updated system event")
  #expect(updatedEvent.startDate == "2026-05-23")
  #expect(updatedEvent.startTime == "11:00")
  #expect(updatedEvent.endTime == "11:30")
  #expect(updatedEvent.location == "Conference room")
  let deletedEventID = try await LorvexSystemIntentRunner.deleteCalendarEvent(
    id: " \(event.id) ", core: core)
  #expect(deletedEventID == event.id)
  #expect(
    !((try await core.loadCalendarTimeline(from: "2026-05-23", to: "2026-05-23")).events.contains {
      $0.id == event.id
    }))
}
