import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@MainActor
private func makeStore(events: [CalendarTimelineEvent]) async throws -> AppStore {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.calendarTimeline = CalendarTimelineSnapshot(
    from: "2026-06-15", to: "2026-06-21", events: events, truncated: false, nextOffset: nil)
  return store
}

private func event(id: String, editable: Bool) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: id, title: "Event \(id)", source: "Work", editable: editable,
    startDate: "2026-06-16", startTime: "09:00", endDate: "2026-06-16", endTime: "10:00",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
}

@MainActor
@Test
func calendarSelectionResolvesAgainstTheLiveTimeline() async throws {
  let owned = event(id: "owned", editable: true)
  let imported = event(id: "imported", editable: false)
  let store = try await makeStore(events: [owned, imported])

  #expect(store.selectedCalendarEvent == nil)

  // Imported (read-only) events are selectable too — the inspector renders them
  // read-only rather than refusing to open.
  store.selectCalendarEvent(imported)
  #expect(store.selectedCalendarEvent?.id == "imported")
  #expect(store.selectedCalendarEvent?.editable == false)

  store.selectCalendarEvent(owned)
  #expect(store.selectedCalendarEvent?.id == "owned")
  #expect(store.selectedCalendarEvent?.editable == true)

  store.clearSelectedCalendarEvent()
  #expect(store.selectedCalendarEvent == nil)
}

@MainActor
@Test
func calendarSelectionAutoHidesWhenEventLeavesTheWindow() async throws {
  let owned = event(id: "owned", editable: true)
  let store = try await makeStore(events: [owned])
  store.selectCalendarEvent(owned)
  #expect(store.selectedCalendarEvent?.id == "owned")

  // Navigating to a week that no longer contains the event drops the panel
  // without an explicit clear (resolution is by id against the live timeline).
  store.calendarTimeline = CalendarTimelineSnapshot(
    from: "2026-06-22", to: "2026-06-28", events: [], truncated: false, nextOffset: nil)
  #expect(store.selectedCalendarEvent == nil)
  #expect(store.selectedCalendarEventID == "owned")
}

@MainActor
@Test
func recurringOccurrencesWithOneCanonicalEventSelectIndependently() async throws {
  let first = CalendarTimelineEvent(
    id: "occurrence-one", eventID: "series", seriesID: "series",
    recurrenceGeneration: "1000-0-device", occurrenceDate: "2026-06-16",
    title: "First occurrence", source: "canonical", editable: true,
    startDate: "2026-06-16", startTime: "09:00", endDate: nil, endTime: "10:00",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: true)
  let second = CalendarTimelineEvent(
    id: "occurrence-two", eventID: "series", seriesID: "series",
    recurrenceGeneration: "1000-0-device", occurrenceDate: "2026-06-17",
    title: "Second occurrence", source: "canonical", editable: true,
    startDate: "2026-06-17", startTime: "09:00", endDate: nil, endTime: "10:00",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: true)
  let store = try await makeStore(events: [first, second])

  store.selectCalendarEvent(second)

  #expect(store.selectedCalendarEvent?.id == "occurrence-two")
  #expect(store.selectedCalendarEvent?.eventID == "series")
  #expect(store.selectedCalendarEvent?.occurrenceDate == "2026-06-17")
}
