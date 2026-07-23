import Foundation
import LorvexCore
import LorvexMobile
import Testing

// I4 — mobile scoped recurring-event editing: the store threads the
// this-occurrence / this-and-following / all-events scope to the core's
// scoped-edit path (matching macOS + the edit_scoped_calendar_event MCP tool).

private func makeRecurringStandup(_ core: SwiftLorvexCoreService) async throws
  -> CalendarTimelineEvent
{
  try await core.createCalendarEvent(
    title: "Standup",
    startDate: "2026-05-23",
    endDate: nil,
    startTime: "09:00",
    endTime: "09:30",
    allDay: false,
    location: nil,
    notes: nil,
    recurrence: TaskRecurrenceRule(freq: .weekly, interval: 1),
    timezone: nil,
    url: nil,
    color: nil,
    eventType: nil,
    personName: nil,
    attendees: nil)
}

@Test
func calendarEventEditScopeWireValuesMatchContract() {
  #expect(CalendarEventEditScope.thisEvent.rawValue == "this_only")
  #expect(CalendarEventEditScope.thisAndFollowing.rawValue == "this_and_following")
  #expect(CalendarEventEditScope.allEvents.rawValue == "all_in_series")
}

@MainActor
@Test
func mobileStoreScopedAllEventsEditUpdatesWholeSeries() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let recurring = try await makeRecurringStandup(core)
  await store.refresh()
  #expect(recurring.isRecurring)

  store.prepareCalendarDraft(for: recurring)
  store.calendarDraft.title = "Team Standup"
  let saved = await store.saveScopedCalendarEvent(recurring, scope: .allEvents)

  #expect(saved)
  let updated = try #require(
    store.calendarTimeline?.events.first { $0.eventID == recurring.eventID })
  #expect(updated.title == "Team Standup")
  #expect(updated.isRecurring)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreScopedThisOccurrenceEditThreadsToService() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let recurring = try await makeRecurringStandup(core)
  await store.refresh()

  store.prepareCalendarDraft(for: recurring)
  store.calendarDraft.title = "Standup (this week only)"
  // The in-memory fake's scoped edit is a no-op returning the original, so this
  // asserts the store threads the this-occurrence scope to the service without
  // error; the on-disk core performs the real occurrence override.
  let saved = await store.saveScopedCalendarEvent(recurring, scope: .thisEvent)

  #expect(saved)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreReeditsMovedOccurrenceUsingOriginalOccurrenceDate() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let recurring = try await makeRecurringStandup(core)
  let firstEdit = try await core.editScopedCalendarEvent(
    eventID: recurring.eventID,
    occurrenceDate: "2026-05-23",
    scope: CalendarEventEditScope.thisEvent.rawValue,
    updates: ScopedCalendarEventUpdates(title: "Moved standup", startDate: "2026-05-25"))
  let moved = try #require(firstEdit.replacementEvent)
  #expect(moved.startDate == "2026-05-25")
  #expect(moved.occurrenceDate == "2026-05-23")

  store.prepareCalendarDraft(for: moved)
  store.calendarDraft.title = "Moved standup again"
  let saved = await store.saveScopedCalendarEvent(moved, scope: .thisEvent)

  #expect(saved)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreScopedAllEventsDeleteRemovesSeries() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let recurring = try await makeRecurringStandup(core)
  await store.refresh()
  #expect(store.calendarTimeline?.events.contains { $0.eventID == recurring.eventID } == true)

  let deleted = await store.deleteScopedCalendarEvent(recurring, scope: .allEvents)

  #expect(deleted)
  #expect(store.calendarTimeline?.events.contains { $0.eventID == recurring.eventID } == false)
  #expect(store.errorMessage == nil)
}
