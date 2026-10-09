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

/// A phone on its side (a compact height) shows three days in Day mode, in a
/// compact width (iPhone Pro) and a regular one (iPhone Pro Max) alike, and
/// never stands the agenda beside a grid only a few hours tall.
@Test
func calendarDayModeShowsThreeDaysOnAPhoneOnItsSide() {
  #expect(
    MobileCalendarDayView.adaptiveDayCount(for: 750, isRegularWidth: false, isCompactHeight: true)
      == 3)
  #expect(
    MobileCalendarDayView.adaptiveDayCount(for: 830, isRegularWidth: true, isCompactHeight: true)
      == 3)
  #expect(
    !MobileCalendarDayView.usesAgendaPanel(for: 900, isRegularWidth: true, isCompactHeight: true))
}

/// The calendar opens in Day mode until the user switches, then in the mode
/// last switched to. Showing a mode directly (as the DEBUG route does) is not
/// remembered, and a stored value no mode names reads as Day.
@MainActor
@Test
func mobileCalendarOpensInTheModeLastSwitchedTo() async throws {
  let suiteName = "MobileCalendarModeTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try await makeSeededInMemoryCore()

  let store = MobileStore(core: core, defaults: defaults)
  #expect(store.calendarPresentationMode == .grid)
  #expect(MobileCalendarPresentationMode.allCases == [.grid, .week, .month])

  #expect(store.calendarPendingDay(in: .current) == nil)
  store.switchCalendarPresentationMode(to: .month, onDayKey: "2026-10-05")
  #expect(store.calendarPresentationMode == .month)
  #expect(store.calendarPendingDayKey == "2026-10-05")
  var tokyo = Calendar(identifier: .gregorian)
  tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
  #expect(
    store.calendarPendingDay(in: tokyo)
      == tokyo.date(from: DateComponents(year: 2026, month: 10, day: 5)))
  #expect(MobileStore(core: core, defaults: defaults).calendarPresentationMode == .month)

  store.switchCalendarPresentationMode(to: .month, onDayKey: "2026-10-09")
  #expect(store.calendarPendingDayKey == "2026-10-05")

  store.calendarPresentationMode = .week
  #expect(MobileStore(core: core, defaults: defaults).calendarPresentationMode == .month)

  defaults.set("year", forKey: MobileCalendarPresentationMode.defaultsKey)
  #expect(MobileStore(core: core, defaults: defaults).calendarPresentationMode == .grid)
}

@MainActor
@Test("The agenda beside the grid uses the same search-filtered events as the grid")
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

  let view = MobileCalendarDayView(store: store, searchQuery: "cedar")
  let visibleEventIDs = view.agendaDays(dayCount: 7, from: view.visibleDate).flatMap(\.events).map(\.id)

  #expect(visibleEventIDs == ["matching"])
}

@MainActor
@Test("Grouped calendar agenda uses the canonical planned-first task day")
func mobileCalendarAgendaUsesPlannedFirstTaskDays() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-25" })
  let view = MobileCalendarDayView(store: store, weekMode: true)
  let visibleDayKeys = view.agendaDays(dayCount: 3, from: view.visibleDate).map {
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

  let days = view.agendaDays(dayCount: 3, from: view.visibleDate)

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
    let events = MobileCalendarAgendaDay.agendaEvents(from: [trip], on: key)
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

  #expect(MobileCalendarAgendaDay.agendaEvents(from: [trip, single], on: "2026-05-24").isEmpty)
  #expect(MobileCalendarAgendaDay.agendaEvents(from: [trip, single], on: "2026-05-28").isEmpty)
  #expect(MobileCalendarAgendaDay.agendaEvents(from: [single], on: "2026-05-25").isEmpty)
  #expect(MobileCalendarAgendaDay.agendaEvents(from: [single], on: "2026-05-27").isEmpty)
}

/// A nil `endDate` is treated as a single-day event on its `startDate`.
@Test
func agendaTreatsMissingEndDateAsSingleDay() {
  let event = makeAgendaEvent(
    id: "e", title: "Standup", startDate: "2026-05-26", startTime: "10:00")

  #expect(MobileCalendarAgendaDay.agendaEvents(from: [event], on: "2026-05-26").map(\.id) == ["e"])
  #expect(MobileCalendarAgendaDay.agendaEvents(from: [event], on: "2026-05-27").isEmpty)
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

  let ordered = MobileCalendarAgendaDay.agendaEvents(
    from: [nine, allDay, nineToo, eight], on: "2026-05-26")
  // Untimed first, then 08:00, then the two 09:00 events tie-broken by title
  // ("Alpha" < "Sync").
  #expect(ordered.map(\.id) == ["allday", "eight", "nine2", "nine"])
}

/// A task under an agenda day states its time that day, else its estimate,
/// then "Due" on its due date, and breaks only after a span's dash or a dot.
@Test
func agendaTaskFactsBreakOnlyBetweenFacts() {
  let day = "2026-09-30"
  let midnight = LorvexDateFormatters.ymdUTC.date(from: day)!
  func task(time: Range<Int>? = nil, estimate: Int? = nil, due: Date? = nil) -> LorvexTask {
    LorvexTask(
      id: "t", title: "Task", notes: "", priority: .p2, status: .open, dueDate: due,
      plannedDate: time == nil ? nil : midnight, plannedTime: time, estimatedMinutes: estimate,
      tags: [])
  }
  func facts(_ task: LorvexTask, on key: String = day) -> String? {
    MobileCalendarAgendaTaskRow.subtitle(for: task, dayKey: key)
  }
  let span = lorvexUnbreakable(lorvexClockRangeLabel(startMinutes: 585, endMinutes: 630))
  let estimate = lorvexUnbreakable(LorvexDurationFormat.minutes(45))

  #expect(facts(task(time: 585..<630, estimate: 45, due: midnight)) == "\(span)\u{00A0}· Due")
  #expect(facts(task(estimate: 45)) == estimate)
  #expect(facts(task(due: midnight)) == "Due")
  #expect(facts(task()) == nil)
  // A time or a due date on another day says nothing about this one.
  #expect(facts(task(time: 585..<630, estimate: 45), on: "2026-10-01") == estimate)
  #expect(facts(task(due: midnight.addingTimeInterval(86_400))) == nil)
  // A blocked task says so last.
  let blocked = MobileTaskDisplayText.blocked
  #expect(
    MobileCalendarAgendaTaskRow.subtitle(for: task(due: midnight), dayKey: day, isBlocked: true)
      == "Due\u{00A0}· \(blocked)")
  #expect(MobileCalendarAgendaTaskRow.subtitle(for: task(), dayKey: day, isBlocked: true) == blocked)
}
