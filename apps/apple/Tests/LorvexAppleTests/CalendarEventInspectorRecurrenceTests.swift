import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func inspectorEvent(
  recurrenceRule: String?, recurrenceSummary: String? = nil, isRecurring: Bool = true
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: "e", title: "Standup", source: "canonical", editable: true,
    startDate: "2026-06-01", startTime: "09:00", endDate: "2026-06-01", endTime: "09:15",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: isRecurring, recurrenceRule: recurrenceRule,
    recurrenceSummary: recurrenceSummary)
}

@Test("The event inspector says how a Lorvex series repeats, in the repeat editor's words")
func eventInspectorNamesTheCadenceOfAStoredRule() {
  let rule = TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO", "WE"])

  let label = CalendarEventInspector.recurrenceLabel(
    for: inspectorEvent(recurrenceRule: rule.canonicalRecurrenceJSON()))

  #expect(label == rule.localizedDisplaySummary(anchorDay: nil))
  #expect(label.contains("2"))
  #expect(label != "Repeating event")
}

@Test("The event inspector prefers the source's own summary of a mirrored event's repeat")
func eventInspectorPrefersTheSourceSummary() {
  let label = CalendarEventInspector.recurrenceLabel(
    for: inspectorEvent(
      recurrenceRule: TaskRecurrenceRule(freq: .daily).canonicalRecurrenceJSON(),
      recurrenceSummary: "Every weekday"))

  #expect(label == "Every weekday")
}

@Test("A one-off change to a series occurrence reads as a generic repeating event")
func eventInspectorFallsBackWithoutARule() {
  let label = CalendarEventInspector.recurrenceLabel(
    for: inspectorEvent(recurrenceRule: nil, isRecurring: false))

  #expect(label == "Repeating event")
}

struct CalendarRecurrenceDisplayTimeZoneTests {
  @Test(arguments: [
    ("America/New_York", "Asia/Tokyo", "23:30", "23:45", "2026-11-24"),
    ("Asia/Tokyo", "America/Los_Angeles", "00:30", "01:30", "2026-11-22"),
    ("Asia/Kathmandu", "America/Los_Angeles", "00:30", "01:30", "2026-11-22"),
  ])
  func implicitWeeklyDayUsesTheSourceClock(
    source: String, display: String, start: String, end: String, displayedDay: String
  ) async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: display)
    let saved = try await core.createCalendarEvent(
      title: "Monday meeting", startDate: "2026-11-23", endDate: nil,
      startTime: start, endTime: end, allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .weekly), timezone: source,
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-22", to: "2026-11-24")
    let projected = try #require(timeline.events.first { $0.eventID == saved.id })
    #expect(projected.startDate == displayedDay)
    let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
      .localizedDisplaySummary(anchorDay: nil)
    #expect(saved.recurrenceDescription(generic: "Repeating event") == monday)
    #expect(projected.recurrenceDescription(generic: "Repeating event") == monday)
    let instant = try #require(projected.projection?.start)
    let sourceName = try #require(LorvexTimeZoneChoice(identifier: source, now: instant)).summary
    #expect(try #require(projected.recurrenceTimeZoneNote).contains(sourceName))
    #expect(saved.recurrenceTimeZoneNote == nil)

    var sameClock = projected
    sameClock.projection = CalendarEventProjection(timezone: source, start: instant, end: nil)
    #expect(sameClock.recurrenceTimeZoneNote == nil)

    var oneOff = projected
    oneOff.isRecurring = false
    oneOff.supportsScopedMutation = false
    oneOff.recurrenceRule = nil
    #expect(oneOff.recurrenceTimeZoneNote == nil)
  }

  @Test(arguments: [false, true])
  func floatingAndAllDayRulesKeepTheirCivilWeekday(allDay: Bool) {
    var event = inspectorEvent(recurrenceRule: TaskRecurrenceRule(freq: .weekly).canonicalRecurrenceJSON())
    event.allDay = allDay
    event.timezone = allDay ? "Asia/Tokyo" : nil
    if allDay {
      event.startTime = nil
      event.endTime = nil
    }
    let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
      .localizedDisplaySummary(anchorDay: nil)
    #expect(event.recurrenceDescription(generic: "Repeating event") == monday)
    event.projection = CalendarEventProjection(timezone: "America/Los_Angeles", start: .distantPast, end: nil)
    #expect(event.recurrenceTimeZoneNote == nil)
  }
}
