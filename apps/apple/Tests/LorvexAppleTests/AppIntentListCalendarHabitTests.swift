import AppIntents
import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing
import UniformTypeIdentifiers

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func createListIntentPerformThrowsOnBlankName() async throws {
  let intent = CreateLorvexListIntent(name: "   ")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await intent.perform()
  }
}

@Test
func updateListIntentPerformThrowsOnBlankListID() async throws {
  let intent = UpdateLorvexListIntent(
    list: LorvexListEntity(id: "   ", name: "", openCount: 0, totalCount: 0),
    name: "Inbox"
  )
  await #expect(throws: LorvexCoreError.self) {
    _ = try await intent.perform()
  }
}

@Test
func readListDetailIntentPerformThrowsOnBlankListID() async throws {
  let intent = ReadLorvexListDetailIntent(
    list: LorvexListEntity(id: "   ", name: "", openCount: 0, totalCount: 0)
  )
  await #expect(throws: LorvexCoreError.self) {
    _ = try await intent.perform()
  }
}

@Test
func updateCalendarEventIntentPerformThrowsOnBlankEventID() async throws {
  let intent = UpdateLorvexCalendarEventIntent(
    event: LorvexCalendarEventEntity(
      id: "   ", title: "", startDate: "", startTime: nil, endTime: nil, allDay: false),
    title: "Planning"
  )
  await #expect(throws: LorvexCoreError.self) {
    _ = try await intent.perform()
  }
}

@Test
func calendarExtendedIntentPerformThrowsOnInvalidInputs() async throws {
  let blankTask = LorvexTaskEntity(id: "   ", title: "", status: "")
  let blankEvent = LorvexCalendarEventEntity(
    id: "   ", title: "", startDate: "", startTime: nil, endTime: nil, allDay: false)
  await #expect(throws: LorvexCoreError.self) {
    _ = try await ReadLorvexCalendarTimelineIntent(from: "   ", to: "2026-05-25").perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await SearchLorvexCalendarEventsIntent(query: "   ").perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LinkLorvexTaskToProviderEventIntent(
      task: blankTask,
      providerEventID: "provider-1"
    ).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await UnlinkLorvexTaskFromProviderEventIntent(
      task: blankTask,
      providerEventID: "provider-1"
    ).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await ReadLorvexLinkedEventsForTaskIntent(task: blankTask).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await ReadLorvexLinkedTasksForEventIntent(event: blankEvent).perform()
  }
}

@Test
func deleteCalendarEventIntentPerformThrowsOnBlankEventID() async throws {
  // DeleteLorvexCalendarEventIntent confirms before validating, so perform()
  // surfaces the confirmation gate rather than a core error in a unit test.
  let intent = DeleteLorvexCalendarEventIntent(
    event: LorvexCalendarEventEntity(
      id: "   ", title: "", startDate: "", startTime: nil, endTime: nil, allDay: false)
  )
  await #expect(throws: (any Error).self) {
    _ = try await intent.perform()
  }
}

@Test
func completeHabitIntentPerformThrowsOnBlankHabitID() async throws {
  let intent = CompleteLorvexHabitIntent(
    habit: LorvexHabitEntity(id: "   ", name: "", completionsToday: 0, targetCount: 1))
  await #expect(throws: LorvexCoreError.self) {
    _ = try await intent.perform()
  }
}

@Test
func habitExtendedIntentPerformThrowsOnInvalidInputs() async throws {
  let blankHabit = LorvexHabitEntity(
    id: "   ", name: "", completionsToday: 0, targetCount: 1)
  await #expect(throws: LorvexCoreError.self) {
    _ = try await ReadLorvexHabitCompletionsIntent(habit: blankHabit).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await ReadLorvexHabitStatsIntent(habit: blankHabit).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await BatchCompleteLorvexHabitsIntent(habits: []).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await ReadLorvexHabitReminderPoliciesIntent(habit: blankHabit).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await UpsertLorvexHabitReminderPolicyIntent(
      habit: blankHabit,
      reminderTime: "25:99",
      enabled: true
    ).perform()
  }
}

@Test
func updateHabitIntentPerformThrowsOnBlankHabitID() async throws {
  let intent = UpdateLorvexHabitIntent(
    habit: LorvexHabitEntity(
      id: "   ", name: "", completionsToday: 0, targetCount: 1),
    name: "Read"
  )
  await #expect(throws: LorvexCoreError.self) {
    _ = try await intent.perform()
  }
}

@Test
func deleteHabitIntentPerformThrowsOnBlankHabitID() async throws {
  // DeleteLorvexHabitIntent confirms before validating, so perform() surfaces the
  // confirmation gate rather than a core error in a unit test.
  let intent = DeleteLorvexHabitIntent(
    habit: LorvexHabitEntity(
      id: "   ", name: "", completionsToday: 0, targetCount: 1)
  )
  await #expect(throws: (any Error).self) {
    _ = try await intent.perform()
  }
}
