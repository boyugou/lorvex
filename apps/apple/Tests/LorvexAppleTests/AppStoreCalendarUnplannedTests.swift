import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// The Calendar's "Unplanned Tasks" rail lists the open tasks that have no
// planned day and follows every task change while it is shown.

@MainActor
private func makeStore() async throws -> (store: AppStore, core: any LorvexCoreServicing) {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  return (store, core)
}

private func tomorrow() throws -> Date {
  try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
}

@MainActor
@Test
func theRailListsOpenTasksWithNoPlannedDay() async throws {
  let (store, core) = try await makeStore()
  let loose = try await core.createTask(title: "Loose end", notes: "")
  let planned = try await core.createTask(title: "Has a day", notes: "")
  _ = try await core.updateTask(
    TaskUpdateDraft(
      id: planned.id,
      plannedDate: .set(PlannedDayBridge.storageDate(forLocalInstant: try tomorrow()))))
  let finished = try await core.createTask(title: "Already done", notes: "")
  _ = try await core.completeTask(id: finished.id)

  await store.showCalendarUnplannedTasks()

  let ids = Set((store.calendarUnplannedTasks ?? []).map(\.id))
  #expect(ids.contains(loose.id))
  #expect(!ids.contains(planned.id))
  #expect(!ids.contains(finished.id))
  #expect(store.calendarUnplannedTotal == store.calendarUnplannedTasks?.count)
}

@MainActor
@Test
func aTaskDeferredToALaterDayIsNotYetSomethingToPlan() async throws {
  let (store, core) = try await makeStore()
  let waiting = try await core.createTask(title: "Wait a week", notes: "")
  let nextWeek = try #require(Calendar.current.date(byAdding: .day, value: 7, to: Date()))
  _ = try await core.batchDeferTasks(ids: [waiting.id], until: nextWeek)

  await store.showCalendarUnplannedTasks()

  #expect(!(store.calendarUnplannedTasks ?? []).map(\.id).contains(waiting.id))
}

@MainActor
@Test
func planningATaskTakesItOffTheRail() async throws {
  let (store, core) = try await makeStore()
  let task = try await core.createTask(title: "Plan me", notes: "")
  await store.showCalendarUnplannedTasks()
  #expect((store.calendarUnplannedTasks ?? []).map(\.id).contains(task.id))
  let before = store.calendarUnplannedTotal

  await store.planTasks(ids: [task.id], on: try tomorrow(), time: .start(9 * 60))

  #expect(!(store.calendarUnplannedTasks ?? []).map(\.id).contains(task.id))
  #expect(store.calendarUnplannedTotal == before - 1)
}

@MainActor
@Test
func completingATaskTakesItOffTheRail() async throws {
  let (store, core) = try await makeStore()
  let task = try await core.createTask(title: "Finish me", notes: "")
  await store.showCalendarUnplannedTasks()
  let listed = try #require((store.calendarUnplannedTasks ?? []).first { $0.id == task.id })

  await store.toggleTaskCompletion(listed, undoManager: nil)

  #expect(!(store.calendarUnplannedTasks ?? []).map(\.id).contains(task.id))
}

@MainActor
@Test
func aTaskCreatedWhileTheRailIsShownJoinsIt() async throws {
  let (store, core) = try await makeStore()
  await store.showCalendarUnplannedTasks()
  let task = try await core.createTask(title: "Fresh idea", notes: "")

  await store.reloadTaskWorkspaceIfLoaded()

  #expect((store.calendarUnplannedTasks ?? []).map(\.id).contains(task.id))
}

@MainActor
@Test
func theRailStopsFollowingTaskChangesOnceHidden() async throws {
  let (store, core) = try await makeStore()
  await store.showCalendarUnplannedTasks()
  #expect(store.calendarUnplannedTasks != nil)

  store.hideCalendarUnplannedTasks()
  _ = try await core.createTask(title: "Unseen", notes: "")
  await store.reloadTaskWorkspaceIfLoaded()

  #expect(store.calendarUnplannedTasks == nil)
  #expect(store.calendarUnplannedTotal == 0)
}

@MainActor
@Test
func theRailListsTheFirstTasksAndCountsTheRest() async throws {
  let (store, core) = try await makeStore()
  for index in 0..<(AppStore.calendarUnplannedLimit + 5) {
    _ = try await core.createTask(title: "Backlog \(index)", notes: "")
  }

  await store.showCalendarUnplannedTasks()

  #expect(store.calendarUnplannedTasks?.count == AppStore.calendarUnplannedLimit)
  #expect(store.calendarUnplannedTotal >= AppStore.calendarUnplannedLimit + 5)
}
