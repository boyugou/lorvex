import LorvexDomain
import Testing

@testable import LorvexStore

@Test
func providerRecurrenceOccurrencesHaveUniqueRenderIDsAndOneLinkAddress() throws {
  let start = try LorvexDate.parse("2026-09-01").get()
  let startTime = try TimeOfDay.parse("09:00").get()
  let endTime = try TimeOfDay.parse("09:30").get()
  let item = try CalendarTimelineItem.make(
    source: .provider, editable: false, id: "eventkit:device:series-key",
    title: "External standup", startDate: start, startTime: startTime,
    endDate: nil, endTime: endTime, allDay: false, location: nil, color: nil,
    eventType: "event", personName: nil, timezone: "UTC",
    providerKind: "eventkit", providerScope: "device", isRecurring: true,
    recurrenceRule: #"{"FREQ":"DAILY"}"#, sourceTimeKind: "tzid",
    sourceTzid: "UTC", url: nil, attendeesJson: nil).get()
  let raw = CalendarTimeline.RawCalendarRow(
    item: item, recurrence: #"{"FREQ":"DAILY"}"#, recurrenceExceptions: nil)
  let from = try CalendarRecurrence.parseYmd("2026-09-01")
  let to = try CalendarRecurrence.parseYmd("2026-09-02")

  let expanded = try CalendarTimeline.expandRowForRange(raw, from, to, "UTC").items

  #expect(expanded.count == 2)
  #expect(Set(expanded.map(\.id)).count == 2)
  #expect(expanded.map(\.eventId) == [
    "eventkit:device:series-key", "eventkit:device:series-key",
  ])
  #expect(expanded[0].id.contains(":occurrence:2026-09-01"))
  #expect(expanded[1].id.contains(":occurrence:2026-09-02"))
}
