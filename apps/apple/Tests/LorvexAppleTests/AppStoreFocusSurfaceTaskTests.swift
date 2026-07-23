import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@MainActor
@Test
func focusedTasksResolveOutsideTodaySnapshotFromFocusSurfaceCache() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)

  await store.refresh()
  let offscreen = try await core.createTask(title: "Offscreen focus plan task", notes: "")
  store.currentFocus = CurrentFocusPlan(
    date: "2026-05-31",
    taskIDs: [offscreen.id],
    briefing: nil,
    timezone: nil,
    localChangeSequence: 1
  )

  #expect(store.today.tasks.contains { $0.id == offscreen.id } == false)
  #expect(store.focusedTasks.isEmpty)

  await store.loadFocusSurfaceTasks()

  #expect(store.focusedTasks.map(\.id) == [offscreen.id])
  #expect(store.focusedTasks.first?.title == "Offscreen focus plan task")
}

@MainActor
@Test
func todayHasVisibleTasksWhenOnlyAFocusedTaskIsScheduledElsewhere() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)

  await store.refresh()
  // A focused task with no due date is not in today's snapshot, but it still
  // renders in the Today Focus section — so the Today empty state must not fire.
  let offscreen = try await core.createTask(title: "Focused but not due today", notes: "")
  store.currentFocus = CurrentFocusPlan(
    date: "2026-05-31",
    taskIDs: [offscreen.id],
    briefing: nil,
    timezone: nil,
    localChangeSequence: 1
  )
  await store.loadFocusSurfaceTasks()
  // Clear today's snapshot so the only renderable row is the focused task that
  // lives outside it — the exact case the empty-state fix guards against.
  store.today = .empty

  #expect(store.filteredRemainingTodayTasks.isEmpty)
  #expect(store.filteredFocusedTasks.map(\.id) == [offscreen.id])
  // The list still renders the focused task, so the "No Tasks Today" overlay is
  // suppressed even though `today.tasks` is empty.
  #expect(store.hasVisibleTodayTasks)
}
