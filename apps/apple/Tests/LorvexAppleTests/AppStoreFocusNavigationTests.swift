import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

@MainActor
@Test
func appStoreRestoresSelectionFromCaseVariantDefaults() async throws {
  let suiteName = "AppStore.restoreSelection.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defaults.set("MEMORY", forKey: AppStore.Key.selection)

  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher(),
    defaults: defaults
  )

  #expect(store.selection == .memory)
}

@MainActor
@Test
func appStoreDraftCaptureClearsOnlyAfterSuccessfulCreate() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  store.draftTitle = "  "
  store.draftNotes = "Still editing"
  await store.createDraftTask()

  // A whitespace-only capture has nothing to create: the draft is preserved and
  // it's a silent no-op — no error is pushed at the user (an empty field isn't a
  // failure they asked to surface).
  #expect(store.draftTitle == "  ")
  #expect(store.draftNotes == "Still editing")
  #expect(store.errorMessage == nil)

  store.draftTitle = "Captured draft"
  await store.createDraftTask()

  #expect(store.draftTitle.isEmpty)
  #expect(store.draftNotes.isEmpty)
  #expect(store.selectedTask?.title == "Captured draft")
}

@MainActor
@Test
func appStoreFocusesSelectedPreviewTask() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let selectedID = store.today.tasks.first?.id
  store.selectedTaskID = selectedID
  await store.focusSelectedTask()
  await store.focusSelectedTask()

  #expect(selectedID != nil)
  #expect(store.currentFocus?.taskIDs == selectedID.map { [$0] })
  #expect(store.currentFocusTaskCount == 1)
  #expect(store.focusedTasks.map(\.id) == selectedID.map { [$0] })
  #expect(!store.remainingTodayTasks.contains { $0.id == selectedID })
}

@MainActor
@Test
func appStoreBatchAddsMultipleTasksToFocusInOneCall() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let ids = Array(store.today.tasks.prefix(3).map(\.id))

  // A multi-item drop routes through one batched core write, not one Task per
  // ref, so all three land in currentFocus without racing each other.
  await store.addTasksToCurrentFocus(ids: ids)

  #expect(ids.count == 3)
  #expect(Set(store.currentFocus?.taskIDs ?? []) == Set(ids))
  #expect(store.currentFocusTaskCount == 3)
}

@MainActor
@Test
func appStoreTogglesSelectedPreviewTaskFocus() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let selectedID = store.today.tasks.first?.id
  store.selectedTaskID = selectedID

  await store.toggleSelectedTaskFocus()
  #expect(store.currentFocus?.taskIDs == selectedID.map { [$0] })
  #expect(store.selectedTaskIsFocused)

  await store.toggleSelectedTaskFocus()
  #expect(store.currentFocus == nil)
  #expect(!store.selectedTaskIsFocused)
}

@MainActor
@Test
func appStoreGroupsTasksForWorkspaceViews() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)

  await store.refresh()
  let initialOpenCount = store.openTasks.count
  store.selectedTaskID = store.openTasks.first?.id

  await store.deferSelectedTask()

  #expect(initialOpenCount > 0)
  #expect(store.deferredTasks.count == 1)
  #expect(store.openTasks.count == initialOpenCount - 1)
  // Non-open statuses never ride the Today snapshot; the someday bucket is
  // read from the store.
  let someday = try await core.listTasks(
    status: "someday", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  #expect(someday.tasks.map(\.id) == [LorvexPreviewSeedID.standingDeskTask])
  #expect(store.weeklyReview?.someday == 1)
}

@MainActor
@Test
func appStoreRefreshesLoadedTaskWorkspaceAfterStatusMutations() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  await store.loadTaskWorkspace()

  let task = try #require(store.taskWorkspaceOpenTasks.first)
  store.selectTaskFromList(task.id)
  await store.completeSelectedTask()

  // A mutation that errored skips its workspace reload (perform's catch path),
  // so a bucket mismatch below would be a symptom — surface the cause first.
  #expect(store.errorMessage == nil, "completeSelectedTask errored: \(store.errorMessage ?? "")")
  // The mutation is committed and its reload awaited. loadTaskWorkspace now
  // single-flights (a reload requested mid-load coalesces into a trailing re-run),
  // so the mutation's awaited reload observes its own write and no older-started
  // background reload can revert the buckets to a pre-mutation snapshot. The
  // bounded, non-mutating re-read below is retained as belt-and-suspenders for the
  // separately-scheduled republish reload's timing under maximum parallel load.
  await awaitWorkspaceReflects(store) { !store.taskWorkspaceOpenTasks.contains { $0.id == task.id } }
  #expect(!store.taskWorkspaceOpenTasks.contains { $0.id == task.id })
  #expect(store.taskWorkspaceCompletedTasks.contains { $0.id == task.id })

  await store.reopenSelectedTask()

  #expect(store.errorMessage == nil, "reopenSelectedTask errored: \(store.errorMessage ?? "")")
  await awaitWorkspaceReflects(store) { store.taskWorkspaceOpenTasks.contains { $0.id == task.id } }
  #expect(store.taskWorkspaceOpenTasks.contains { $0.id == task.id })
  #expect(!store.taskWorkspaceCompletedTasks.contains { $0.id == task.id })
}

/// Re-reads the task workspace until `condition` holds, so the mutation→reload
/// wiring can be asserted without flaking on the full suite's maximum
/// parallel-load scheduling. The mutation is already committed, so this only
/// re-reads; it never mutates. `loadTaskWorkspace` single-flights, so a re-read
/// observes the committed state; this loop just gives a maximally-contended
/// scheduler enough yields to make that read run. Returns the instant the
/// condition holds — because the caller's `#expect` runs synchronously right
/// after, with no await in between, the observed state cannot change between the
/// two on `@MainActor`. Escalates to a full `refresh()` if plain reloads stall,
/// and re-checks after every attempt (the earlier version returned after its
/// fallback WITHOUT re-checking, which is what let a still-stale state reach the
/// assertion). If the condition genuinely never holds the loop exhausts and the
/// caller's `#expect` surfaces the real regression.
@MainActor
private func awaitWorkspaceReflects(_ store: AppStore, _ condition: () -> Bool) async {
  // Real suspensions with exponential backoff, not bare yields: under maximum
  // parallel suite load a yield-only spin can exhaust every attempt before a
  // competing executor finishes one coalesced trailing reload. The backoff
  // gives the trailing run wall time (~2s total budget) while a converged
  // state still returns on the first check.
  var backoffNs: UInt64 = 1_000_000
  for _ in 0..<40 {
    if condition() { return }
    try? await Task.sleep(nanoseconds: backoffNs)
    backoffNs = min(backoffNs * 2, 50_000_000)
    await store.loadTaskWorkspace()
  }
  for _ in 0..<5 {
    if condition() { return }
    await store.refresh()
    await store.loadTaskWorkspace()
    try? await Task.sleep(nanoseconds: backoffNs)
  }
}

@MainActor
@Test
func appStoreExposesDeferredTasksAsScheduledTasks() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let selectedID = store.today.tasks.first?.id
  store.selectedTaskID = selectedID

  await store.deferSelectedTask()
  // The calendar's scheduled-task pills come from the 14-day window, not the
  // Today snapshot, so they refresh when the calendar (re)loads after a
  // mutation — the week grid does this via `onChange(of: today)`. Simulate that
  // refetch here rather than relying on a today-snapshot shortcut that
  // truncated the window in the real on-disk core.
  try? await store.refreshCurrentCalendarTimeline()

  #expect(selectedID != nil)
  // The deferred task joins the scheduled lane. The seeded weekly-recurring
  // task also carries an occurrence date in the window, so membership — not
  // exact equality — is the contract.
  #expect(store.scheduledTasks.contains { $0.id == selectedID })
  #expect(store.filteredScheduledTasks.contains { $0.id == selectedID })
}

@MainActor
@Test
func appStoreRemovesSelectedPreviewTaskFromFocus() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let selectedID = store.today.tasks.first?.id
  store.selectedTaskID = selectedID
  await store.focusSelectedTask()
  #expect(store.selectedTaskIsFocused)

  await store.removeSelectedTaskFromFocus()

  #expect(selectedID != nil)
  #expect(store.currentFocus == nil)
  #expect(!store.selectedTaskIsFocused)
  #expect(store.focusedTasks.isEmpty)
  #expect(store.remainingTodayTasks.contains { $0.id == selectedID })
}

@MainActor
@Test
func appStoreFocusWorkspaceSelectionAddsAndRemovesFocusTasks() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let selectedIDs = Set(store.remainingTodayTasks.prefix(2).map(\.id))
  #expect(selectedIDs.count == 2)

  store.setFocusWorkspaceSelection(selectedIDs)
  await store.addFocusWorkspaceSelectionToFocus()

  #expect(Set(store.currentFocus?.taskIDs ?? []) == selectedIDs)
  #expect(store.focusWorkspaceSelectionCount == selectedIDs.count)
  #expect(store.errorMessage == nil)

  await store.removeFocusWorkspaceSelectionFromFocus()

  #expect(store.currentFocus == nil)
  #expect(store.focusWorkspaceSelectionCount == selectedIDs.count)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreFocusWorkspaceSelectionCompletesAndReopensTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)

  await store.refresh()
  let selectedIDs = Set(store.remainingTodayTasks.prefix(2).map(\.id))
  #expect(selectedIDs.count == 2)
  store.setFocusWorkspaceSelection(selectedIDs)

  await store.completeFocusWorkspaceSelection()

  // Completed tasks leave the open-only Today pool, and the surface prunes
  // its selection to the tasks still visible there.
  #expect(!store.today.tasks.contains { selectedIDs.contains($0.id) })
  for id in selectedIDs {
    #expect(try await core.loadTask(id: id).status == .completed)
  }
  #expect(store.focusWorkspaceSelectionCount == 0)
  #expect(store.errorMessage == nil)

  // Reopening happens where completed tasks are listed: the task workspace.
  await store.loadTaskWorkspace()
  for id in selectedIDs {
    store.selectTaskFromList(id)
    await store.reopenSelectedTask()
  }
  #expect(selectedIDs.isSubset(of: Set(store.today.tasks.filter { $0.status == .open }.map(\.id))))
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func focusWorkspaceTaskRowSelectionSeparatesOpenFromBatchSelection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let tasks = store.filteredRemainingTodayTasks
  let first = try #require(tasks.first)
  let second = try #require(tasks.dropFirst().first)

  store.selectOnlyFocusWorkspaceTask(first.id)

  #expect(store.selectedTaskID == first.id)
  #expect(store.focusWorkspaceSelectedTaskIDs == [first.id])

  store.toggleFocusWorkspaceTaskBatchSelection(second.id)

  #expect(store.selectedTaskID == second.id)
  #expect(store.focusWorkspaceSelectedTaskIDs == [first.id, second.id])

  store.toggleFocusWorkspaceTaskBatchSelection(second.id)

  #expect(store.selectedTaskID == first.id)
  #expect(store.focusWorkspaceSelectedTaskIDs == [first.id])
}

@MainActor
@Test
func appStorePersistsNavigationStateAcrossLaunches() async throws {
  let suiteName = "LorvexAppleTests-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()
  let taskID = store.today.tasks[1].id
  store.selection = .today
  store.selectedTaskID = taskID

  let restored = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  #expect(restored.selection == .today)
  #expect(restored.selectedTaskID == taskID)
}

@MainActor
@Test
func appStoreDoesNotRestoreTaskSelectionForNonTaskLaunchDestination() async throws {
  let suiteName = "LorvexAppleTests-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  defaults.set(SidebarSelection.calendar.rawValue, forKey: "navigation.selection")
  defaults.set("stale-task-id", forKey: "navigation.selectedTaskID")

  let restored = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  #expect(restored.selection == .calendar)
  #expect(restored.selectedTaskID == nil)
  #expect(defaults.string(forKey: "navigation.selectedTaskID") == nil)
}

@MainActor
@Test
func appStoreDeepLinkOverridesRestoredNavigationState() async throws {
  let suiteName = "LorvexAppleTests-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  defaults.set(SidebarSelection.memory.rawValue, forKey: "navigation.selection")
  defaults.set("stale-task-id", forKey: "navigation.selectedTaskID")
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  let taskID = try #require(store.today.tasks.first?.id)
  await store.openDeepLinkRoute(.task(taskID))

  let restored = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  #expect(store.selection == .tasks)
  #expect(store.selectedTaskID == taskID)
  #expect(restored.selection == .tasks)
  #expect(restored.selectedTaskID == taskID)
}

@MainActor
@Test
func appStoreCanReplaceCoreAndReload() async throws {
  let suiteName = "AppStoreCanReplaceCoreAndReload.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  store.selectedTaskID = LorvexPreviewSeedID.statusUpdateTask

  await store.replaceCore(try await makeSeededInMemoryCore())

  #expect(store.selectedTaskID == nil)
  #expect(store.currentFocus == nil)
  #expect(!store.today.tasks.isEmpty)
}

@MainActor
@Test
func toggleTaskFocusFromRowLeavesSelectionUntouched() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = nil

  await store.toggleTaskFocus(task)
  #expect(store.focusedTaskIDSet.contains(task.id))
  #expect(store.selectedTaskID == nil)

  await store.toggleTaskFocus(task)
  #expect(!store.focusedTaskIDSet.contains(task.id))
  #expect(store.selectedTaskID == nil)
}

@MainActor
@Test
func deferTaskFromRowLeavesSelectionUntouched() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let task = try #require(store.today.tasks.first { $0.status == .open })
  store.selectedTaskID = nil
  let tomorrow = try #require(store.deferStorageDate(daysFromNow: 1))

  await store.deferTaskFromRow(task, until: tomorrow)
  #expect(store.selectedTaskID == nil)
  #expect(store.errorMessage == nil)
}
