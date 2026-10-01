import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

// The Today glance every widget reads: which task leads at a given clock, how
// the rest are ordered, what the ring shows, and when a timeline needs a new
// entry.

private func task(
  _ id: String, start: String? = nil, end: String? = nil, status: String = "open",
  estimate: Int? = nil
) -> WidgetSnapshot.TodayTask {
  .init(
    id: id, title: id.capitalized, status: status, dueDate: nil, priority: nil, listID: nil,
    estimatedMinutes: estimate, scheduledStart: start, scheduledEnd: end)
}

@Suite("Widget Today glance")
struct WidgetTodayGlanceTests {
  @Test("a task whose time contains the clock leads; the rest keep Today's order")
  func runningTimeLeads() {
    let glance = WidgetTodayGlance.build(
      tasks: [
        task("first"),
        task("passed", start: "09:45", end: "10:30"),
        task("running", start: "11:00", end: "12:30"),
        task("ahead", start: "14:00", end: "14:30"),
      ],
      nowMinutes: 11 * 60 + 20)
    #expect(glance.lead?.id == "running")
    #expect(glance.isLeadRunning)
    #expect(glance.minutesLeft == 70)
    #expect(glance.rest.map(\.id) == ["first", "passed", "ahead"])
    #expect(abs(glance.progress - 20.0 / 90.0) < 0.001)
  }

  @Test("with no time running the next time leads, and nothing is measured")
  func nextTimeLeadsWithoutARunningTime() {
    let glance = WidgetTodayGlance.build(
      tasks: [
        task("first", estimate: 40),
        task("passed", start: "09:45", end: "10:30"),
        task("ahead", start: "14:00", end: "14:30"),
      ],
      nowMinutes: 12 * 60)
    #expect(glance.lead?.id == "ahead")
    #expect(glance.leadKind == .next)
    #expect(!glance.isLeadRunning)
    #expect(glance.progress == 0)
    #expect(glance.minutesLeft == nil)
    #expect(glance.rest.map(\.id) == ["first", "passed"])
    #expect(glance.remainingCount == 3)
    #expect(glance.workMinutes == 70, "the estimate and the time ahead; the passed time is over")
  }

  @Test("with nothing running, started, or ahead, no task leads")
  func noTaskLeadsOnAnOpenDay() {
    let glance = WidgetTodayGlance.build(
      tasks: [task("first", estimate: 40), task("passed", start: "09:45", end: "10:30")],
      nowMinutes: 12 * 60)
    #expect(glance.lead == nil)
    #expect(glance.leadKind == nil)
    #expect(glance.rest.map(\.id) == ["first", "passed"])
    #expect(glance.remainingCount == 2)
    #expect(glance.workMinutes == 40)
  }

  @Test("finished tasks are left out of the glance")
  func finishedTasksAreLeftOut() {
    let glance = WidgetTodayGlance.build(
      tasks: [
        task("done", start: "11:00", end: "12:00", status: "completed"),
        task("open", start: "13:00", end: "14:00"),
      ],
      nowMinutes: 11 * 60 + 30)
    #expect(glance.lead?.id == "open")
    #expect(glance.remainingCount == 1)
    #expect(WidgetTodayGlance.build(tasks: [], nowMinutes: 0).lead == nil)
  }

  @Test("a time ending at midnight parses, a reversed or half one does not")
  func timeParsing() {
    #expect(WidgetTodayGlance.time(of: task("x", start: "23:00", end: "24:00")) == (23 * 60)..<(24 * 60))
    #expect(WidgetTodayGlance.time(of: task("x", start: "10:00", end: "09:00")) == nil)
    #expect(WidgetTodayGlance.time(of: task("x", start: "10:00")) == nil)
  }

  @Test("the clock is read in the day's timezone")
  func clockInDayZone() {
    let instant = Date(timeIntervalSince1970: 1_779_465_600)  // 2026-05-22T16:00:00Z
    #expect(WidgetTodayGlance.minutes(at: instant, timezoneName: "UTC") == 16 * 60)
    #expect(WidgetTodayGlance.minutes(at: instant, timezoneName: "America/New_York") == 12 * 60)
  }

  @Test("entries fall on time edges and ten-minute ticks still ahead")
  func changeDates() {
    let now = Date(timeIntervalSince1970: 1_779_465_600)  // 16:00 UTC
    let until = now.addingTimeInterval(2 * 60 * 60)
    let dates = WidgetTodayGlance.changeDates(
      tasks: [
        task("run", start: "15:45", end: "16:30"), task("next", start: "17:00", end: "17:20"),
        task("far", start: "20:00", end: "21:00"),
      ],
      from: now, until: until, timezoneName: "UTC")
    let minutes = dates.map { Int($0.timeIntervalSince(now)) / 60 }
    #expect(minutes == [5, 15, 25, 30, 60, 70, 80])
    #expect(
      WidgetTodayGlance.changeDates(tasks: [task("loose")], from: now, until: until, timezoneName: "UTC")
        .isEmpty)
  }
}
