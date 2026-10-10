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
