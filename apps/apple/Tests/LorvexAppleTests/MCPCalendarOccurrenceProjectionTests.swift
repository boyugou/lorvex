import LorvexCore
import Testing

@testable import LorvexMCPHost

@Test
func calendarOccurrenceProjectionSeparatesUniqueIDFromMutationAddress() throws {
  let event = CalendarTimelineEvent(
    id: "decision-id",
    eventID: "series-id",
    seriesID: "series-id",
    recurrenceGeneration: "1770000000000-0-device",
    occurrenceDate: "2026-06-23",
    occurrenceState: .replacement,
    title: "Moved occurrence",
    source: "canonical",
    editable: true,
    startDate: "2026-06-25",
    startTime: "10:00",
    endDate: nil,
    endTime: "10:30",
    allDay: false,
    location: nil,
    color: nil,
    eventType: "event",
    timezone: nil,
    isRecurring: false)

  let full = try #require(
    CoreBridgeClient.calendarEventValue(from: event).objectValue)
  #expect(full["id"]?.stringValue == "decision-id")
  #expect(full["event_id"]?.stringValue == "series-id")
  #expect(full["series_id"]?.stringValue == "series-id")
  #expect(full["occurrence_date"]?.stringValue == "2026-06-23")
  #expect(full["occurrence_state"]?.stringValue == "replacement")
  #expect(full["start_date"]?.stringValue == "2026-06-25")

  let compact = try #require(
    CoreBridgeClient.calendarEventValue(from: event, options: .compact).objectValue)
  #expect(compact["id"]?.stringValue == "decision-id")
  #expect(compact["event_id"]?.stringValue == "series-id")
  #expect(compact["occurrence_date"]?.stringValue == "2026-06-23")
  #expect(compact["occurrence_state"]?.stringValue == "replacement")

  let explicit = try #require(
    CoreBridgeClient.calendarEventValue(
      from: event,
      options: CalendarEventValueOptions(fields: ["title"]))
      .objectValue)
  #expect(explicit["title"]?.stringValue == "Moved occurrence")
  #expect(explicit["id"]?.stringValue == "decision-id")
  #expect(explicit["event_id"]?.stringValue == "series-id")
  #expect(explicit["series_id"]?.stringValue == "series-id")
  #expect(explicit["recurrence_generation"]?.stringValue == "1770000000000-0-device")
  #expect(explicit["occurrence_date"]?.stringValue == "2026-06-23")
  #expect(explicit["occurrence_state"]?.stringValue == "replacement")
}

@Test
func explicitCalendarFieldsKeepOneOffEventWireShapeCompact() throws {
  let event = CalendarTimelineEvent(
    id: "one-off", title: "One off", source: "canonical", editable: true,
    startDate: "2026-06-25", startTime: nil, endDate: nil, endTime: nil,
    allDay: true, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)

  let explicit = try #require(
    CoreBridgeClient.calendarEventValue(
      from: event,
      options: CalendarEventValueOptions(fields: ["title"]))
      .objectValue)

  #expect(explicit["id"]?.stringValue == "one-off")
  #expect(explicit["event_id"]?.stringValue == "one-off")
  #expect(explicit["title"]?.stringValue == "One off")
  #expect(explicit["series_id"] == nil)
  #expect(explicit["recurrence_generation"] == nil)
  #expect(explicit["occurrence_date"] == nil)
  #expect(explicit["occurrence_state"] == nil)

  let full = try #require(CoreBridgeClient.calendarEventValue(from: event).objectValue)
  #expect(full["event_id"]?.stringValue == "one-off")
  #expect(full["series_id"] == nil)
  #expect(full["recurrence_generation"] == nil)
  #expect(full["occurrence_date"] == nil)
  #expect(full["occurrence_state"] == nil)
}

@Test
func fullCalendarProjectionSeparatesProviderOccurrenceIDFromLinkAddress() throws {
  let provider = CalendarTimelineEvent(
    id: "eventkit:device:opaque:key:occurrence:2026-06-25",
    eventID: "eventkit:device:opaque:key",
    title: "External standup", source: "provider", editable: false,
    startDate: "2026-06-25", startTime: "09:00", endDate: "2026-06-25",
    endTime: "09:30", allDay: false, location: nil, color: nil,
    eventType: "event", timezone: "UTC", isRecurring: true)

  let full = try #require(CoreBridgeClient.calendarEventValue(from: provider).objectValue)

  #expect(full["id"]?.stringValue == "eventkit:device:opaque:key:occurrence:2026-06-25")
  #expect(full["event_id"]?.stringValue == "eventkit:device:opaque:key")
  #expect(full["series_id"] == nil)
  #expect(full["recurrence_generation"] == nil)
  #expect(full["occurrence_date"] == nil)
  #expect(full["occurrence_state"] == nil)
}

@Test
func narrowRecurringProjectionAlwaysIncludesScopedMutationAddress() throws {
  let occurrence = CalendarTimelineEvent(
    id: "decision-id", eventID: "series-id", seriesID: "series-id",
    recurrenceGeneration: "1770000000000-0-device", occurrenceDate: "2026-06-25",
    title: "Natural occurrence", source: "canonical", editable: true,
    startDate: "2026-06-25", startTime: "09:00", endDate: "2026-06-25",
    endTime: "09:30", allDay: false, location: nil, color: nil,
    eventType: "event", timezone: "UTC", isRecurring: true,
    recurrenceRule: #"{"FREQ":"DAILY"}"#)

  let narrow = try #require(
    CoreBridgeClient.calendarEventValue(
      from: occurrence,
      options: CalendarEventValueOptions(fields: ["title"]))
      .objectValue)

  #expect(narrow["id"]?.stringValue == "decision-id")
  #expect(narrow["event_id"]?.stringValue == "series-id")
  #expect(narrow["series_id"]?.stringValue == "series-id")
  #expect(narrow["recurrence_generation"]?.stringValue == "1770000000000-0-device")
  #expect(narrow["occurrence_date"]?.stringValue == "2026-06-25")
  #expect(narrow["occurrence_state"] == .null)
}
