import Foundation
import LorvexCore
import Testing

@Test
func calendarGridModelRejectsOutOfRangeClockTimes() {
  #expect(CalendarGridModel.parseMinutes("00:00") == 0)
  #expect(CalendarGridModel.parseMinutes("04:22") == 262)
  #expect(CalendarGridModel.parseMinutes("23:59") == 1439)

  #expect(CalendarGridModel.parseMinutes("24:00") == nil)
  #expect(CalendarGridModel.parseMinutes("25:00") == nil)
  #expect(CalendarGridModel.parseMinutes("12:60") == nil)
  #expect(CalendarGridModel.parseMinutes("-1:00") == nil)
}

@Test
func calendarGridModelKeepsInvalidTimedEventsOutOfTheTimeAxis() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 19)))

  let days = CalendarGridModel.buildDays(
    rangeStart: start,
    dayCount: 1,
    calendar: calendar,
    events: [
      calendarGridEvent(
        id: "bad-clock",
        title: "Bad clock",
        startDate: "2026-06-19",
        startTime: "25:00",
        endTime: "26:00"
      ),
      calendarGridEvent(
        id: "airport",
        title: "To Airport",
        startDate: "2026-06-19",
        startTime: "04:22",
        endTime: "06:22"
      ),
    ],
    tasks: [],
    dayKeyFor: { calendarGridYMD.string(from: $0) }
  )

  let day = try #require(days.first)
  #expect(day.timedBlocks.map(\.event.id) == ["airport"])
  #expect(day.timedBlocks.first?.startMin == 262)
  #expect(day.allDayEvents.map(\.id) == ["bad-clock"])
  #expect(CalendarGridModel.initialScrollAnchorHour(for: days) == 0)
}

@Test
func calendarGridModelAnchorsToTodaysEarlyEventInsteadOfHidingItAboveTheFold() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 19)))

  let days = CalendarGridModel.buildDays(
    rangeStart: start,
    dayCount: 1,
    calendar: calendar,
    events: [
      calendarGridEvent(
        id: "dawn-flight",
        title: "Dawn flight",
        startDate: "2026-06-19",
        startTime: "05:00",
        endTime: "07:00"
      )
    ],
    tasks: [],
    dayKeyFor: { calendarGridYMD.string(from: $0) }
  )

  // Opened at 2pm: a now-only anchor would scroll to 13:00 and hide the 5am
  // flight above the fold. The smart anchor opens at the event's hour instead.
  #expect(
    CalendarGridModel.initialScrollAnchorHour(
      for: days, todayKey: "2026-06-19", nowMinute: 14 * 60) == 5)

  // When today's earliest event is after the now-anchor, the familiar
  // now-anchored position (one hour before now) is preserved.
  #expect(
    CalendarGridModel.initialScrollAnchorHour(
      for: days, todayKey: "2026-06-19", nowMinute: 3 * 60) == 2)
}

@Test
func calendarGridModelUsesPlannedFirstStorageDaysWithoutTimezoneShift() throws {
  let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = timeZone
  let formatter = DateFormatter()
  formatter.calendar = calendar
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = timeZone
  formatter.dateFormat = "yyyy-MM-dd"
  let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 26)))

  let dueOnly = calendarGridTask(
    id: "due-only",
    dueDate: LorvexDateFormatters.ymdUTC.date(from: "2026-05-27"))
  let plannedOnly = calendarGridTask(
    id: "planned-only",
    dueDate: nil,
    plannedDate: LorvexDateFormatters.ymdUTC.date(from: "2026-05-28"))
  let plannedWins = calendarGridTask(
    id: "planned-wins",
    dueDate: LorvexDateFormatters.ymdUTC.date(from: "2026-05-26"),
    plannedDate: LorvexDateFormatters.ymdUTC.date(from: "2026-05-29"))

  let days = CalendarGridModel.buildDays(
    rangeStart: start,
    dayCount: 4,
    calendar: calendar,
    events: [],
    tasks: [dueOnly, plannedOnly, plannedWins],
    dayKeyFor: { formatter.string(from: $0) }
  )

  #expect(days.first { $0.dayKey == "2026-05-26" }?.scheduledTasks.isEmpty == true)
  #expect(days.first { $0.dayKey == "2026-05-27" }?.scheduledTasks.map(\.id) == ["due-only"])
  #expect(days.first { $0.dayKey == "2026-05-28" }?.scheduledTasks.map(\.id) == ["planned-only"])
  #expect(days.first { $0.dayKey == "2026-05-29" }?.scheduledTasks.map(\.id) == ["planned-wins"])
}

private let calendarGridYMD: DateFormatter = {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter
}()

private func calendarGridEvent(
  id: String,
  title: String,
  startDate: String,
  startTime: String?,
  endTime: String?
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: id,
    title: title,
    source: "lorvex",
    editable: true,
    startDate: startDate,
    startTime: startTime,
    endDate: nil,
    endTime: endTime,
    allDay: false,
    location: nil,
    color: nil,
    eventType: "event",
    timezone: nil,
    isRecurring: false
  )
}

private func calendarGridTask(
  id: String,
  dueDate: Date?,
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
