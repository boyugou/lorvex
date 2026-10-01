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
  let timed = try await core.createTask(
    TaskCreateDraft(
      title: "Planned at 2 PM", priority: .p3, plannedDate: dueToday,
      plannedTime: 14 * 60..<14 * 60 + 30))
  let overdue = try await core.createTask(TaskCreateDraft(title: "Missed deadline", dueDate: dueYesterday))
  let alsoToday = try await core.createTask(TaskCreateDraft(title: "Due today", dueDate: dueToday))
  let started = try await core.createTask(TaskCreateDraft(title: "Started, undated", priority: .p3))
  let finished = try await core.createTask(TaskCreateDraft(title: "Finished today", dueDate: dueToday))
  _ = try await core.startTask(id: started.id)
  _ = try await core.completeTask(id: finished.id)
  await store.refresh()
  await store.loadDoneTodayCount()

  // The schedule at the top of the column draws the timed task first; then the
  // tasks without a time, started work leading and the rest in the canonical
  // order (priority, then due date with undated last).
  let open = [timed.id, started.id, untimed.id, overdue.id, alsoToday.id]
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
