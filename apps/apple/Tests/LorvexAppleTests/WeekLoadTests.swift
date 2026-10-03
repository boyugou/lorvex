import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

private func meeting(_ day: String, _ start: String, _ end: String, endDay: String? = nil) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: UUID().uuidString, title: "Meeting", source: "canonical", editable: true,
    startDate: day, startTime: start, endDate: endDay, endTime: end, allDay: false,
    location: nil, color: nil, eventType: "event", timezone: nil, isRecurring: false,
    recurrenceRule: nil)
}

private func task(
  minutes: Int?, status: LorvexTask.Status = .open, title: String = "Task",
  priority: LorvexTask.Priority = .p2, due: String? = nil
) -> LorvexTask {
  LorvexTask(
    id: UUID().uuidString, title: title, notes: "", priority: priority, status: status,
    dueDate: due.flatMap { LorvexDateFormatters.ymdUTC.date(from: $0) },
    estimatedMinutes: minutes, tags: [])
}

private func build(_ days: [LorvexWeekLoad.DayInput], today: String = "2026-09-21") -> LorvexWeekLoad {
  LorvexWeekLoad.build(days: days, todayKey: today, workStart: 9 * 60, workEnd: 17 * 60)
}

@Test("Meetings merge and clip to the working window; tasks pack around them")
func weekLoadPacksTasksAroundMeetings() {
  let load = build([
    .init(
      key: "2026-09-21",
      events: [meeting("2026-09-21", "08:00", "10:00"), meeting("2026-09-21", "09:30", "11:00")],
      tasks: [task(minutes: 90), task(minutes: 30), task(minutes: 45, status: .completed)])
  ])
  let day = load.days[0]
  #expect(day.meetingMinutes == 120)
  #expect(day.taskCount == 2)
  #expect(day.taskMinutes == 120)
  #expect(day.overMinutes == 0)
  #expect(day.freeMinutes == 240)
  #expect(day.segments.map(\.kind) == [.meeting, .task])
  #expect(day.segments[1].start == 11 * 60)
  #expect(day.segments[1].end == 13 * 60)
  #expect(load.range == (9 * 60)...(17 * 60))
  #expect(load.headline == .fullest(key: "2026-09-21", freeMinutes: 240))
}

@Test("An event without an end time takes the grid's hour; a zero-length one takes no time; a filled day is busy")
func weekLoadMeasuresEventsByTheirTimeOnTheDay() {
  let open = CalendarTimelineEvent(
    id: "open", title: "Open-ended", source: "canonical", editable: true,
    startDate: "2026-09-21", startTime: "10:00", endDate: nil, endTime: nil, allDay: false,
    location: nil, color: nil, eventType: "event", timezone: nil, isRecurring: false,
    recurrenceRule: nil)
  let load = build([
    .init(
      key: "2026-09-21",
      events: [open, meeting("2026-09-21", "14:00", "14:00")],
      tasks: []),
    .init(
      key: "2026-09-22",
      events: [meeting("2026-09-21", "18:00", "09:00", endDay: "2026-09-23")],
      tasks: []),
  ])
  #expect(load.days[0].meetingMinutes == CalendarGridModel.defaultEventDurationMinutes)
  #expect(load.days[0].freeMinutes == 8 * 60 - 60, "not busy from 10:00 AM to the end of the day")
  #expect(load.days[1].meetingMinutes == 8 * 60, "the trip fills the working day it spans")
}

@Test("Estimates that do not fit run past the window as overrun, widening the shared scale")
func weekLoadMarksOverbookedDays() {
  let load = build([
    .init(key: "2026-09-21", events: [], tasks: [task(minutes: 60)]),
    .init(
      key: "2026-09-24",
      events: [meeting("2026-09-24", "09:00", "15:00")],
      tasks: [task(minutes: 170)]),
    .init(key: "2026-09-25", events: [], tasks: [task(minutes: 520)]),
    .init(key: "2026-09-26", events: [], tasks: [task(minutes: 500)]),
  ])
  let thursday = load.days[1]
  #expect(thursday.overMinutes == 50)
  let last = thursday.segments.last
  #expect(last?.kind == .overrun)
  #expect(last?.start == 1_020)
  #expect(last?.end == 1_070)
  #expect(load.days[2].overMinutes == 40)
  // Twenty minutes over is inside the tolerance: estimates are rough.
  #expect(load.days[3].overMinutes == 0)
  #expect(load.range.upperBound == 1_070)
  #expect(load.headline == .overbooked(key: "2026-09-24", minutes: 50, otherDays: 1))
}

@Test("The headline ignores days already past, and an empty week is open")
func weekLoadHeadlineLooksAhead() {
  let past = build(
    [
      .init(key: "2026-09-20", events: [], tasks: [task(minutes: 600)]),
      .init(key: "2026-09-21", events: [], tasks: []),
    ])
  #expect(past.headline == .open)
  #expect(past.days[1].isToday)

  let overnight = build([
    .init(
      key: "2026-09-22", events: [meeting("2026-09-21", "22:00", "00:00", endDay: "2026-09-22")],
      tasks: [])
  ])
  #expect(overnight.days[0].meetingMinutes == 0)
}

@Test("On today, time already gone is neither free nor packed")
func weekLoadCountsTodayFromNow() {
  let load = LorvexWeekLoad.build(
    days: [
      .init(
        key: "2026-09-21", events: [meeting("2026-09-21", "10:00", "11:00")],
        tasks: [task(minutes: 60)])
    ],
    todayKey: "2026-09-21", workStart: 9 * 60, workEnd: 17 * 60, nowMinutes: 13 * 60)
  let day = load.days[0]
  #expect(day.meetingMinutes == 0)
  #expect(day.freeMinutes == 180)
  #expect(day.segments.last?.start == 13 * 60)
}

@Test("A few minutes over is not overbooked")
func weekLoadToleratesSmallOverruns() {
  let load = build([.init(key: "2026-09-21", events: [], tasks: [task(minutes: 490)])])
  #expect(load.days[0].overMinutes == 0)
  #expect(load.headline == .fullest(key: "2026-09-21", freeMinutes: 0))
}

@Test("An overbooked day suggests moving its least urgent task to the roomiest day that fits it")
func weekLoadSuggestsOneMove() throws {
  let load = build([
    .init(
      key: "2026-09-21", events: [meeting("2026-09-21", "09:00", "14:00")],
      tasks: [
        task(minutes: 120, title: "Urgent", priority: .p1),
        task(minutes: 90, title: "Due today", priority: .p3, due: "2026-09-21"),
        task(minutes: 60, title: "Later", priority: .p3),
      ]),
    .init(key: "2026-09-22", events: [meeting("2026-09-22", "09:00", "16:30")], tasks: []),
    .init(key: "2026-09-23", events: [meeting("2026-09-23", "09:00", "12:00")], tasks: []),
  ])
  #expect(load.headline == .overbooked(key: "2026-09-21", minutes: 90, otherDays: 0))
  let move = try #require(load.suggestion)
  #expect(move.title == "Later")
  #expect(move.toKey == "2026-09-23")
  #expect(move.minutes == 60)
}

@Test("No move is suggested past a task's due date, before today, or without an overbooked day")
func weekLoadSuggestionRespectsLimits() {
  let blocked = build(
    [
      .init(key: "2026-09-20", events: [], tasks: []),
      .init(
        key: "2026-09-21", events: [meeting("2026-09-21", "09:00", "16:00")],
        tasks: [task(minutes: 120, due: "2026-09-21"), task(minutes: 60, due: "2026-09-21")]),
      .init(key: "2026-09-22", events: [], tasks: []),
    ])
  #expect(blocked.suggestion == nil)

  let early = build(
    [
      .init(key: "2026-09-20", events: [], tasks: []),
      .init(
        key: "2026-09-21", events: [meeting("2026-09-21", "09:00", "16:00")],
        tasks: [task(minutes: 120, due: "2026-09-22")]),
      .init(key: "2026-09-22", events: [meeting("2026-09-22", "09:00", "16:00")], tasks: []),
      .init(key: "2026-09-23", events: [], tasks: []),
    ])
  #expect(early.suggestion == nil)

  let calm = build([.init(key: "2026-09-21", events: [], tasks: [task(minutes: 60)])])
  #expect(calm.suggestion == nil)
}

@Test("Days before today are past only in the week that holds today")
func weekLoadMarksDaysBeforeTodayPast() {
  let week = ["2026-09-27", "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"]
  let inputs = week.map { LorvexWeekLoad.DayInput(key: $0, events: [], tasks: []) }
  #expect(build(inputs, today: "2026-09-29").days.map(\.isPast) == [true, true, false, false, false])
  #expect(build(inputs, today: "2026-10-12").days.allSatisfy { !$0.isPast })
}
