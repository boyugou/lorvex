import Foundation
import LorvexCore
import SwiftUI
import Testing

@testable import LorvexMobile

@Test
func calendarDayCountAdaptsToActualAvailableWidth() {
  #expect(MobileCalendarDayView.adaptiveDayCount(for: 600, isRegularWidth: true) == 1)
  #expect(MobileCalendarDayView.adaptiveDayCount(for: 900, isRegularWidth: true) == 2)
  #expect(MobileCalendarDayView.adaptiveDayCount(for: 1_100, isRegularWidth: true) == 3)
  #expect(MobileCalendarDayView.adaptiveDayCount(for: 1_100, isRegularWidth: false) == 1)

  #expect(!MobileCalendarDayView.usesAgendaPanel(for: 820, isRegularWidth: true))
  #expect(MobileCalendarDayView.usesAgendaPanel(for: 900, isRegularWidth: true))
  #expect(!MobileCalendarDayView.usesAgendaPanel(for: 1_100, isRegularWidth: false))
}

@MainActor
@Test
func mobileCalendarDefaultsToTheAdaptiveDayGrid() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())

  #expect(store.calendarPresentationMode == .grid)
}

@MainActor
@Test("Grouped calendar agenda uses the same search-filtered events as the grid")
func mobileCalendarAgendaUsesSearchProjection() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-25" })
  store.calendarTimeline = CalendarTimelineSnapshot(
    from: "2026-05-25", to: "2026-05-31",
    events: [
      makeAgendaEvent(
        id: "matching", title: "Project Cedar", startDate: "2026-05-25", startTime: "09:00"),
      makeAgendaEvent(
        id: "hidden", title: "Dentist", startDate: "2026-05-25", startTime: "10:00"),
    ],
    truncated: false, nextOffset: nil)

  let view = MobileCalendarDayView(store: store, weekMode: true, searchQuery: "cedar")
  let visibleEventIDs = view.visibleAgendaDays(dayCount: 7).flatMap(\.events).map(\.id)

  #expect(visibleEventIDs == ["matching"])
}

@MainActor
@Test("Grouped calendar agenda uses the canonical planned-first task day")
func mobileCalendarAgendaUsesPlannedFirstTaskDays() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-25" })
  let view = MobileCalendarDayView(store: store, weekMode: true)
  let visibleDayKeys = view.visibleAgendaDays(dayCount: 3).map {
    MobileCalendarDayView.keyFormatter.string(from: $0.date)
  }
  #expect(visibleDayKeys.count == 3)
  store.calendarScheduledTasks = [
    makeAgendaTask(
      id: "due-only",
      dueDate: LorvexDateFormatters.ymdUTC.date(from: visibleDayKeys[0])),
    makeAgendaTask(
      id: "planned-only",
      plannedDate: LorvexDateFormatters.ymdUTC.date(from: visibleDayKeys[1])),
    makeAgendaTask(
      id: "planned-wins",
      dueDate: LorvexDateFormatters.ymdUTC.date(from: visibleDayKeys[0]),
      plannedDate: LorvexDateFormatters.ymdUTC.date(from: visibleDayKeys[2])),
  ]

  let days = view.visibleAgendaDays(dayCount: 3)

  #expect(days[0].tasks.map(\.id) == ["due-only"])
  #expect(days[1].tasks.map(\.id) == ["planned-only"])
  #expect(days[2].tasks.map(\.id) == ["planned-wins"])
}

@Test
func weekModeCreateDateUsesTodayOnlyForTheCurrentWeek() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 2
  let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 27)))
  let currentWeekStart = try #require(
    calendar.date(from: DateComponents(year: 2026, month: 5, day: 25)))
  let futureWeekStart = try #require(
    calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))

  #expect(
    calendar.isDate(
      MobileCalendarDayView.defaultCreateDate(
        weekMode: true,
        visibleDate: currentWeekStart,
        today: today,
        calendar: calendar),
      inSameDayAs: today))
  #expect(
    calendar.isDate(
      MobileCalendarDayView.defaultCreateDate(
        weekMode: true,
        visibleDate: futureWeekStart,
        today: today,
        calendar: calendar),
      inSameDayAs: futureWeekStart))
  #expect(
    calendar.isDate(
      MobileCalendarDayView.defaultCreateDate(
        weekMode: false,
        visibleDate: futureWeekStart,
        today: today,
        calendar: calendar),
      inSameDayAs: futureWeekStart))
}

private func makeAgendaEvent(
  id: String,
  title: String,
  startDate: String,
  endDate: String? = nil,
  startTime: String? = nil
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: id,
    title: title,
    source: "test",
    editable: true,
    startDate: startDate,
    startTime: startTime,
    endDate: endDate,
    endTime: nil,
    allDay: startTime == nil,
    location: nil,
    color: nil,
    eventType: "event",
    timezone: nil,
    isRecurring: false
  )
}

private func makeAgendaTask(
  id: String,
  dueDate: Date? = nil,
  plannedDate: Date? = nil
) -> LorvexTask {
  LorvexTask(
    id: id,
    title: id,
    notes: "",
    priority: .p3,
    status: .open,
    dueDate: dueDate,
    plannedDate: plannedDate,
    estimatedMinutes: nil,
    tags: []
  )
}

/// A multi-day event must appear on every day its span covers — including the
/// middle days — so the iPad agenda panel never disagrees with the timeline
/// grid about which day an event belongs to.
@Test
func agendaIncludesMultiDayEventOnEveryCoveredDay() {
  let trip = makeAgendaEvent(
    id: "trip", title: "Conference", startDate: "2026-05-25", endDate: "2026-05-27")

  for key in ["2026-05-25", "2026-05-26", "2026-05-27"] {
    let events = MobileCalendarDayView.agendaEvents(from: [trip], on: key)
    #expect(events.map(\.id) == ["trip"], "expected the multi-day event on \(key)")
  }
}

/// Days outside the span (and single-day events on other days) stay excluded.
@Test
func agendaExcludesDaysOutsideTheSpan() {
  let trip = makeAgendaEvent(
    id: "trip", title: "Conference", startDate: "2026-05-25", endDate: "2026-05-27")
  let single = makeAgendaEvent(
    id: "single", title: "Dentist", startDate: "2026-05-26", startTime: "09:00")

  #expect(MobileCalendarDayView.agendaEvents(from: [trip, single], on: "2026-05-24").isEmpty)
  #expect(MobileCalendarDayView.agendaEvents(from: [trip, single], on: "2026-05-28").isEmpty)
  #expect(MobileCalendarDayView.agendaEvents(from: [single], on: "2026-05-25").isEmpty)
  #expect(MobileCalendarDayView.agendaEvents(from: [single], on: "2026-05-27").isEmpty)
}

/// A nil `endDate` is treated as a single-day event on its `startDate`.
@Test
func agendaTreatsMissingEndDateAsSingleDay() {
  let event = makeAgendaEvent(
    id: "e", title: "Standup", startDate: "2026-05-26", startTime: "10:00")

  #expect(MobileCalendarDayView.agendaEvents(from: [event], on: "2026-05-26").map(\.id) == ["e"])
  #expect(MobileCalendarDayView.agendaEvents(from: [event], on: "2026-05-27").isEmpty)
}

/// Ordering is start-time ascending, with untimed (all-day / spanning) events
/// before timed ones, then title for ties.
@Test
func agendaOrdersTimedAfterUntimedThenByStartTimeAndTitle() {
  let allDay = makeAgendaEvent(id: "allday", title: "Holiday", startDate: "2026-05-26")
  let nine = makeAgendaEvent(id: "nine", title: "Sync", startDate: "2026-05-26", startTime: "09:00")
  let nineToo = makeAgendaEvent(
    id: "nine2", title: "Alpha", startDate: "2026-05-26", startTime: "09:00")
  let eight = makeAgendaEvent(
    id: "eight", title: "Breakfast", startDate: "2026-05-26", startTime: "08:00")

  let ordered = MobileCalendarDayView.agendaEvents(
    from: [nine, allDay, nineToo, eight], on: "2026-05-26")
  // Untimed first, then 08:00, then the two 09:00 events tie-broken by title
  // ("Alpha" < "Sync").
  #expect(ordered.map(\.id) == ["allday", "eight", "nine2", "nine"])
}
