import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func searchEvent(
  id: String, title: String, startDate: String, startTime: String? = nil
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: id, title: title, source: "test", editable: true,
    startDate: startDate, startTime: startTime, endDate: startDate, endTime: nil,
    allDay: startTime == nil, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
}

@Test("A search lists days from today on first, earliest first, then past days, most recent first")
func calendarSearchDaysOrderUpcomingBeforePast() {
  let events = [
    searchEvent(id: "a", title: "Past old", startDate: "2026-04-01", startTime: "09:00"),
    searchEvent(id: "b", title: "Later", startDate: "2026-06-30", startTime: "09:00"),
    searchEvent(id: "c", title: "Past recent", startDate: "2026-05-20", startTime: "09:00"),
    searchEvent(id: "d", title: "Today", startDate: "2026-05-25", startTime: "09:00"),
  ]

  let days = CalendarSearchDay.days(for: events, todayKey: "2026-05-25")

  #expect(days.map(\.key) == ["2026-05-25", "2026-06-30", "2026-05-20", "2026-04-01"])
}

@Test("A search day lists all-day events first, then timed events by start, then by title")
func calendarSearchDayOrdersEventsLikeTheAgenda() {
  let events = [
    searchEvent(id: "late", title: "Late call", startDate: "2026-06-01", startTime: "16:00"),
    searchEvent(id: "b", title: "Beta sync", startDate: "2026-06-01", startTime: "09:00"),
    searchEvent(id: "a", title: "Alpha sync", startDate: "2026-06-01", startTime: "09:00"),
    searchEvent(id: "all", title: "Offsite", startDate: "2026-06-01"),
  ]

  let day = CalendarSearchDay.days(for: events, todayKey: "2026-05-25").first

  #expect(day?.events.map(\.id) == ["all", "a", "b", "late"])
}

@Test("A search with no events lists no days")
func calendarSearchDaysForNoEventsAreEmpty() {
  #expect(CalendarSearchDay.days(for: [], todayKey: "2026-05-25").isEmpty)
}

@MainActor
@Test("The Mac calendar search finds events on any date, not only in the loaded window")
func macCalendarSearchFindsEventsOutsideTheLoadedWindow() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  let today = store.logicalTodayDateString
  let future = try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: 400))
  let past = try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: -400))
  _ = try await core.createCalendarEvent(
    title: "Zeppelin inspection", startDate: future, endDate: nil, startTime: "10:00",
    endTime: "11:00", allDay: false, location: "Hangar 4", notes: nil)
  _ = try await core.createCalendarEvent(
    title: "Zeppelin retrospective", startDate: past, endDate: nil, startTime: nil,
    endTime: nil, allDay: true, location: nil, notes: nil)
  #expect(store.calendarTimeline == nil)

  let days = await store.searchCalendarDays(matching: "  zeppelin ")

  #expect(days.map(\.key) == [future, past])
  #expect(await store.searchCalendarDays(matching: "hangar").count == 1)
  #expect(await store.searchCalendarDays(matching: "   ").isEmpty)
  #expect(await store.searchCalendarDays(matching: "quokka").isEmpty)
}

@MainActor
@Test("Opening a recurring series from a search result opens its occurrence in the loaded window")
func calendarSearchResultOfASeriesOpensItsOccurrence() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  let today = store.logicalTodayDateString
  let series = try await core.createCalendarEvent(
    title: "Zeppelin standup", startDate: today, endDate: nil, startTime: "09:00",
    endTime: "09:15", allDay: false, location: nil, notes: nil,
    recurrence: TaskRecurrenceRule(freq: .daily), timezone: nil, url: nil, color: nil,
    eventType: nil, personName: nil, attendees: nil)
  let row = try #require(
    await store.searchCalendarDays(matching: "zeppelin").first?.events.first)
  #expect(row.id == series.id)

  // The window is not loaded yet, so there is nothing to open.
  store.selectCalendarEvent(row)
  #expect(store.selectedCalendarEvent == nil)
  #expect(store.isCalendarEventSelected(row))

  // Loading it lists the series as occurrences; the selection moves onto the
  // one the row stands for.
  try await store.refreshCalendarTimeline(ingestingEventKit: false)
  let open = try #require(store.selectedCalendarEvent)
  #expect(open.id != row.id)
  #expect(open.eventID == series.id)
  #expect(open.startDate == today)
  #expect(store.selectedCalendarEventID == open.id)
  #expect(store.isCalendarEventSelected(row))

  // With the window already loaded, the selection resolves at once.
  store.clearSelectedCalendarEvent()
  store.selectCalendarEvent(row)
  #expect(store.selectedCalendarEvent?.id == open.id)
}

@MainActor
@Test("Opening a one-off event from a search result keeps its own id")
func calendarSearchResultOfAOneOffEventKeepsItsID() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  let today = store.logicalTodayDateString
  _ = try await core.createCalendarEvent(
    title: "Zeppelin inspection", startDate: today, endDate: nil, startTime: "10:00",
    endTime: "11:00", allDay: false, location: nil, notes: nil)
  let row = try #require(
    await store.searchCalendarDays(matching: "zeppelin").first?.events.first)
  try await store.refreshCalendarTimeline(ingestingEventKit: false)

  store.selectCalendarEvent(row)

  #expect(store.selectedCalendarEvent?.id == row.id)
  #expect(store.isCalendarEventSelected(row))
}

@Test("A series row and its occurrence are the same event only at the same recurrence slot")
func seriesRowAndOccurrenceShareASlot() {
  func recurring(id: String, seriesID: String?, slot: String) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id, seriesID: seriesID, occurrenceDate: slot, title: "Standup", source: "canonical",
      editable: true, startDate: slot, startTime: "09:00", endDate: slot, endTime: nil,
      allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
      isRecurring: seriesID == nil)
  }
  let master = recurring(id: "series", seriesID: nil, slot: "2026-06-01")
  let first = recurring(id: "occurrence-1", seriesID: "series", slot: "2026-06-01")
  let second = recurring(id: "occurrence-2", seriesID: "series", slot: "2026-06-02")

  #expect(master.isSameEvent(as: first))
  #expect(first.isSameEvent(as: master))
  #expect(!master.isSameEvent(as: second))
  #expect(first.isSameEvent(as: first))
  #expect(
    !searchEvent(id: "a", title: "One", startDate: "2026-06-01")
      .isSameEvent(as: searchEvent(id: "b", title: "One", startDate: "2026-06-01")))
}

@MainActor
@Test("Find in the Calendar workspace stays there and asks for its event search")
func findInTheCalendarKeepsTheCalendar() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.selection = .calendar

  store.beginSearch()

  #expect(store.selection == .calendar)
  #expect(store.isSearchFocusRequested)
  #expect(store.workspaceSearchPrompt(for: .calendar) != nil)
}

@MainActor
@Test("A calendar search ends when the person leaves the Calendar")
func calendarSearchEndsWithTheWorkspace() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.selection = .calendar
  store.searchText = "dentist"
  #expect(store.hasActiveSearch)

  store.selection = .today

  #expect(store.searchText.isEmpty)
}

private func source(_ path: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: path)
  return try String(contentsOf: url, encoding: .utf8)
}

@Test("The Calendar workspace covers the grid with the results and ends the search when a toolbar action moves it")
func calendarWorkspaceSearchOverlaysTheGrid() throws {
  let text = try source("Sources/LorvexApple/Views/CalendarWorkspaceView.swift")

  // The results overlay the grid, so closing the search returns to the period
  // and scroll position the person left.
  let grid = try #require(text.range(of: "switch mode {"))
  let hidden = try #require(text.range(of: ".accessibilityHidden(store.hasActiveSearch)"))
  let results = try #require(text.range(of: "CalendarSearchResultsView("))
  #expect(grid.lowerBound < hidden.lowerBound)
  #expect(hidden.lowerBound < results.lowerBound)
  #expect(text.contains(".overlay {"))

  // The steps, Today button, and mode picker stay in the toolbar beside the
  // field; each ends the search instead of changing a grid nobody can see.
  #expect(text.contains(".onChange(of: anchorDate)"))
  #expect(text.contains(".onChange(of: mode)"))
}
