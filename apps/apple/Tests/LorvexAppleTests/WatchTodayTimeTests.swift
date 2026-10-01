import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexMobile
@testable import LorvexWatch

private let taskID = "00000000-0000-4000-8000-0000000000a1"

private func task(
  _ id: String, status: LorvexTask.Status = .open, due: String? = nil, minutes: Int? = nil,
  plannedDate: String? = nil, time: Range<Int>? = nil
) -> LorvexTask {
  LorvexTask(
    id: id, title: id, notes: "", priority: .p2, status: status,
    dueDate: due.flatMap(LorvexDateFormatters.ymdUTC.date(from:)),
    plannedDate: plannedDate.flatMap(LorvexDateFormatters.ymdUTC.date(from:)),
    plannedTime: time, estimatedMinutes: minutes, tags: [])
}

@Test("the widget projection carries a task's time only on the day it is set for")
func widgetProjectionCarriesTodaysTime() {
  let timedToday = task(taskID, plannedDate: "2026-09-22", time: 600..<645)
  let timedTomorrow = task("b", plannedDate: "2026-09-23", time: 600..<645)
  let endsAtMidnight = task("c", plannedDate: "2026-09-22", time: 1_380..<1_440)
  let snapshot = WidgetSnapshotProjector().snapshot(
    logicalDay: "2026-09-22",
    today: TodaySnapshot(
      summary: "", tasks: [timedToday, timedTomorrow, endsAtMidnight], localChangeSequence: 0),
    timezone: "UTC")

  #expect(snapshot.tasks.first?.scheduledStart == "10:00")
  #expect(snapshot.tasks.first?.scheduledEnd == "10:45")
  #expect(snapshot.tasks[1].scheduledStart == nil, "a time on another day is not today's")
  #expect(snapshot.tasks[2].scheduledEnd == "24:00")
  #expect(snapshot.tasks.map(WidgetTodayGlance.time(of:)) == [600..<645, nil, 1_380..<1_440])
}

@Test("the watch replica keeps a well-formed time and drops a malformed one")
func watchReplicaValidatesTimes() {
  #expect(WatchReplicaSnapshotProjector.clockPair("10:00", "10:45")?.start == "10:00")
  #expect(WatchReplicaSnapshotProjector.clockPair("23:00", "24:00")?.end == "24:00")
  #expect(WatchReplicaSnapshotProjector.clockPair("10:45", "10:00") == nil)
  #expect(WatchReplicaSnapshotProjector.clockPair("10:00", nil) == nil)
  #expect(WatchReplicaSnapshotProjector.clockPair("1:00", "10:45") == nil)
  #expect(WatchReplicaSnapshotProjector.clockPair("10:00", "25:00") == nil)
}

@Test("a snapshot task without time fields still decodes")
func todayTaskDecodesWithoutTimes() throws {
  let json = #"{"id":"a","title":"t","status":"open","due_date":null,"priority":1,"list_id":null,"estimated_minutes":30}"#
  let task = try JSONDecoder().decode(WidgetSnapshot.TodayTask.self, from: Data(json.utf8))
  #expect(task.scheduledStart == nil)
  #expect(task.scheduledEnd == nil)
  #expect(WidgetTodayGlance.time(of: task) == nil)
}

@Test("the lead is a running time, else a started task, else the next time; else none leads")
func todayLeadFollowsTheClock() {
  let ids = ["a", "b", "c", "d"]
  let times: [String: Range<Int>] = ["b": 600..<660, "c": 570..<700, "d": 900..<960]
  func lead(_ now: Int?, started: Set<String> = []) -> (String, TodayLead.Kind)? {
    TodayLead.lead(in: ids, nowMinutes: now, time: { times[$0] }, isStarted: started.contains)
      .map { (ids[$0.index], $0.kind) }
  }

  #expect(lead(620)! == ("c", .running), "when two times hold the clock, the earlier start leads")
  #expect(lead(690)! == ("c", .running))
  #expect(lead(500)! == ("c", .next), "no time runs: the next time to start leads")
  #expect(lead(700)! == ("d", .next), "a time ends at its end")
  #expect(lead(970) == nil, "nothing runs, nothing is started, nothing is ahead")
  #expect(lead(500, started: ["b"])! == ("b", .started), "a started task beats the next time")
  #expect(lead(620, started: ["a"])! == ("c", .running), "a running time beats a started task")
  #expect(lead(nil) == nil, "a day that is not today has no clock")
  #expect(lead(nil, started: ["d"])! == ("d", .started))
  #expect(TodayLead.lead(in: [String](), nowMinutes: 620, time: { times[$0] }, isStarted: { _ in false }) == nil)

  let ordered = TodayLead.ordered(ids, nowMinutes: 700, time: { times[$0] }, isStarted: { _ in false })
  #expect(ordered == ["d", "a", "b", "c"], "the lead moves to the top; the rest keep Today's order")
  #expect(
    TodayLead.ordered(ids, nowMinutes: 970, time: { times[$0] }, isStarted: { _ in false }) == ids,
    "with no lead the list keeps Today's order")
}

@MainActor
@Test("the watch leads with the running time, else the next time, else keeps Today's order")
func watchStoreLeadsWithTheRunningTask() throws {
  let store = LorvexWatchStore(core: try SwiftLorvexCoreService.inMemory(), logicalDayOverride: "2026-09-22")
  store.tasks = [task("first"), task("timed", minutes: 30), task("later")]
  store.savedTimes = ["timed": 600..<630, "later": 700..<730]

  #expect(store.orderedTasks(at: 590).map(\.id) == ["timed", "first", "later"], "the next time leads")
  #expect(store.orderedTasks(at: 615).map(\.id) == ["timed", "first", "later"])
  #expect(store.runningTime(of: store.tasks[1], at: 615) == 600..<630)
  #expect(store.runningTime(of: store.tasks[1], at: 630) == nil)
  #expect(
    store.orderedTasks(at: 645).map(\.id) == ["later", "first", "timed"],
    "a time that passed returns the task to its place; the next time leads")
  #expect(store.orderedTasks(at: 740).map(\.id) == ["first", "timed", "later"], "nothing ahead")
}

@Test("the line under a watch row: running time, then its start, overdue, started, estimate")
func watchTaskLineFollowsTodaysRowRules() {
  let day = "2026-09-22"
  let timed = task("t", minutes: 60)
  #expect(
    LorvexWatchTaskLine.make(task: timed, time: 600..<660, nowMinutes: 610, logicalDay: day)
      == LorvexWatchTaskLine(text: LorvexWatchCalmCopy.until(660), tone: .running))
  #expect(
    LorvexWatchTaskLine.make(task: timed, time: 600..<660, nowMinutes: 590, logicalDay: day)
      == LorvexWatchTaskLine(text: lorvexClockTimeLabel(minutes: 600), tone: .plain))
  #expect(
    LorvexWatchTaskLine.make(task: timed, time: 600..<660, nowMinutes: 700, logicalDay: day)
      == LorvexWatchTaskLine(text: lorvexClockTimeLabel(minutes: 600), tone: .plain),
    "a passed time keeps reading as its start")
  #expect(
    LorvexWatchTaskLine.make(
      task: task("o", status: .inProgress, due: "2026-09-21"), time: nil, nowMinutes: 610,
      logicalDay: day)?.tone == .overdue)
  #expect(
    LorvexWatchTaskLine.make(task: task("s", status: .inProgress), time: nil, nowMinutes: 610, logicalDay: day)
      == LorvexWatchTaskLine(text: LorvexWatchCalmCopy.started, tone: .started))
  #expect(
    LorvexWatchTaskLine.make(task: timed, time: nil, nowMinutes: 610, logicalDay: day)
      == LorvexWatchTaskLine(text: LorvexWatchCalmCopy.minutes(60), tone: .plain))
  #expect(LorvexWatchTaskLine.make(task: task("n"), time: nil, nowMinutes: 610, logicalDay: day) == nil)
}

@Test("the lead's ring fills with the elapsed part of its time")
func watchLeadRingProgress() {
  let time = 600..<660
  #expect(LorvexWatchTodayPage.progress(of: time, at: 590) == 0)
  #expect(LorvexWatchTodayPage.progress(of: time, at: 615) == 0.25)
  #expect(LorvexWatchTodayPage.progress(of: time, at: 700) == 1)
}
