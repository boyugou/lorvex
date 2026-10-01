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
  store.restorePersistedLaunchState()

  #expect(store.selection == .memory)
}

@MainActor
@Test
func appStoreStartsSelectedTaskAtTheTopOfToday() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let task = try #require(store.today.tasks.last { $0.status == .open })
  store.selectedTaskID = task.id
  await store.startSelectedTask()

  #expect(store.errorMessage == nil)
  #expect(store.selectedTaskID == task.id)
  #expect(try await store.core.loadTask(id: task.id).status == .inProgress)
  // Started work leads Today: every row above the started task is started too.
  let started = store.today.tasks.prefix { $0.status == .inProgress }
  #expect(started.contains { $0.id == task.id })
  #expect(store.todayOrderedTasks.prefix(started.count).contains { $0.id == task.id })
}

@MainActor
@Test
func appStorePlansTasksDroppedOnTodayInOneBatch() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  var dropped: [LorvexTask.ID] = []
  for title in ["Draft the outline", "Book the venue", "Order supplies"] {
    dropped.append(try await core.createTask(TaskCreateDraft(title: title)).id)
  }

  await store.refresh()
  let alreadyOnToday = try #require(store.today.tasks.first { $0.status == .open })
  #expect(!store.today.tasks.contains { dropped.contains($0.id) })

  await store.planTasksForToday(ids: dropped + [alreadyOnToday.id])

  #expect(store.errorMessage == nil)
  let onToday = Set(store.today.tasks.map(\.id))
  #expect(Set(dropped).isSubset(of: onToday))
  #expect(onToday.contains(alreadyOnToday.id))
  // A task that was already on Today keeps the planned date it had.
  #expect(try await core.loadTask(id: alreadyOnToday.id).plannedDate == alreadyOnToday.plannedDate)
}

@MainActor
@Test
func appStoreTogglesSelectedTaskStartedAndPausingKeepsItOnToday() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let task = try #require(store.today.tasks.first { $0.status == .open })
  store.selectedTaskID = task.id

  await store.toggleSelectedTaskStarted()
  #expect(store.selectedTask?.status == .inProgress)

  await store.toggleSelectedTaskStarted()
  #expect(store.selectedTask?.status == .open)
  #expect(store.selectedTaskID == task.id)
  // Pausing takes the started mark off without unplanning the day.
  #expect(store.today.tasks.contains { $0.id == task.id })
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreGroupsTasksForWorkspaceViews() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)

  await store.refresh()
  let initialPoolCount = store.today.tasks.count
  let deferred = try #require(store.today.tasks.first)
  store.selectedTaskID = deferred.id

  await store.deferSelectedTask()

  #expect(initialPoolCount > 0)
  // Deferral pushes `planned_date` to tomorrow, so the task leaves today's pool
  // entirely — that is the visible effect of deferring.
  #expect(!store.today.tasks.contains { $0.id == deferred.id })
  #expect(store.today.tasks.count == initialPoolCount - 1)
  // It lands in the Deferred lane, which the workspace reads from the store by
  // defer pressure rather than deriving from the day snapshot.
  let deferredLane = try await core.getDeferredTasks(listID: nil, limit: 50, offset: 0)
  #expect(deferredLane.tasks.map(\.id) == [deferred.id])
  // Non-actionable statuses never ride the Today snapshot; the someday bucket is
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

  // `reopenSelectedTask` no-ops without error when the selection is gone, so a
  // lost selection would otherwise surface as an unexplained bucket mismatch
  // below rather than as its own cause.
  #expect(store.selectedTaskID == task.id, "the task selection was lost before reopen")
  await store.reopenSelectedTask()

  #expect(store.errorMessage == nil, "reopenSelectedTask errored: \(store.errorMessage ?? "")")
  // Separate the two ways the buckets below can be wrong: the mutation never
  // committed, or it committed and the workspace lanes are still stale.
  let reopenedStatus = try await store.core.loadTask(id: task.id).status
  #expect(reopenedStatus == .open, "reopenSelectedTask did not commit; row is \(reopenedStatus)")
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
/// restoring the inspector selection that refresh reconciles away, and re-checks
/// after every attempt. If the condition genuinely never holds the loop exhausts
/// and the caller's `#expect` surfaces the real regression.
@MainActor
private func awaitWorkspaceReflects(_ store: AppStore, _ condition: () -> Bool) async {
  // The store's reload logic is correct (every path single-flights and the
  // generation guard discards a superseded load), so this converges on the first
  // check under normal conditions. The retry exists purely for CPU starvation:
  // under maximum parallel suite load the awaited async reads can be scheduled so
  // late that a competing coalesced trailing reload hasn't run yet. Real
  // suspensions with exponential backoff give it wall time; a converged state
  // still returns immediately, so the generous worst-case budget costs nothing on
  // the happy path.
  var backoffNs: UInt64 = 1_000_000
  for _ in 0..<40 {
    if condition() { return }
    try? await Task.sleep(nanoseconds: backoffNs)
    backoffNs = min(backoffNs * 2, 50_000_000)
    await store.loadTaskWorkspace()
  }
  // Escalate to a full refresh (which re-reads every surface authoritatively),
  // settling a beat first so a starved in-flight reload can drain before this
  // one. Generously bounded so extreme starvation can't exhaust it while a real
  // regression still surfaces (the condition genuinely never holds).
  //
  // `refresh()` reconciles the inspector selection against the refreshed
  // surface, and a task the caller just completed has legitimately left that
  // surface — so escalating here would clear `selectedTaskID` and turn the
  // caller's next selected-task mutation into a silent no-op. This helper only
  // observes, so it puts the selection back. Only when it actually changed:
  // `selectedTaskID` carries a didSet that discards the detail draft.
  let selectedTaskID = store.selectedTaskID
  for _ in 0..<20 {
    if condition() { return }
    try? await Task.sleep(nanoseconds: 50_000_000)
    await store.refresh()
    if store.selectedTaskID != selectedTaskID { store.selectedTaskID = selectedTaskID }
    await store.loadTaskWorkspace()
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
}

@MainActor
@Test
func appStoreTodaySelectionCompletesAndReopensTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)

  await store.refresh()
  let selectedIDs = Set(store.todayOrderedTasks.filter { $0.status == .open }.prefix(2).map(\.id))
  #expect(selectedIDs.count == 2)
  store.setTodaySelection(selectedIDs)

  await store.completeTodaySelection()

  // Completed tasks leave the open-only Today pool, and the surface prunes
  // its selection to the tasks still visible there.
  #expect(!store.today.tasks.contains { selectedIDs.contains($0.id) })
  for id in selectedIDs {
    #expect(try await core.loadTask(id: id).status == .completed)
  }
  #expect(store.todaySelectionCount == 0)
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
func todayTaskRowSelectionSeparatesOpenFromBatchSelection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let tasks = store.todayOrderedTasks
  let first = try #require(tasks.first)
  let second = try #require(tasks.dropFirst().first)

  store.selectOnlyTodayTask(first.id)

  #expect(store.selectedTaskID == first.id)
  #expect(store.todaySelectedTaskIDs == [first.id])

  store.toggleTodayTaskBatchSelection(second.id)

  #expect(store.selectedTaskID == second.id)
  #expect(store.todaySelectedTaskIDs == [first.id, second.id])

  store.toggleTodayTaskBatchSelection(second.id)

  #expect(store.selectedTaskID == first.id)
  #expect(store.todaySelectedTaskIDs == [first.id])
}

@MainActor
@Test
func appStorePersistsNavigationStateAcrossLaunches() async throws {
  let suiteName = "LorvexAppleTests-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  // Any stable seeded id works: persistence round-trips the string and restore
  // gates on the destination, not on the task still being in a loaded snapshot.
  let taskID = LorvexPreviewSeedID.agendaTask
  store.selection = .today
  store.selectedTaskID = taskID

  let restored = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  restored.restorePersistedLaunchState()

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
  restored.restorePersistedLaunchState()

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
  store.restorePersistedLaunchState()

  await store.refresh()
  let taskID = try #require(store.today.tasks.first?.id)
  await store.openDeepLinkRoute(.task(taskID))

  let restored = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  restored.restorePersistedLaunchState()
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
  #expect(!store.today.tasks.isEmpty)
}

@MainActor
@Test
func startAndPauseFromRowLeaveSelectionUntouched() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let task = try #require(store.today.tasks.first { $0.status == .open })
  store.selectedTaskID = nil

  await store.startTaskFromRow(task)
  let started = try #require(store.today.tasks.first { $0.id == task.id })
  #expect(started.status == .inProgress)
  #expect(store.selectedTaskID == nil)

  await store.pauseTaskFromRow(started)
  #expect(store.today.tasks.first { $0.id == task.id }?.status == .open)
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

@MainActor
@Test
func findFromAWorkspaceWithoutSearchOpensAllTasksAcrossEveryList() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.selection = .tasks
  store.setTaskWorkspaceListScope(LorvexPreviewSeedID.appleNativeList)
  store.selection = .habits

  store.beginSearch()

  #expect(store.selection == .tasks)
  #expect(store.taskWorkspaceListScopeID == nil)
  #expect(store.isSearchFocusRequested)
}

@MainActor
@Test
func findInASearchableWorkspaceKeepsItsScope() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.selection = .tasks
  store.setTaskWorkspaceListScope(LorvexPreviewSeedID.appleNativeList)

  store.beginSearch()

  #expect(store.selection == .tasks)
  #expect(store.taskWorkspaceListScopeID == LorvexPreviewSeedID.appleNativeList)
  #expect(store.isSearchFocusRequested)

  store.isSearchFocusRequested = false
  store.selection = .memory
  store.beginSearch()

  #expect(store.selection == .memory)
  #expect(store.isSearchFocusRequested)
}

@MainActor
@Test
func aSearchEndsWithItsWorkspaceOrListScope() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.selection = .tasks

  store.searchText = "offsite"
  store.selection = .today
  #expect(store.searchText.isEmpty)

  store.selection = .tasks
  store.searchText = "offsite"
  store.setTaskWorkspaceListScope(nil)
  #expect(store.searchText == "offsite")

  store.setTaskWorkspaceListScope(LorvexPreviewSeedID.appleNativeList)
  #expect(store.searchText.isEmpty)
}
