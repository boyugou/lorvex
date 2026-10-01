import Foundation
import LorvexCore
import Testing

/// Ordering and marking rules for the day on the clock drawn beside Today
/// (``LorvexTodayTimeline/build(events:tasks:times:nowMinutes:)``).
private enum Fixture {
  static func event(
    _ id: String, start: String?, end: String? = nil, allDay: Bool = false
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id, eventID: id, supportsScopedMutation: false, title: id, source: "canonical",
      editable: true, startDate: "2026-05-23", startTime: start, endDate: "2026-05-23",
      endTime: end, allDay: allDay, location: nil, color: nil, eventType: "event",
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
    events: [],
    tasks: [done, early],
    times: ["finished": 9 * 60..<10 * 60, "finishedEarly": 13 * 60..<14 * 60],
    nowMinutes: 12 * 60)

  #expect(Set(items.filter(\.isPast).map(\.id)) == ["task:finished"])
}

@Test("the fold takes the finished rows that open the timed day, never all-day rows")
func earlierFoldTakesTheLeadingFinishedRun() {
  let items = LorvexTodayTimeline.build(
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
