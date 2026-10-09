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

@Test
func sharedSystemIntentCalendarEventsKeepTheTimesTheyAreGiven() async throws {
  let core = try await makeSeededInMemoryCore()

  // A start time makes the event timed even with All Day left on, its default.
  let timed = try await LorvexSystemIntentRunner.createCalendarEvent(
    title: "Dentist", startDate: "2026-05-23", startTime: "14:00", endTime: "15:00",
    allDay: true, location: nil, notes: nil, core: core)
  #expect(!timed.allDay)
  #expect(timed.startTime == "14:00")
  #expect(timed.endTime == "15:00")
  #expect((timed.endDate ?? timed.startDate) == "2026-05-23")

  // An end time earlier than the start time ends on the next day.
  let overnight = try await LorvexSystemIntentRunner.createCalendarEvent(
    title: "Night shift", startDate: "2026-05-23", startTime: "22:00", endTime: "06:00",
    allDay: false, location: nil, notes: nil, core: core)
  #expect(overnight.startDate == "2026-05-23")
  #expect(overnight.startTime == "22:00")
  #expect(overnight.endDate == "2026-05-24")
  #expect(overnight.endTime == "06:00")

  // With no start time, All Day stays all-day and drops a lone end time.
  let offsite = try await LorvexSystemIntentRunner.createCalendarEvent(
    title: "Offsite", startDate: "2026-05-25", startTime: nil, endTime: "10:00",
    allDay: true, location: nil, notes: nil, core: core)
  #expect(offsite.allDay)
  #expect(offsite.startTime == nil)

  // A start time given to an all-day event makes it timed unless All Day is
  // set in the same update.
  let retimed = try await LorvexSystemIntentRunner.updateCalendarEvent(
    id: offsite.id, title: nil, startDate: nil, startTime: "09:30", endTime: "11:00",
    allDay: nil, location: nil, notes: nil, core: core)
  #expect(!retimed.allDay)
  #expect(retimed.startTime == "09:30")
  #expect(retimed.endTime == "11:00")

  // An update that names no time leaves the event's timing alone.
  let renamed = try await LorvexSystemIntentRunner.updateCalendarEvent(
    id: timed.id, title: "Dentist visit", startDate: nil, startTime: nil, endTime: nil,
    allDay: nil, location: nil, notes: nil, core: core)
  #expect(renamed.title == "Dentist visit")
  #expect(!renamed.allDay)
  #expect(renamed.startTime == "14:00")
  #expect(renamed.endTime == "15:00")
}

@Test
func sharedSystemIntentCalendarUpdatesKeepNightAndMultiDayEventsWhole() async throws {
  let core = try await makeSeededInMemoryCore()

  // New times whose end comes before the start end on the next day.
  let meeting = try await LorvexSystemIntentRunner.createCalendarEvent(
    title: "Meeting", startDate: "2026-05-23", startTime: "09:00", endTime: "10:00",
    allDay: false, location: nil, notes: nil, core: core)
  let nightShift = try await LorvexSystemIntentRunner.updateCalendarEvent(
    id: meeting.id, title: nil, startDate: nil, startTime: "22:00", endTime: "06:00",
    allDay: nil, location: nil, notes: nil, core: core)
  #expect(nightShift.startDate == "2026-05-23")
  #expect(nightShift.endDate == "2026-05-24")
  #expect(nightShift.endTime == "06:00")

  // Daytime times bring a night event back within one day.
  let daytime = try await LorvexSystemIntentRunner.updateCalendarEvent(
    id: meeting.id, title: nil, startDate: nil, startTime: "09:00", endTime: "10:00",
    allDay: nil, location: nil, notes: nil, core: core)
  #expect((daytime.endDate ?? daytime.startDate) == "2026-05-23")

  // Moving a night event's date keeps it ending the morning after.
  _ = try await LorvexSystemIntentRunner.updateCalendarEvent(
    id: meeting.id, title: nil, startDate: nil, startTime: "22:00", endTime: "06:00",
    allDay: nil, location: nil, notes: nil, core: core)
  let movedNight = try await LorvexSystemIntentRunner.updateCalendarEvent(
    id: meeting.id, title: nil, startDate: "2026-05-30", startTime: nil, endTime: nil,
    allDay: nil, location: nil, notes: nil, core: core)
  #expect(movedNight.startDate == "2026-05-30")
  #expect(movedNight.endDate == "2026-05-31")

  // Moving a multi-day all-day event carries its length along.
  let trip = try await core.createCalendarEvent(
    title: "Trip", startDate: "2026-05-25", endDate: "2026-05-27", startTime: nil,
    endTime: nil, allDay: true, location: nil, notes: nil)
  let movedTrip = try await LorvexSystemIntentRunner.updateCalendarEvent(
    id: trip.id, title: nil, startDate: "2026-06-01", startTime: nil, endTime: nil,
    allDay: nil, location: nil, notes: nil, core: core)
  #expect(movedTrip.startDate == "2026-06-01")
  #expect(movedTrip.endDate == "2026-06-03")
  #expect(movedTrip.allDay)
}

@Test
func sharedSystemIntentRunnerHoldsAHabitTargetToTheSupportedRange() async throws {
  let core = try await makeSeededInMemoryCore()
  let huge = try await LorvexSystemIntentRunner.createHabit(
    name: "Huge target", cue: nil, targetCount: Int.max, core: core)
  #expect(huge.targetCount == 1_000)
  let negative = try await LorvexSystemIntentRunner.createHabit(
    name: "Negative target", cue: nil, targetCount: -4, core: core)
  #expect(negative.targetCount == 1)
  let updated = try await LorvexSystemIntentRunner.updateHabit(
    id: negative.id, name: nil, cue: nil, targetCount: Int.max, core: core)
  #expect(updated.targetCount == 1_000)
  let lowered = try await LorvexSystemIntentRunner.updateHabit(
    id: negative.id, name: nil, cue: nil, targetCount: 0, core: core)
  #expect(lowered.targetCount == 1)
}
