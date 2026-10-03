import Foundation
import LorvexCore
import Testing

/// Ordering and marking rules for the day on the clock drawn beside Today
/// (``LorvexTodayTimeline/build(day:events:tasks:times:nowMinutes:)``).
private enum Fixture {
  /// The day every schedule here is built for.
  static let day = "2026-05-23"

  static func event(
    _ id: String, start: String?, end: String? = nil, allDay: Bool = false
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id, eventID: id, supportsScopedMutation: false, title: id, source: "canonical",
      editable: true, startDate: day, startTime: start, endDate: day,
      endTime: end, allDay: allDay, location: nil, color: nil, eventType: "event",
      timezone: nil, isRecurring: false)
  }

  /// A timed event from `start` on `startDate` to `end` on `endDate`.
  static func event(
    _ id: String, from startDate: String, _ start: String, to endDate: String, _ end: String
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id, eventID: id, supportsScopedMutation: false, title: id, source: "canonical",
      editable: true, startDate: startDate, startTime: start, endDate: endDate,
      endTime: end, allDay: false, location: nil, color: nil, eventType: "event",
      timezone: nil, isRecurring: false)
  }

  static func task(_ id: String) -> LorvexTask {
    LorvexTask(
      id: id, title: id, notes: "", priority: .p2, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: [])
  }

  /// The rows' identities, which encode both kind and subject.
  static func ids(_ items: [LorvexTodayTimelineItem]) -> [String] { items.map(\.id) }
}

@Test("all-day events lead, then timed events and timed tasks in clock order")
func timelineOrdersAllDayThenTimedRows() {
  let items = LorvexTodayTimeline.build(
    day: Fixture.day,
    events: [
      Fixture.event("late", start: "15:00", end: "16:00"),
      Fixture.event("allday", start: nil, allDay: true),
      Fixture.event("early", start: "09:00", end: "10:00"),
    ],
    tasks: [Fixture.task("timed")],
    times: ["timed": 11 * 60..<12 * 60],
    nowMinutes: nil)

  #expect(Fixture.ids(items) == ["event:allday", "event:early", "task:timed", "event:late"])
}

@Test("a task without a time on the day stays off the schedule")
func timelineLeavesUntimedTasksOut() {
  let items = LorvexTodayTimeline.build(
    day: Fixture.day,
    events: [],
    tasks: [Fixture.task("a"), Fixture.task("b")],
    times: ["a": 8 * 60..<9 * 60],
    nowMinutes: nil)

  #expect(
    Fixture.ids(items) == ["task:a"],
    "the list beside the schedule already shows every task; the schedule shows only timed ones")
  #expect(items.first?.timeLabel.isEmpty == false, "a timed task shows its start")
  #expect(items.first?.startMinutes == 8 * 60)
  #expect(items.first?.endMinutes == 9 * 60)
}

@Test("a time for a task the caller did not pass is ignored")
func timelineIgnoresTimesForMissingTasks() {
  let items = LorvexTodayTimeline.build(
    day: Fixture.day,
    events: [],
    tasks: [Fixture.task("kept")],
    times: ["kept": 8 * 60..<9 * 60, "removed": 10 * 60..<11 * 60],
    nowMinutes: nil)

  #expect(
    Fixture.ids(items) == ["task:kept"],
    "the rows come from the tasks the surface holds; a stray time must not add a row")
}

@Test("rows that share a start keep their arrival order, events before tasks")
func timelineKeepsArrivalOrderOnTies() {
  let items = LorvexTodayTimeline.build(
    day: Fixture.day,
    events: [
      Fixture.event("first", start: "09:00", end: "09:30"),
      Fixture.event("second", start: "09:00", end: "09:15"),
    ],
    tasks: [Fixture.task("x"), Fixture.task("y")],
    times: ["y": 9 * 60..<10 * 60, "x": 9 * 60..<9 * 60 + 30],
    nowMinutes: nil)

  #expect(Fixture.ids(items) == ["event:first", "event:second", "task:x", "task:y"])
}

@Test("the now row lands between the rows the clock has and has not reached")
func timelinePlacesNowBetweenPastAndUpcomingRows() {
  let items = LorvexTodayTimeline.build(
    day: Fixture.day,
    events: [
      Fixture.event("done", start: "09:00", end: "10:00"),
      Fixture.event("next", start: "14:00", end: "15:00"),
    ],
    tasks: [],
    times: [:],
    nowMinutes: 12 * 60)

  #expect(Fixture.ids(items) == ["event:done", "now", "event:next"])
}

@Test("no timed rows means no now marker")
func timelineOmitsNowWhenNothingIsTimed() {
  let items = LorvexTodayTimeline.build(
    day: Fixture.day,
    events: [Fixture.event("allday", start: nil, allDay: true)],
    tasks: [Fixture.task("a")], times: [:], nowMinutes: 12 * 60)

  #expect(Fixture.ids(items) == ["event:allday"], "a now marker alone would mark nothing")
}

@Test("a finished task whose time is over reads as past; one finished early keeps its place")
func timelineMarksFinishedTasksPastOnceTheirTimeEnds() {
  var early = Fixture.task("finishedEarly")
  early.status = .completed
  var done = Fixture.task("finished")
  done.status = .completed
  let items = LorvexTodayTimeline.build(
    day: Fixture.day,
    events: [],
    tasks: [done, early],
    times: ["finished": 9 * 60..<10 * 60, "finishedEarly": 13 * 60..<14 * 60],
    nowMinutes: 12 * 60)

  #expect(Set(items.filter(\.isPast).map(\.id)) == ["task:finished"])
}

@Test("the fold takes the finished rows that open the timed day, never all-day rows")
func earlierFoldTakesTheLeadingFinishedRun() {
  let items = LorvexTodayTimeline.build(
    day: Fixture.day,
    events: [
      Fixture.event("allday", start: nil, allDay: true),
      Fixture.event("standup", start: "08:00", end: "08:30"),
      Fixture.event("review", start: "10:00", end: "11:00"),
    ],
    tasks: [Fixture.task("missedTime")],
    times: ["missedTime": 9 * 60..<9 * 60 + 30],
    nowMinutes: 12 * 60)

  #expect(
    Fixture.ids(items) == ["event:allday", "event:standup", "task:missedTime", "event:review", "now"])
  // Only the standup opens the timed day finished; the review is past too but
  // follows a task still to do, so it stays in place.
  #expect(LorvexTodayTimeline.earlierFold(items) == 1..<2)
  #expect(LorvexTodayTimeline.earlierFold([]).isEmpty)
}

@Test("a finished event reads as past; a task whose time passed unfinished is still work")
func timelineMarksFinishedEventsButNotMissedTasksAsPast() {
  let items = LorvexTodayTimeline.build(
    day: Fixture.day,
    events: [
      Fixture.event("done", start: "09:00", end: "10:00"),
      Fixture.event("running", start: "11:30", end: "13:00"),
      Fixture.event("allday", start: nil, allDay: true),
    ],
    tasks: [Fixture.task("missedTime")],
    times: ["missedTime": 8 * 60..<8 * 60 + 30],
    nowMinutes: 12 * 60)

  let past = Set(items.filter(\.isPast).map(\.id))
  #expect(past == ["event:done"])
  #expect(
    !items.contains { $0.id == "task:missedTime" && $0.isPast },
    "a task whose time passed unfinished keeps reading as actionable")
  #expect(
    !items.contains { $0.id == "event:allday" && $0.isPast },
    "an all-day event covers the part of the day still ahead")
}

@Test("an overnight event that started the day before opens the timed rows and reads until its end")
func timelineShowsTheEndOfAnOvernightEventFromTheDayBefore() {
  let flight = Fixture.event("flight", from: "2026-05-22", "22:30", to: Fixture.day, "01:30")
  let build = { (now: Int) in
    LorvexTodayTimeline.build(
      day: Fixture.day, events: [flight, Fixture.event("standup", start: "09:00", end: "09:15")],
      tasks: [], times: [:], nowMinutes: now)
  }

  let night = build(60)
  #expect(Fixture.ids(night) == ["event:flight", "now", "event:standup"])
  let row = night[0]
  #expect(row.eventPart == .lastDay)
  #expect(row.startMinutes == 0, "the day's share of the event starts at midnight")
  #expect(row.endMinutes == 90)
  #expect(row.timeLabel == flight.timeLabel(for: .lastDay))
  #expect(row.timeLabel.contains(lorvexClockTimeLabel("01:30")), "the row says when the event ends")
  #expect(!row.timeLabel.contains(lorvexClockTimeLabel("22:30")), "not a start from the day before")
  #expect(!row.isPast, "the flight is still on at 1:00 AM")
  #expect(build(8 * 60)[0].isPast, "and over by 8:00 AM")
}

@Test("an overnight event on its first day runs to midnight and never reads as past that day")
func timelineRunsAnOvernightEventToMidnightOnItsFirstDay() {
  let redeye = Fixture.event("redeye", from: Fixture.day, "22:30", to: "2026-05-24", "01:30")
  for now in [2 * 60, 23 * 60 + 50] {
    let items = LorvexTodayTimeline.build(
      day: Fixture.day, events: [redeye], tasks: [], times: [:], nowMinutes: now)
    let row = items.first { $0.id == "event:redeye" }
    #expect(row?.eventPart == .firstDay)
    #expect(row?.startMinutes == 22 * 60 + 30)
    #expect(row?.endMinutes == 1440)
    #expect(row?.timeLabel == lorvexClockTimeLabel("22:30"))
    #expect(row?.isPast == false, "at \(now) minutes the event has not ended: it ends tomorrow")
  }
}

@Test("an event that ends at exactly midnight runs to the end of its day")
func timelineRunsAnEventEndingAtMidnightToTheEndOfTheDay() {
  let late = Fixture.event("late", from: Fixture.day, "21:00", to: "2026-05-24", "00:00")
  let items = LorvexTodayTimeline.build(
    day: Fixture.day, events: [late], tasks: [], times: [:], nowMinutes: 12 * 60)

  #expect(Fixture.ids(items) == ["now", "event:late"])
  let row = items[1]
  #expect(row.eventPart == .whole, "it takes time on its start day only")
  #expect(row.startMinutes == 21 * 60)
  #expect(row.endMinutes == 1440)
  #expect(!row.isPast, "an end of 00:00 is the end of the day, not its start")
}

@Test("a day that a longer event fills reads as an all-day row; its first and last days are timed")
func timelineShowsTheDaysALongEventTakes() {
  let trip = Fixture.event("trip", from: "2026-05-22", "19:00", to: "2026-05-24", "09:00")
  #expect(trip.dayPart(on: "2026-05-22") == .firstDay)
  #expect(trip.dayPart(on: Fixture.day) == .middleDay)
  #expect(trip.dayPart(on: "2026-05-24") == .lastDay)

  let middle = LorvexTodayTimeline.build(
    day: Fixture.day, events: [trip, Fixture.event("standup", start: "09:00", end: "09:15")],
    tasks: [], times: [:], nowMinutes: 23 * 60)
  #expect(Fixture.ids(middle) == ["event:trip", "event:standup", "now"])
  #expect(middle[0].eventPart == .middleDay)
  #expect(middle[0].startMinutes == nil, "the trip fills the day rather than sitting at a time")
  #expect(middle[0].timeLabel.isEmpty)
  #expect(!middle[0].isPast)

  let last = LorvexTodayTimeline.build(
    day: "2026-05-24", events: [trip], tasks: [], times: [:], nowMinutes: nil)
  #expect(last.first?.eventPart == .lastDay)
  #expect(last.first?.endMinutes == 9 * 60)
  #expect(last.first?.timeLabel.contains(lorvexClockTimeLabel("09:00")) == true)
}
