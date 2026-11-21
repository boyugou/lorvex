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
  // The list itself keeps Today's order.
  #expect(page.items.map(\.id) == ["first", "timed"])
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

@Test("Today offers other flexible tasks without selecting them by default")
func calmTodayOverflowAlternatives() throws {
  let page = Fixture.page(tasks: [
    Fixture.task("pinned", due: Fixture.day, estimate: 120),
    Fixture.task("alternate", estimate: 40), Fixture.task("suggested", estimate: 90),
  ], now: 9 * 60, workingHours: 9 * 60..<12 * 60)
  let load = try #require(page.overbooked)
  #expect(load.candidates.map(\.id) == ["suggested"])
  #expect(load.alternatives.map(\.id) == ["alternate"])
  #expect(load.planningRows.map(\.id) == ["suggested", "alternate"])
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

@Suite
struct TodayWorkCueTests {
  private func cue(_ tasks: [LorvexTask], _ events: [CalendarTimelineEvent], at minute: Int?,
    blocked: Set<String> = []) -> TodayWorkCue? {
    TodayWorkCue.resolve(
      lead: Fixture.page(tasks: tasks, events: events, now: minute).lead,
      blocked: blocked, events: events, day: Fixture.day, nowMinutes: minute)
  }

  @Test func resumeBetweenAppointments() throws {
    let task = Fixture.task("draft", status: .inProgress)
    let standup = Fixture.event("Standup", start: "09:30", end: "10:00")
    let review = Fixture.event("Review", start: "10:35", end: "11:00")
    let events = [review, Fixture.event("Trip", start: nil, allDay: true), standup]
    #expect(cue([task], events, at: 599) == nil)
    let result = try #require(cue([task], events, at: 600))
    #expect(result.action == .resume)
    #expect(result.bringsTaskToTop)
    #expect(result.upcoming?.title == "Review")
    #expect(result.upcoming?.minutesAway == 35)
    #expect(cue([task], events, at: 635) == nil)
    #expect(cue([task], events, at: 660)?.upcoming == nil)
    #expect(cue([task], [], at: 690)?.action == .resume)
  }

  @Test func showConflictsInPlaceAndStartOnlyAtUsableTimes() {
    let timed = Fixture.task("draft", time: 600..<660)
    let review = Fixture.event("Review", start: "10:30", end: "11:00")
    #expect(cue([timed], [review], at: 590)?.action == .reviewConflict(event: "Review"))
    #expect(cue([timed], [review], at: 590)?.bringsTaskToTop == false)
    #expect(cue([timed], [review], at: 600)?.action == .start)
    #expect(cue([timed], [review], at: 600)?.upcoming?.minutesAway == 30)
    #expect(cue([timed], [review], at: 630)?.action == .reviewConflict(event: "Review"))
    #expect(cue([timed], [review], at: 660) == nil)
    #expect(cue([timed], [], at: 600, blocked: ["draft"]) == nil)
    #expect(cue([timed], [], at: 590) == nil)
    #expect(cue([Fixture.task("no plan")], [], at: 600) == nil)
    #expect(cue([Fixture.task("started", status: .inProgress)], [], at: nil) == nil)
    #expect(cue([Fixture.task("done", status: .completed)], [], at: 600) == nil)
  }

  @Test func midnightAndPointEvents() {
    let task = Fixture.task("task", status: .inProgress)
    var overnight = Fixture.event("Travel", start: "22:00", end: "09:00")
    overnight.startDate = "2026-05-22"
    #expect(cue([task], [overnight], at: 539) == nil)
    #expect(cue([task], [overnight], at: 540)?.action == .resume)
    let point = Fixture.event("Reminder", start: "10:00", end: "10:00")
    #expect(cue([task], [point], at: 600)?.action == .resume)
    let reminder = Fixture.event("Collect parcel", start: "10:00")
    #expect(cue([task], [reminder], at: 595)?.upcoming?.minutesAway == 5)
    #expect(cue([task], [reminder], at: 605)?.action == .resume)
  }

  @Test func elapsedTimeAcrossTheRepeatedClockHour() throws {
    let day = "2026-11-01"
    let date = ISO8601DateFormatter()
    let first0130 = try #require(date.date(from: "2026-11-01T08:30:00Z"))
    let second0115 = try #require(date.date(from: "2026-11-01T09:15:00Z"))
    var event = Fixture.event("Call", start: "01:15", end: "01:40")
    event.startDate = day
    event.endDate = day
    event.projection = CalendarEventProjection(timezone: "America/Los_Angeles", start: second0115,
      end: second0115.addingTimeInterval(1500))
    let lead = LorvexCalmToday.Item(task: Fixture.task("notes", status: .inProgress))
    let first = TodayWorkCue.resolve(lead: lead, blocked: [], events: [event], day: day,
      nowMinutes: 90, now: first0130)
    #expect(first?.upcoming?.minutesAway == 45)
    #expect(TodayWorkCue.resolve(lead: lead, blocked: [], events: [event], day: day,
      nowMinutes: 75, now: second0115) == nil)
  }
}
