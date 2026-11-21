import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// Today's selectable rows on macOS follow the page. Arrow keys, shift-click
/// ranges, Select All, batch actions, and the inspector's refresh check all read
/// `todayOrderedTasks`, so it must list the rows in the order the main
/// column draws them and leave out the rows the Done fold hides.
private struct TodayFixture {
  let store: AppStore
  let core: SwiftLorvexCoreService
  let defaults: UserDefaults
  let suiteName: String

  @MainActor
  static func make() async throws -> TodayFixture {
    let suiteName = "TodaySelectionOrderTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let core = try makeInMemoryCore()
    let store = AppStore(core: core, defaults: defaults)
    await store.refresh()
    return TodayFixture(store: store, core: core, defaults: defaults, suiteName: suiteName)
  }

  func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
  }
}

@MainActor
@Test
func todaySelectableRowsFollowTheColumnOrder() async throws {
  let fixture = try await TodayFixture.make()
  defer { fixture.tearDown() }
  let (store, core) = (fixture.store, fixture.core)
  let today = store.logicalTodayDateString
  let dueToday = try #require(LorvexDateFormatters.ymdUTC.date(from: today))
  let dueYesterday = dueToday.addingTimeInterval(-86_400)

  // Priorities differ so the expected order is deterministic: ids minted in
  // the same millisecond tie-break arbitrarily.
  let untimed = try await core.createTask(
    TaskCreateDraft(title: "Planned, no time", priority: .p1, plannedDate: dueToday))
  // Keep the saved time away from now so the explicitly started task leads
  // regardless of the host's current hour.
  let slot = (store.nowMinutesInProductDay ?? 0) < 720 ? 18 * 60 : 6 * 60
  let timed = try await core.createTask(
    TaskCreateDraft(
      title: "Another scheduled task", priority: .p3, plannedDate: dueToday,
      plannedTime: slot..<slot + 30))
  let overdue = try await core.createTask(TaskCreateDraft(title: "Missed deadline", dueDate: dueYesterday))
  let alsoToday = try await core.createTask(TaskCreateDraft(title: "Due today", dueDate: dueToday))
  let started = try await core.createTask(TaskCreateDraft(title: "Started, undated", priority: .p3))
  let finished = try await core.createTask(TaskCreateDraft(title: "Finished today", dueDate: dueToday))
  _ = try await core.startTask(id: started.id)
  _ = try await core.completeTask(id: finished.id)
  await store.refresh()
  await store.loadDoneTodayCount()

  // The started task leads once, followed by the remaining schedule, untimed
  // work in canonical order, and the visible Done section.
  let open = [started.id, timed.id, untimed.id, overdue.id, alsoToday.id]
  #expect(store.orderedTaskIDs(on: .today) == open + [finished.id])

  store.isTodayDoneCollapsed = true
  #expect(store.orderedTaskIDs(on: .today) == open, "the fold hides the done rows from the keyboard")
  #expect(fixture.defaults.bool(forKey: "today.done.collapsed"))
  let relaunched = AppStore(core: core, defaults: fixture.defaults)
  #expect(relaunched.isTodayDoneCollapsed, "the fold survives a relaunch")
}

@MainActor
@Test
func todayKeepsTheInspectorOnADoneRowWhileTheFoldIsOpen() async throws {
  let fixture = try await TodayFixture.make()
  defer { fixture.tearDown() }
  let (store, core) = (fixture.store, fixture.core)
  let finished = try await core.createTask(title: "Finished today", notes: "")
  _ = try await core.completeTask(id: finished.id)
  await store.refresh()
  await store.loadDoneTodayCount()

  store.selectOnlyTodayTask(finished.id)
  store.reconcileSelectedTaskAfterRefresh()
  #expect(store.selectedTaskID == finished.id, "a done row is still on the page")

  store.isTodayDoneCollapsed = true
  store.reconcileSelectedTaskAfterRefresh()
  #expect(store.selectedTaskID == nil, "a row the fold hides has left the page")
}

@MainActor
@Test func todayContinueOpensTheOneFeaturedRowAndKeepsItsWorkStarted() async throws {
  let fixture = try await TodayFixture.make()
  defer { fixture.tearDown() }
  let (store, core) = (fixture.store, fixture.core)
  let writing = try await core.createTask(title: "Write the abstract", notes: "Continue at paragraph two.")
  _ = try await core.startTask(id: writing.id)
  await store.refresh()
  await store.loadTodaySchedule()

  let content = store.todayColumnContent
  let cue = try #require(content.workCue)
  #expect(cue.action == .resume)
  #expect(content.featured?.id == writing.id)
  #expect(!content.untimedItems.contains { $0.id == writing.id })
  #expect(store.todayArrowKeyStops().ids == [writing.id])
  #expect(store.orderedTaskIDs(on: .today) == [writing.id])
  await store.performTodayWorkAction(cue)
  #expect(store.selectedTaskID == writing.id)
  #expect(store.selectedTask?.notes == "Continue at paragraph two.")
  #expect(try await core.loadTask(id: writing.id).status == .inProgress)

  _ = try await core.completeTask(id: writing.id)
  await store.refresh()
  store.selectedTaskID = nil
  await store.performTodayWorkAction(cue)
  #expect(store.selectedTaskID == nil)
  #expect(try await core.loadTask(id: writing.id).status == .completed)
}

@MainActor
@Test func todayStartUsesTheSavedSlotAndRejectsAStaleOfferDuringAMeeting() async throws {
  let fixture = try await TodayFixture.make()
  defer { fixture.tearDown() }
  let (store, core) = (fixture.store, fixture.core)
  let day = store.logicalTodayDateString
  let planned = try #require(LorvexDateFormatters.ymdUTC.date(from: day))
  let task = try await core.createTask(TaskCreateDraft(title: "Edit outline",
    plannedDate: planned, plannedTime: 600..<660))
  await store.refresh()
  let event = CalendarTimelineEvent(id: "call", title: "Call", source: "canonical", editable: true,
    startDate: day, startTime: "10:30", endDate: day, endTime: "11:00", allDay: false,
    location: nil, color: nil, eventType: "event", timezone: nil, isRecurring: false)
  store.calendarTimeline = CalendarTimelineSnapshot(from: day, to: day, events: [event], truncated: false, nextOffset: nil)
  let calendar = LorvexDateFormatters.gregorianCalendar(timeZone: store.logicalTimeZone)
  let morning = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date()))
  let meetingStart = morning.addingTimeInterval(1800)
  let offer = try #require(store.todayColumnContent(at: morning).workCue)
  #expect(offer.action == .start)
  #expect(offer.upcoming?.minutesAway == 30)
  #expect(store.todayColumnContent(at: meetingStart).workCue?.action == .reviewConflict(event: "Call"))
  await store.performTodayWorkAction(offer, at: meetingStart)
  #expect(try await core.loadTask(id: task.id).status == .open)
  await store.performTodayWorkAction(offer, at: morning)
  let saved = try await core.loadTask(id: task.id)
  #expect(saved.status == .inProgress)
  #expect(saved.time(on: day) == 600..<660)
  #expect(store.selectedTaskID == task.id)
}
