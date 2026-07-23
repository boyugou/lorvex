import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore

@MainActor
@Test
func taskWorkspaceLoadsStatusBucketsFromCoreQueries() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  #expect(!store.taskWorkspaceHasLoaded)

  await store.refresh()
  let deferredID = try #require(store.today.tasks.first?.id)
  store.selectedTaskID = deferredID
  await store.deferSelectedTask()

  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceHasLoaded)
  #expect(store.taskWorkspaceOpenTasks.isEmpty == false)
  #expect(store.taskWorkspaceDeferredTasks.map(\.id).contains(deferredID))
  #expect(store.taskWorkspaceSomedayTasks.map(\.id).contains(LorvexPreviewSeedID.standingDeskTask))
}

@MainActor
@Test
func taskWorkspaceSelectionResolvesOutsideTodaySnapshot() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  await store.loadTaskWorkspace()

  let someday = try #require(store.taskWorkspaceSomedayTasks.first)
  store.selectedTaskID = someday.id

  #expect(store.selectedTask?.id == someday.id)
}

@MainActor
@Test
func taskWorkspaceSearchUsesCoreQueryBackedBuckets() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.searchText = "standing"

  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceSomedayTasks.map(\.id) == [LorvexPreviewSeedID.standingDeskTask])
  #expect(store.taskWorkspaceOpenTasks.allSatisfy { $0.matchesSearch("standing") })
}

@MainActor
@Test
func taskWorkspaceListScopeQueriesSelectedListBuckets() async throws {
  let core = try await makeSeededInMemoryCore()
  let scopedList = try await core.createList(name: "Scoped Project", description: nil)
  let scopedTask = try await core.createTask(title: "Scoped needle task", notes: "")
  let unrelatedTask = try await core.createTask(title: "Unrelated needle task", notes: "")
  _ = try await core.moveTask(id: scopedTask.id, toListID: scopedList.id)

  let store = AppStore(core: core)
  await store.refresh()
  store.searchText = "needle"
  store.setTaskWorkspaceListScope(scopedList.id)
  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceListScopeID == scopedList.id)
  #expect(store.taskWorkspaceOpenTasks.map(\.id).contains(scopedTask.id))
  #expect(!store.taskWorkspaceOpenTasks.map(\.id).contains(unrelatedTask.id))
  #expect(Set(store.taskWorkspaceOpenTasks.map(\.id)) == [scopedTask.id])
}

@MainActor
@Test
func taskWorkspaceListScopeKeepsDeferredBucketScopedToList() async throws {
  let core = try await makeSeededInMemoryCore()
  let scopedList = try await core.createList(name: "Deferred Project", description: nil)
  let scopedTask = try await core.createTask(title: "Scoped deferred task", notes: "")
  let unrelatedTask = try await core.createTask(title: "Unrelated deferred task", notes: "")
  _ = try await core.moveTask(id: scopedTask.id, toListID: scopedList.id)
  _ = try await core.deferTask(id: scopedTask.id, until: Date(timeIntervalSince1970: 1_779_494_400))
  _ = try await core.deferTask(id: unrelatedTask.id, until: Date(timeIntervalSince1970: 1_779_494_400))

  let store = AppStore(core: core)
  await store.refresh()
  store.setTaskWorkspaceListScope(scopedList.id)
  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceOpenTasks.isEmpty)
  #expect(Set(store.taskWorkspaceDeferredTasks.map(\.id)) == [scopedTask.id])
}

@MainActor
@Test
func taskWorkspaceListScopeKeepsPlannedButUndeferredTaskInOpen() async throws {
  let core = try await makeSeededInMemoryCore()
  let scopedList = try await core.createList(name: "Health", description: nil)
  let task = try await core.createTask(title: "Annual physical", notes: "")
  _ = try await core.moveTask(id: task.id, toListID: scopedList.id)
  // A planned work day but never deferred (defer_count stays 0). It must still
  // appear in the open backlog — the regression that left a list whose tasks all
  // carried a planned_date showing empty, because planned tasks were dropped
  // from open while the Deferred lane only catches defer_count > 0.
  _ = try await core.updateTask(
    id: task.id, title: "Annual physical", notes: "", priority: task.priority,
    estimatedMinutes: nil, dueDate: nil,
    plannedDate: Date(timeIntervalSince1970: 1_779_494_400),
    tags: [], dependsOn: [])

  let store = AppStore(core: core)
  await store.refresh()
  store.setTaskWorkspaceListScope(scopedList.id)
  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceOpenTasks.map(\.id) == [task.id])
  #expect(store.taskWorkspaceDeferredTasks.isEmpty)
}

@MainActor
@Test
func taskWorkspaceDeferredSearchDoesNotFilterOnlyTheFirstDeferredPage() async throws {
  let core = try await makeSeededInMemoryCore()
  for index in 0..<500 {
    let task = try await core.createTask(title: "Deferred filler \(index)", notes: "")
    _ = try await core.deferTask(id: task.id, until: Date(timeIntervalSince1970: 1_779_494_400))
  }
  let match = try await core.createTask(title: "Deferred beyond first page", notes: "needle-token")
  _ = try await core.deferTask(id: match.id, until: Date(timeIntervalSince1970: 1_779_494_400))

  let store = AppStore(core: core)
  store.searchText = "needle-token"
  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceDeferredTasks.map(\.id) == [match.id])
}

@MainActor
@Test
func taskWorkspaceDeferredSearchFillsPageAcrossLocallyFilteredRawPages() async throws {
  let core = try await makeSeededInMemoryCore()
  for index in 0..<500 {
    _ = try await core.createTask(title: "Open raw match \(index)", notes: "deferred-paging-token")
  }
  let match = try await core.createTask(title: "Deferred raw match", notes: "deferred-paging-token")
  _ = try await core.deferTask(id: match.id, until: Date(timeIntervalSince1970: 1_779_494_400))

  let store = AppStore(core: core)
  store.searchText = "deferred-paging-token"
  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceDeferredTasks.map(\.id) == [match.id])
}

@MainActor
@Test
func taskWorkspaceDeferredSearchExcludesNonDeferredMatches() async throws {
  // Two open tasks share a search token; only one has ever been deferred. Under
  // search, `search_tasks` has no `deferred` status (it queries `open`), so
  // without the defer_count narrowing the never-deferred match would leak into
  // the Deferred lane and duplicate the Open lane.
  let core = try await makeSeededInMemoryCore()
  let deferred = try await core.createTask(title: "Archive cleanup deferred", notes: "shared-token")
  _ = try await core.deferTask(id: deferred.id, until: Date(timeIntervalSince1970: 1_779_494_400))
  let openOnly = try await core.createTask(title: "Archive cleanup open", notes: "shared-token")

  let store = AppStore(core: core)
  store.searchText = "shared-token"
  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceDeferredTasks.map(\.id) == [deferred.id])
  #expect(store.taskWorkspaceOpenTasks.map(\.id) == [openOnly.id])
}

@MainActor
@Test
func taskWorkspaceLoadsAdditionalCoreBackedSearchPages() async throws {
  let core = try await makeSeededInMemoryCore()
  var createdIDs: [LorvexTask.ID] = []
  for index in 0..<501 {
    let task = try await core.createTask(title: "Paged Mac Workspace \(index)", notes: "paged-mac-token")
    createdIDs.append(task.id)
  }

  let store = AppStore(core: core)
  store.searchText = "paged-mac-token"
  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceOpenTasks.count == 500)
  #expect(store.taskWorkspaceHasMore(status: .open))

  await store.loadMoreTaskWorkspace(status: .open)

  #expect(store.taskWorkspaceOpenTasks.count == 501)
  #expect(store.taskWorkspaceOpenTasks.map(\.id).contains(createdIDs.last ?? ""))
  #expect(!store.taskWorkspaceHasMore(status: .open))
}

@MainActor
@Test
func taskWorkspaceSelectionSupportsBatchCompleteAndReopen() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  await store.loadTaskWorkspace()

  let openTasks = Array(store.taskWorkspaceOpenTasks.prefix(2))
  #expect(openTasks.count == 2)
  let selectedIDs = Set(openTasks.map(\.id))
  store.setTaskWorkspaceSelection(selectedIDs)

  await store.completeTaskWorkspaceSelection()

  #expect(selectedIDs.isSubset(of: Set(store.taskWorkspaceCompletedTasks.map(\.id))))
  #expect(store.taskWorkspaceSelectionCount == selectedIDs.count)

  await store.reopenTaskWorkspaceSelection()

  #expect(selectedIDs.isSubset(of: Set(store.taskWorkspaceOpenTasks.map(\.id))))
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func taskWorkspaceRowSelectionSeparatesOpenFromBatchSelection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  await store.loadTaskWorkspace()

  let first = try #require(store.taskWorkspaceOpenTasks.first)
  let second = try #require(store.taskWorkspaceOpenTasks.dropFirst().first)

  store.selectOnlyTaskInWorkspace(first.id)
  #expect(store.selectedTaskID == first.id)
  #expect(store.taskWorkspaceSelectedTaskIDs == Set([first.id]))

  store.toggleTaskWorkspaceBatchSelection(second.id)
  #expect(store.selectedTaskID == second.id)
  #expect(store.taskWorkspaceSelectedTaskIDs == Set([first.id, second.id]))

  store.toggleTaskWorkspaceBatchSelection(second.id)
  #expect(store.selectedTaskID == first.id)
  #expect(store.taskWorkspaceSelectedTaskIDs == Set([first.id]))
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func taskWorkspaceSelectionSupportsBatchDefer() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore(), now: {
    Date(timeIntervalSince1970: 1_779_494_400)
  })
  await store.refresh()
  await store.loadTaskWorkspace()

  let openTasks = Array(store.taskWorkspaceOpenTasks.prefix(2))
  #expect(openTasks.count == 2)
  let selectedIDs = Set(openTasks.map(\.id))
  store.setTaskWorkspaceSelection(selectedIDs)

  await store.deferTaskWorkspaceSelection()

  #expect(selectedIDs.isSubset(of: Set(store.taskWorkspaceDeferredTasks.map(\.id))))
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func taskWorkspaceSelectionSupportsBatchMove() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.draftListName = "Batch Target"
  await store.createDraftList()
  let targetListID = try #require(store.selectedListID)
  await store.loadTaskWorkspace()

  let openTasks = Array(store.taskWorkspaceOpenTasks.prefix(2))
  #expect(openTasks.count == 2)
  let selectedIDs = Set(openTasks.map(\.id))
  store.setTaskWorkspaceSelection(selectedIDs)

  await store.moveTaskWorkspaceSelection(toListID: targetListID)

  #expect(selectedIDs.isSubset(of: Set(store.selectedListDetail?.tasks.map(\.id) ?? [])))
  #expect(store.lists?.lists.first { $0.id == targetListID }?.openCount == selectedIDs.count)
  #expect(store.taskWorkspaceSelectionCount == selectedIDs.count)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func taskWorkspaceSelectionSupportsBatchCancel() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  await store.loadTaskWorkspace()

  let openTasks = Array(store.taskWorkspaceOpenTasks.prefix(2))
  #expect(openTasks.count == 2)
  let selectedIDs = Set(openTasks.map(\.id))
  store.setTaskWorkspaceSelection(selectedIDs)

  await store.cancelTaskWorkspaceSelection()
  // A bulk cancel now stages a confirmation; with no recurring tasks it is a
  // plain "cancel N tasks" confirm that the dialog resolves.
  #expect(store.pendingRecurringBatchCancel != nil)
  await store.confirmPendingRecurringBatchCancel(scope: .thisOccurrence)

  #expect(selectedIDs.isSubset(of: Set(store.taskWorkspaceCancelledTasks.map(\.id))))
  #expect(store.taskWorkspaceSelectionCount == selectedIDs.count)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func taskWorkspaceRecurringBatchCancelWaitsForScopeAndCanEndSeries() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  await store.loadTaskWorkspace()

  let recurring = try #require(store.taskWorkspaceOpenTasks.first { $0.id == LorvexPreviewSeedID.statusUpdateTask })
  let nonRecurring = try #require(store.taskWorkspaceOpenTasks.first { $0.recurrence == nil })
  let selectedIDs = Set([recurring.id, nonRecurring.id])
  store.setTaskWorkspaceSelection(selectedIDs)

  await store.cancelTaskWorkspaceSelection()

  #expect(store.pendingRecurringBatchCancel?.surface == .taskWorkspace)
  #expect(Set(store.pendingRecurringBatchCancel?.taskIDs ?? []) == selectedIDs)
  #expect(store.pendingRecurringBatchCancel?.recurringTaskIDs == [recurring.id])
  #expect((try await core.loadTask(id: recurring.id)).status == .open)

  await store.confirmPendingRecurringBatchCancel(scope: .all)

  let cancelledRecurring = try await core.loadTask(id: recurring.id)
  let cancelledNonRecurring = try await core.loadTask(id: nonRecurring.id)
  #expect(cancelledRecurring.status == .cancelled)
  #expect(cancelledRecurring.recurrence == nil)
  #expect(cancelledNonRecurring.status == .cancelled)
  #expect(store.pendingRecurringBatchCancel == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func selectedTaskDetailLoadsOutsideLocalCaches() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()

  let created = try await core.createTask(title: "Deep linked outside snapshot", notes: "")
  #expect(store.today.tasks.map(\.id).contains(created.id) == false)

  store.selectedTaskID = created.id
  #expect(store.selectedTask == nil)

  await store.loadSelectedTaskDetail()

  #expect(store.selectedTask?.id == created.id)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func missingSelectedTaskDetailClearsStaleSelection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  store.selectedTaskID = "missing-task-from-old-launch"
  #expect(store.selectedTask == nil)

  await store.loadSelectedTaskDetail()

  #expect(store.selectedTaskID == nil)
  #expect(store.taskDetailTitle.isEmpty)
}
