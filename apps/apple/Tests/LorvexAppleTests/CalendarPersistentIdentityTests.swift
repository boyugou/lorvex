import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexSystemIntents

@Test
func calendarEventEntityUsesStableSeriesAddress() {
  let occurrence = CalendarTimelineEvent(
    id: "rendered-occurrence-id",
    eventID: "series-segment-id",
    seriesID: "series-segment-id",
    recurrenceGeneration: "generation-a",
    occurrenceDate: "2026-07-17",
    title: "Daily planning",
    source: "canonical",
    editable: true,
    startDate: "2026-07-17",
    startTime: "09:00",
    endDate: nil,
    endTime: "09:30",
    allDay: false,
    location: nil,
    color: nil,
    eventType: "event",
    timezone: "UTC",
    isRecurring: true)

  let entity = LorvexCalendarEventEntity(event: occurrence)

  #expect(entity.id == "series-segment-id")
  #expect(entity.eventID == "series-segment-id")
}

@Test
func stableCalendarRepresentativesCollapseOccurrencesAndPreferNaturalSlot() {
  let replacement = persistentIdentityEvent(
    id: "replacement-decision", eventID: "series-a", title: "One-off title",
    occurrenceDate: "2026-07-17", occurrenceState: .replacement)
  let natural = persistentIdentityEvent(
    id: "natural-occurrence", eventID: "series-a", title: "Series title",
    occurrenceDate: "2026-07-18", occurrenceState: nil)
  let oneOff = persistentIdentityEvent(
    id: "one-off", eventID: "one-off", title: "One off",
    occurrenceDate: nil, occurrenceState: nil)

  let representatives = CalendarTimelineEvent.stableSourceRepresentatives(
    in: [replacement, natural, oneOff])

  #expect(representatives.map(\.eventID) == ["series-a", "one-off"])
  #expect(representatives.first?.id == "natural-occurrence")
  #expect(representatives.first?.title == "Series title")
}

@Test
func calendarEventEntityRoutesWholeSeriesMutationsThroughStableID() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = LorvexDateFormatters.ymd.string(from: Date())
  let series = try await core.createCalendarEvent(
    title: "Shortcut recurring identity",
    startDate: today,
    endDate: nil,
    startTime: "09:00",
    endTime: "09:30",
    allDay: false,
    location: nil,
    notes: nil,
    recurrence: TaskRecurrenceRule(freq: .daily, count: 3),
    timezone: "UTC",
    url: nil,
    color: nil,
    eventType: nil,
    personName: nil,
    attendees: nil)
  let replacementOnlySeries = try await core.createCalendarEvent(
    title: "Stable series title",
    startDate: today,
    endDate: nil,
    startTime: "11:00",
    endTime: "11:30",
    allDay: false,
    location: nil,
    notes: nil,
    recurrence: TaskRecurrenceRule(freq: .daily, count: 1),
    timezone: "UTC",
    url: nil,
    color: nil,
    eventType: nil,
    personName: nil,
    attendees: nil)
  _ = try await core.editScopedCalendarEvent(
    eventID: replacementOnlySeries.eventID,
    occurrenceDate: today,
    scope: CalendarEventEditScope.thisEvent.rawValue,
    updates: ScopedCalendarEventUpdates(title: "One-off replacement title"))

  let suggested = try await LorvexCalendarEventEntityQuery.suggestedEntities(core: core)
  let matchingSeries = suggested.filter { $0.id == series.id }
  #expect(matchingSeries.count == 1)
  #expect(suggested.first { $0.id == replacementOnlySeries.id }?.title == "Stable series title")

  let rehydrated = try await LorvexCalendarEventEntityQuery.entities(
    for: [series.id], core: core)
  #expect(rehydrated.map(\.id) == [series.id])

  let updated = try await LorvexTaskIntentRunner.updateCalendarEvent(
    id: try #require(rehydrated.first).eventID,
    title: "Updated recurring identity",
    startDate: nil,
    startTime: nil,
    endTime: nil,
    allDay: nil,
    location: nil,
    notes: nil,
    core: core)
  #expect(updated.id == series.id)
  #expect(updated.title == "Updated recurring identity")

  let rehydratedAfterUpdate = try await LorvexCalendarEventEntityQuery.entities(
    for: [series.id], core: core)
  #expect(rehydratedAfterUpdate.map(\.id) == [series.id])

  let timeline = try await core.loadCalendarTimeline(from: today, to: today)
  #expect(timeline.events.first { $0.eventID == series.id }?.title == "Updated recurring identity")

  let deletedID = try await LorvexTaskIntentRunner.deleteCalendarEvent(
    id: try #require(rehydrated.first).eventID, core: core)
  #expect(deletedID == series.id)
  #expect(try await core.getCalendarEvent(id: series.id) == nil)
}

private func persistentIdentityEvent(
  id: String,
  eventID: String,
  title: String,
  occurrenceDate: String?,
  occurrenceState: CalendarTimelineOccurrenceState?
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: id,
    eventID: eventID,
    seriesID: occurrenceDate == nil ? nil : eventID,
    recurrenceGeneration: occurrenceDate == nil ? nil : "generation-a",
    occurrenceDate: occurrenceDate,
    occurrenceState: occurrenceState,
    title: title,
    source: "canonical",
    editable: true,
    startDate: occurrenceDate ?? "2026-07-17",
    startTime: "09:00",
    endDate: nil,
    endTime: "09:30",
    allDay: false,
    location: nil,
    color: nil,
    eventType: "event",
    timezone: "UTC",
    isRecurring: occurrenceDate != nil)
}
