import Foundation
import LorvexCore
import Testing

/// Rules for the Today page (``LorvexCalmToday/build``): the list keeps
/// Today's order, which task leads, what the facts line says, how much work is
/// left, and when the day is overbooked.
private enum Fixture {
  static let day = "2026-05-23"

  static func event(_ id: String, start: String?, end: String? = nil, allDay: Bool = false)
    -> CalendarTimelineEvent
  {
    CalendarTimelineEvent(
      id: id, eventID: id, supportsScopedMutation: false, title: id, source: "canonical",
      editable: true, startDate: day, startTime: start, endDate: day,
      endTime: end, allDay: allDay, location: nil, color: nil, eventType: "event",
      timezone: nil, isRecurring: false)
  }

  static func task(
    _ id: String, status: LorvexTask.Status = .open, due: String? = nil,
    time: Range<Int>? = nil, estimate: Int? = nil
  ) -> LorvexTask {
    LorvexTask(
      id: id, title: id, notes: "", priority: .p2, status: status,
      dueDate: due.map(utcMidnight), plannedDate: time == nil ? nil : utcMidnight(day),
      plannedTime: time, estimatedMinutes: estimate, tags: [])
  }

  static func utcMidnight(_ ymd: String) -> Date {
    LorvexDateFormatters.ymdUTC.date(from: ymd) ?? .distantPast
  }

  static func page(
    tasks: [LorvexTask] = [], events: [CalendarTimelineEvent] = [], done: Int = 0,
    now: Int?, workingHours: Range<Int>? = nil
  ) -> LorvexCalmToday {
    LorvexCalmToday.build(
      tasks: tasks, events: events, doneToday: done, nowMinutes: now, logicalDay: day,
      workingHours: workingHours)
  }
}

@Test("the list keeps Today's order and leaves out finished tasks")
func calmTodayKeepsTodaysOrder() {
  let page = Fixture.page(
    tasks: [
      Fixture.task("started", status: .inProgress),
      Fixture.task("open"),
      Fixture.task("finished", status: .completed),
      Fixture.task("dropped", status: .cancelled),
    ],
    now: 9 * 60)

  #expect(page.items.map(\.id) == ["started", "open"])
}

@Test("a task whose time contains the clock leads, with progress and minutes left")
func calmTodayRunningTimeLeads() throws {
  let page = Fixture.page(
    tasks: [Fixture.task("first"), Fixture.task("timed", time: 9 * 60..<10 * 60)],
    now: 9 * 60 + 15)

  let lead = try #require(page.lead)
  #expect(lead.id == "timed")
  #expect(lead.isRunning)
  #expect(lead.progress(nowMinutes: 9 * 60 + 15) == 0.25)
  #expect(lead.minutesLeft(nowMinutes: 9 * 60 + 15) == 45)
  // The list itself keeps Today's order; glances open with the lead.
  #expect(page.items.map(\.id) == ["first", "timed"])
  #expect(page.leadFirst.map(\.id) == ["timed", "first"])
}

@Test("with no time running, the list's first task leads")
func calmTodayFirstTaskLeadsWithoutARunningTime() {
  let page = Fixture.page(
    tasks: [Fixture.task("later", time: 14 * 60..<15 * 60), Fixture.task("other")],
    now: 12 * 60)

  #expect(page.leadID == "later")
  #expect(page.lead?.isRunning == false)
  #expect(page.lead?.progress(nowMinutes: 12 * 60) == 0)
  #expect(page.lead?.minutesLeft(nowMinutes: 12 * 60) == nil)
}

@Test("when two times contain the clock, the earlier start leads")
func calmTodayEarliestRunningTimeLeads() {
  let page = Fixture.page(
    tasks: [
      Fixture.task("short", time: 9 * 60 + 30..<10 * 60 + 30),
      Fixture.task("long", time: 9 * 60..<11 * 60),
    ],
    now: 10 * 60)

  #expect(page.leadID == "long")
  #expect(page.items.allSatisfy { $0.isRunning })
}

@Test("a day that is not today has no running time and no lead")
func calmTodayOtherDayHasNoClock() {
  let page = Fixture.page(
    tasks: [Fixture.task("first"), Fixture.task("timed", time: 9 * 60..<10 * 60)],
    now: nil, workingHours: 9 * 60..<18 * 60)

  #expect(page.leadID == nil)
  #expect(page.leadFirst.map(\.id) == ["first", "timed"])
  #expect(page.items.allSatisfy { !$0.isRunning })
  #expect(page.overbooked == nil)
}

@Test("the facts line reports an empty day, a finished day, and the day's tasks, work, and meetings")
func calmTodayFacts() {
  #expect(Fixture.page(now: 9 * 60).facts == .empty)
  #expect(Fixture.page(done: 2, now: 17 * 60).facts == .allDone(done: 2))

  let day = Fixture.page(
    tasks: [
      Fixture.task("estimated", estimate: 30),
      Fixture.task("timed", time: 13 * 60..<14 * 60),
      Fixture.task("unsized"),
    ],
    events: [
      Fixture.event("standup", start: "09:00", end: "09:15"),
      Fixture.event("sync", start: "13:00", end: "13:30"),
      Fixture.event("holiday", start: nil, allDay: true),
    ],
    now: 10 * 60)
  #expect(day.facts == .day(tasks: 3, workMinutes: 90, meetings: 1))

  let unsized = Fixture.page(tasks: [Fixture.task("a"), Fixture.task("b")], now: 10 * 60)
  #expect(unsized.facts == .day(tasks: 2, workMinutes: nil, meetings: 0))
}

@Test("the meetings ahead are the schedule's timed rows the clock has not cleared, across midnight too")
func calmTodayCountsMeetingsByTheirPartOfTheDay() {
  func spanning(_ id: String, _ from: String, _ start: String, _ to: String, _ end: String)
    -> CalendarTimelineEvent
  {
    CalendarTimelineEvent(
      id: id, eventID: id, supportsScopedMutation: false, title: id, source: "canonical",
      editable: true, startDate: from, startTime: start, endDate: to, endTime: end, allDay: false,
      location: nil, color: nil, eventType: "event", timezone: nil, isRecurring: false)
  }
  let events = [
    spanning("trip", "2026-05-22", "18:00", "2026-05-24", "09:00"),
    spanning("flight", "2026-05-22", "22:30", Fixture.day, "01:30"),
    spanning("late", Fixture.day, "21:00", "2026-05-24", "00:00"),
    spanning("redeye", Fixture.day, "23:00", "2026-05-24", "02:00"),
  ]
  let night = Fixture.page(tasks: [Fixture.task("a")], events: events, now: 60)
  #expect(
    night.facts == .day(tasks: 1, workMinutes: nil, meetings: 3),
    "the flight until 1:30 AM, the late session, and the red-eye; the trip fills the day")
  let evening = Fixture.page(tasks: [Fixture.task("a")], events: events, now: 22 * 60)
  #expect(evening.facts == .day(tasks: 1, workMinutes: nil, meetings: 2), "both run past 10:00 PM")
}

@Test("work counts what is left of a running time and the estimate of a time that passed")
func calmTodayWorkMinutes() {
  let page = Fixture.page(
    tasks: [
      Fixture.task("running", time: 9 * 60..<10 * 60),
      Fixture.task("passed", time: 8 * 60..<8 * 60 + 30, estimate: 45),
      Fixture.task("passedUnsized", time: 7 * 60..<7 * 60 + 30),
      Fixture.task("ahead", time: 11 * 60..<11 * 60 + 45, estimate: 10),
    ],
    now: 9 * 60 + 40)

  // 20 left of the running hour, the passed task's 45-minute estimate, the
  // unsized passed task's 30-minute time, and the 45-minute time still ahead.
  #expect(page.workMinutes == 20 + 45 + 30 + 45)
}

@Test("an overbooked day offers the least urgent untimed, estimated tasks that cover the excess")
func calmTodayOverbookedCandidates() throws {
  let page = Fixture.page(
    tasks: [
      Fixture.task("started", status: .inProgress, estimate: 240),
      Fixture.task("timed", time: 14 * 60..<16 * 60),
      Fixture.task("dueToday", due: Fixture.day, estimate: 120),
      Fixture.task("a", estimate: 60),
      Fixture.task("b", estimate: 90),
    ],
    events: [Fixture.event("review", start: "10:00", end: "11:00")],
    now: 9 * 60, workingHours: 9 * 60..<18 * 60)

  let overbooked = try #require(page.overbooked)
  // 630 minutes of work against 540 working minutes less a 60-minute meeting.
  #expect(overbooked.workMinutes == 630)
  #expect(overbooked.freeMinutes == 480)
  // Taken from the end until they cover the 150-minute excess, listed in
  // Today's order; the started, timed, and due-today tasks are never offered.
  #expect(overbooked.candidates.map(\.id) == ["a", "b"])
}

@Test("a day that fits, or whose working hours are over, is not overbooked")
func calmTodayNotOverbooked() {
  let fits = Fixture.page(
    tasks: [Fixture.task("a", estimate: 60), Fixture.task("b", estimate: 90)],
    now: 9 * 60, workingHours: 9 * 60..<18 * 60)
  #expect(fits.overbooked == nil)

  let evening = Fixture.page(
    tasks: [Fixture.task("a", estimate: 600)], now: 19 * 60, workingHours: 9 * 60..<18 * 60)
  #expect(evening.overbooked == nil)

  let noHours = Fixture.page(tasks: [Fixture.task("a", estimate: 600)], now: 9 * 60)
  #expect(noHours.overbooked == nil)
}

@Test("the briefing line is the stored briefing, trimmed, or nothing")
func calmTodayBriefingIsTrimmedOrAbsent() {
  #expect(LorvexCalmToday.briefing(from: "  Two deep-work blocks.\n") == "Two deep-work blocks.")
  #expect(LorvexCalmToday.briefing(from: "   \n") == nil)
  #expect(LorvexCalmToday.briefing(from: nil) == nil)
}
