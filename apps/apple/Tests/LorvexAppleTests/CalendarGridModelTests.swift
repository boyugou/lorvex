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
func calendarGridModelDoesNotRenderMidnightEndSliverOnTheNextDay() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 19)))

  // A timed event 22:00 Jun 19 → 00:00 Jun 20 (ends exactly at midnight).
  let days = CalendarGridModel.buildDays(
    rangeStart: start,
    dayCount: 2,
    calendar: calendar,
    events: [
      calendarGridEvent(
        id: "late-night",
        title: "Late night",
        startDate: "2026-06-19",
        startTime: "22:00",
        endTime: "00:00",
        endDate: "2026-06-20"
      )
    ],
    tasks: [],
    dayKeyFor: { calendarGridYMD.string(from: $0) }
  )

  // Jun 19 shows the 22:00→24:00 block; Jun 20 shows NOTHING (no 00:00–00:20
  // sliver), matching Apple Calendar's single-day presence for a midnight end.
  let day19 = try #require(days.first { $0.dayKey == "2026-06-19" })
  let day20 = try #require(days.first { $0.dayKey == "2026-06-20" })
  #expect(day19.timedBlocks.map(\.event.id) == ["late-night"])
  #expect(day19.timedBlocks.first?.startMin == 22 * 60)
  #expect(day19.timedBlocks.first?.endMin == 1440)
  #expect(day20.timedBlocks.isEmpty)
}

// A timed event of 24 hours or more reads as days: it sits in the all-day
// strip on each day it takes time on and leaves the time axes alone. A shorter
// event that runs past midnight is drawn as two blocks, each marked with its
// part and showing the time that part has: the first day the event's start,
// the last day when it ends. An event within one day, or one that ends at
// midnight, is drawn whole with its range.
@Test
func calendarGridModelPlacesEventsAcrossDaysByTheirLength() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 19)))

  let days = CalendarGridModel.buildDays(
    rangeStart: start,
    dayCount: 3,
    calendar: calendar,
    events: [
      calendarGridEvent(
        id: "retreat", title: "Retreat", startDate: "2026-06-19", startTime: "22:00",
        endTime: "01:00", endDate: "2026-06-21"),
      calendarGridEvent(
        id: "shift", title: "Shift", startDate: "2026-06-20", startTime: "08:00",
        endTime: "08:00", endDate: "2026-06-21"),
      calendarGridEvent(
        id: "flight", title: "Night flight", startDate: "2026-06-19", startTime: "22:30",
        endTime: "01:30", endDate: "2026-06-20"),
      calendarGridEvent(
        id: "late-night", title: "Late night", startDate: "2026-06-20", startTime: "21:00",
        endTime: "00:00", endDate: "2026-06-21"),
      calendarGridEvent(
        id: "standup", title: "Standup", startDate: "2026-06-21", startTime: "09:00",
        endTime: "09:30"),
    ],
    tasks: [],
    dayKeyFor: { calendarGridYMD.string(from: $0) }
  )

  func column(_ day: String) throws -> CalendarGridDay {
    try #require(days.first { $0.dayKey == day })
  }
  func block(_ id: String, on day: String) throws -> CalendarGridTimedBlock {
    try #require(try column(day).timedBlocks.first { $0.event.id == id })
  }
  #expect(try column("2026-06-19").allDayEvents.map(\.id) == ["retreat"])
  #expect(try column("2026-06-20").allDayEvents.map(\.id) == ["retreat", "shift"])
  #expect(try column("2026-06-21").allDayEvents.map(\.id) == ["retreat", "shift"])
  #expect(days.allSatisfy { day in
    !day.timedBlocks.contains { ["retreat", "shift"].contains($0.event.id) }
  })
  // In the strip a timed event of a day or more shows its start on its first
  // day and its end on its last; a day in between shows no time.
  let retreat = try #require(try column("2026-06-19").allDayEvents.first)
  #expect(retreat.allDayStripTimeLabel(on: "2026-06-19") == lorvexClockTimeLabel("22:00"))
  #expect(retreat.allDayStripTimeLabel(on: "2026-06-20") == nil)
  let retreatEnd = try #require(retreat.allDayStripTimeLabel(on: "2026-06-21"))
  #expect(retreatEnd.contains(lorvexClockTimeLabel("01:00")))
  #expect(retreatEnd != lorvexClockTimeLabel("01:00"))
  let offsite = CalendarTimelineEvent(
    id: "offsite", title: "Offsite", source: "lorvex", editable: true, startDate: "2026-06-19",
    startTime: nil, endDate: "2026-06-20", endTime: nil, allDay: true, location: nil, color: nil,
    eventType: "event", timezone: nil, isRecurring: false)
  #expect(offsite.allDayStripTimeLabel(on: "2026-06-19") == nil)

  let first = try block("flight", on: "2026-06-19")
  let last = try block("flight", on: "2026-06-20")
  #expect(first.part == .firstDay)
  #expect(last.part == .lastDay)
  #expect(first.timeLabel == lorvexClockTimeLabel("22:30"))
  #expect(last.timeLabel?.contains(lorvexClockTimeLabel("01:30")) == true)
  #expect(last.timeLabel != lorvexClockTimeLabel("01:30"))
  #expect(first.rangeLabel == nil)
  #expect(last.rangeLabel == nil)

  let lateNight = try block("late-night", on: "2026-06-20")
  #expect(lateNight.part == .whole)
  #expect(lateNight.timeLabel == lorvexClockTimeLabel("21:00"))
  #expect(lateNight.rangeLabel == lorvexClockRangeLabel(startMinutes: 21 * 60, endMinutes: 1440))
  let standup = try block("standup", on: "2026-06-21")
  #expect(standup.part == .whole)
  #expect(
    standup.rangeLabel == lorvexClockRangeLabel(startMinutes: 9 * 60, endMinutes: 9 * 60 + 30))
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
  endTime: String?,
  endDate: String? = nil
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: id,
    title: title,
    source: "lorvex",
    editable: true,
    startDate: startDate,
    startTime: startTime,
    endDate: endDate,
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
  plannedDate: Date? = nil,
  plannedTime: Range<Int>? = nil,
  status: LorvexTask.Status = .open
) -> LorvexTask {
  LorvexTask(
    id: id,
    title: id,
    notes: "",
    priority: .p3,
    status: status,
    dueDate: dueDate,
    plannedDate: plannedDate,
    plannedTime: plannedTime,
    estimatedMinutes: nil,
    tags: []
  )
}

@Test
func calendarGridModelPlacesTimedTasksOnTheTimeAxisAndOutOfTheAllDayStrip() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 19)))
  let planned = try #require(calendarGridYMD.date(from: "2026-06-19"))
  let brief = calendarGridTask(
    id: "brief", dueDate: nil, plannedDate: planned, plannedTime: 7 * 60..<8 * 60)

  let days = CalendarGridModel.buildDays(
    rangeStart: start,
    dayCount: 1,
    calendar: calendar,
    events: [
      calendarGridEvent(
        id: "standup", title: "Standup", startDate: "2026-06-19", startTime: "09:00", endTime: "10:00")
    ],
    tasks: [
      brief,
      calendarGridTask(id: "untimed", dueDate: nil, plannedDate: planned),
      calendarGridTask(
        id: "shipped", dueDate: nil, plannedDate: planned, plannedTime: 11 * 60..<12 * 60,
        status: .completed),
      calendarGridTask(
        id: "dropped", dueDate: nil, plannedDate: planned, plannedTime: 13 * 60..<14 * 60,
        status: .cancelled),
      brief,
    ],
    dayKeyFor: { calendarGridYMD.string(from: $0) }
  )

  let day = try #require(days.first)
  // Open and completed timed tasks become blocks (the completed one marked
  // done); a cancelled task is not drawn, and a task passed twice is drawn once.
  #expect(day.taskBlocks.map(\.task.id) == ["brief", "shipped"])
  #expect(day.taskBlocks.map(\.isDone) == [false, true])
  #expect(day.taskBlocks.first?.startMin == 7 * 60)
  #expect(day.taskBlocks.first?.endMin == 8 * 60)
  #expect(day.taskBlocks.first?.id == "task:brief#2026-06-19")
  // A task drawn on the clock leaves the all-day strip; an untimed one stays.
  #expect(day.scheduledTasks.map(\.id) == ["untimed"])
  #expect(day.timedBlocks.map(\.event.id) == ["standup"])
  // The task block is the earliest thing on the axis and moves the anchor.
  #expect(day.earliestBlockStart == 7 * 60)
  #expect(CalendarGridModel.initialScrollAnchorHour(for: days) == 0)
  #expect(
    CalendarGridModel.initialScrollAnchorHour(
      for: days, todayKey: "2026-06-19", nowMinute: 14 * 60) == 7)
}

@Test
func calendarGridModelPacksTimedTasksIntoTheSameLanesAsEvents() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 19)))
  let friday = try #require(calendarGridYMD.date(from: "2026-06-19"))
  let saturday = try #require(calendarGridYMD.date(from: "2026-06-20"))
  let outside = try #require(calendarGridYMD.date(from: "2026-07-01"))

  let days = CalendarGridModel.buildDays(
    rangeStart: start,
    dayCount: 2,
    calendar: calendar,
    events: [
      calendarGridEvent(
        id: "standup", title: "Standup", startDate: "2026-06-19", startTime: "09:00", endTime: "10:00")
    ],
    tasks: [
      calendarGridTask(
        id: "brief", dueDate: nil, plannedDate: friday, plannedTime: 9 * 60 + 30..<10 * 60 + 30,
        status: .inProgress),
      calendarGridTask(
        id: "quick", dueDate: nil, plannedDate: saturday, plannedTime: 9 * 60 + 30..<9 * 60 + 35),
      calendarGridTask(
        id: "later", dueDate: nil, plannedDate: outside, plannedTime: 9 * 60..<10 * 60),
    ],
    dayKeyFor: { calendarGridYMD.string(from: $0) }
  )

  let fridayColumn = try #require(days.first)
  let event = try #require(fridayColumn.timedBlocks.first)
  let block = try #require(fridayColumn.taskBlocks.first)
  #expect(event.laneCount == 2 && block.laneCount == 2)
  #expect(event.lane == 0 && block.lane == 1)

  // A block shorter than the render minimum reports its real end and is drawn
  // to the minimum, like an event.
  let saturdayColumn = try #require(days.last)
  #expect(saturdayColumn.taskBlocks.map(\.task.id) == ["quick"])
  #expect(saturdayColumn.taskBlocks.first?.endMin == 9 * 60 + 35)
  #expect(
    saturdayColumn.taskBlocks.first?.drawnEndMin
      == 9 * 60 + 30 + CalendarGridModel.minBlockMinutes)
  #expect(saturdayColumn.isEmpty == false)
  #expect(days.flatMap(\.taskBlocks).map(\.task.id).contains("later") == false)
}
