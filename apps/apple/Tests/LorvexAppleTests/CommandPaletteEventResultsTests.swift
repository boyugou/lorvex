import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func paletteEvent(
  id: String, title: String = "Zeppelin inspection", day: String, start: String? = nil,
  end: String? = nil
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: id, title: title, source: "test", editable: true, startDate: day, startTime: start,
    endDate: day, endTime: end, allDay: start == nil, location: nil, color: nil,
    eventType: "event", timezone: nil, isRecurring: false)
}

private func eventIDs(_ groups: [CommandPaletteGroup]) -> [String] {
  groups.first { $0.title == "Events" }?.results.compactMap {
    if case .openEvent(let event, _) = $0 { event.id } else { nil }
  } ?? []
}

@Test("A typed query lists matching events after the tasks, and an event never leads")
func paletteEventsFollowTheTasksAndNeverLead() {
  let task = LorvexTask(
    id: "t1", title: "Zeppelin plan", notes: "", aiNotes: nil, priority: .p2, status: .open,
    dueDate: nil, estimatedMinutes: nil, tags: [])
  let groups = CommandPaletteResults.groups(
    query: "zeppelin", tasks: [task],
    events: [paletteEvent(id: "e1", day: "2026-06-12", start: "09:00")], todayKey: "2026-06-10")

  #expect(groups.map(\.title) == ["New Task", "Tasks", "Events"])
}

@Test("A palette with nothing typed lists no events")
func paletteWithNothingTypedListsNoEvents() {
  let groups = CommandPaletteResults.groups(
    query: "  ", tasks: [], events: [paletteEvent(id: "e1", day: "2026-06-12")],
    todayKey: "2026-06-10")

  #expect(!groups.contains { $0.title == "Events" })
}

@Test("The palette lists at most five events, those from today on first, earliest first")
func paletteEventsAreCappedAndUpcomingFirst() {
  let days = [
    "2026-06-01", "2026-06-09", "2026-06-10", "2026-06-11", "2026-06-20", "2026-07-01",
    "2026-08-01",
  ]
  let events = days.map { paletteEvent(id: $0, day: $0, start: "09:00") }

  let groups = CommandPaletteResults.groups(
    query: "zeppelin", tasks: [], events: events.reversed(), todayKey: "2026-06-10")

  #expect(CommandPaletteResults.eventResultLimit == 5)
  #expect(
    eventIDs(groups) == ["2026-06-10", "2026-06-11", "2026-06-20", "2026-07-01", "2026-08-01"])
}

@Test("Events before today follow the upcoming ones, most recent first")
func paletteEventsListPastOnesAfterUpcomingOnes() {
  let events = ["2026-06-01", "2026-06-09", "2026-06-11"].map {
    paletteEvent(id: $0, day: $0)
  }

  let groups = CommandPaletteResults.groups(
    query: "zeppelin", tasks: [], events: events, todayKey: "2026-06-10")

  #expect(eventIDs(groups) == ["2026-06-11", "2026-06-09", "2026-06-01"])
}

@Test("An event row names its day and time, and says Today for the logical today")
func paletteEventSubtitleNamesTheDayAndTime() {
  let today = CommandPaletteResults.eventSubtitle(
    paletteEvent(id: "a", day: "2026-06-10", start: "09:00", end: "09:30"),
    todayKey: "2026-06-10")
  let later = CommandPaletteResults.eventSubtitle(
    paletteEvent(id: "b", day: "2026-06-15"), todayKey: "2026-06-10")

  let todayWord = String(
    localized: "calendar.nav.today", defaultValue: "Today", table: "Localizable",
    bundle: LorvexL10n.bundle)
  #expect(today == "\(todayWord) · \(TodayCalmCopy.timeRange(start: 540, end: 570))")
  #expect(later == "\(ReviewCalmCopy.dayLabel("2026-06-15")) · \(TodayCalmCopy.allDay)")
}

@Test("An event result is titled by the event and wears the calendar symbol")
func paletteEventResultIsTitledByTheEvent() {
  let event = paletteEvent(id: "e1", title: "Dentist", day: "2026-06-12")
  let result = CommandPaletteResult.openEvent(event: event, subtitle: "Fri, Jun 12 · All day")

  #expect(result.id == "event.e1")
  #expect(result.localizedTitle == "Dentist")
  #expect(result.systemImage == "calendar")
  #expect(CommandPaletteGroup(title: "Events", results: [result]).localizedTitle.isEmpty == false)
}

@Test("Choosing an event shows it in the Calendar on the day it starts")
func paletteEventOpensInTheCalendarOnItsDay() throws {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/LorvexApple/Views/CommandPaletteView.swift")
  let text = try String(contentsOf: url, encoding: .utf8)

  let open = try #require(text.range(of: "case .openEvent(let event, _):"))
  let call = try #require(text.range(of: "store.showEventInCalendar(event, onDayKey: event.startDate)"))
  #expect(open.upperBound <= call.lowerBound)
  #expect(text.distance(from: open.upperBound, to: call.lowerBound) < 80)
}
