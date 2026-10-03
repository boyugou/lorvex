import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// What the menu bar panel's Today lists (``MenuBarTodaySections``) and where
/// its event rows open.
private enum Fixture {
  static let day = "2026-05-23"

  static func task(_ id: String, status: LorvexTask.Status = .open) -> LorvexTask {
    LorvexTask(
      id: id, title: id, notes: "", priority: .p2, status: status,
      dueDate: nil, estimatedMinutes: nil, tags: [])
  }

  static func event(_ id: String, start: String?, end: String? = nil) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id, eventID: id, supportsScopedMutation: false, title: id, source: "canonical",
      editable: true, startDate: day, startTime: start, endDate: day,
      endTime: end, allDay: start == nil, location: nil, color: nil, eventType: "event",
      timezone: nil, isRecurring: false)
  }

  static func page(_ items: [LorvexCalmToday.Item], leadID: String?) -> LorvexCalmToday {
    LorvexCalmToday(
      items: items, leadID: leadID, doneToday: 0, remainingMeetings: 0, workMinutes: nil,
      overbooked: nil)
  }
}

@Test("the schedule holds what is still ahead on the clock; tasks without a time list under it, each task once")
func menuBarTodaySectionsSplitTheDay() {
  let page = Fixture.page(
    [
      .init(task: Fixture.task("running"), time: 600..<660, isRunning: true),
      .init(task: Fixture.task("missed"), time: 480..<540),
      .init(task: Fixture.task("later"), time: 840..<900),
      .init(task: Fixture.task("overdue")),
      .init(task: Fixture.task("plain")),
    ],
    leadID: "running")
  let sections = MenuBarTodaySections(
    page: page,
    events: [
      Fixture.event("standup", start: "09:00", end: "09:15"),
      Fixture.event("review", start: "13:00", end: "14:00"),
      Fixture.event("sync", start: "10:15", end: "10:45"),
      Fixture.event("holiday", start: nil),
    ],
    logicalDay: Fixture.day, nowMinutes: 630, isOverdue: { $0.id == "overdue" })

  #expect(sections.lead?.id == "running")
  #expect(
    sections.schedule.map(\.id)
      == ["event:holiday", "task:missed", "event:sync", "event:review", "task:later"],
    "all-day first, then by start; the ended standup and the lead are left out, a missed time stays")
  #expect(sections.overdue.map(\.id) == ["overdue"])
  #expect(sections.tasks.map(\.id) == ["plain"])
  #expect(!sections.isEmpty)
}

@Test("a started lead without a time is not repeated under Tasks, and a day with only ended events is empty")
func menuBarTodaySectionsLeaveTheLeadOutAndReadAnEmptyDay() {
  let started = MenuBarTodaySections(
    page: Fixture.page(
      [.init(task: Fixture.task("started", status: .inProgress)), .init(task: Fixture.task("plain"))],
      leadID: "started"),
    events: [], logicalDay: Fixture.day, nowMinutes: 630, isOverdue: { _ in false })
  #expect(started.lead?.id == "started")
  #expect(started.tasks.map(\.id) == ["plain"])
  #expect(started.schedule.isEmpty)

  let cleared = MenuBarTodaySections(
    page: Fixture.page([], leadID: nil),
    events: [Fixture.event("standup", start: "09:00", end: "09:15")],
    logicalDay: Fixture.day, nowMinutes: 630, isOverdue: { _ in false })
  #expect(cleared.isEmpty, "the sun arc shows once the day's last meeting has ended")
}

@MainActor
@Test("an event clicked in the menu bar opens in Today's inspector, or on its day in the Calendar")
func menuBarEventClicksOpenTheEventWhereItLives() async throws {
  let suiteName = "MenuBarTodaySectionsTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  let event = Fixture.event("review", start: "13:00", end: "14:00")

  store.selection = .tasks
  store.selectedTaskID = task.id
  store.showEventInToday(event)
  #expect(store.selection == .today)
  #expect(store.selectedTaskID == nil, "Today's inspector shows one subject")
  #expect(store.selectedCalendarEventID == "review")
  #expect(store.calendarPendingDayKey == nil)

  store.showEventInCalendar(event, onDayKey: "2026-05-25")
  #expect(store.selection == .calendar)
  #expect(store.calendarPendingDayKey == "2026-05-25")
  #expect(store.selectedCalendarEventID == "review", "the switch to Calendar keeps the event it opens")
}
