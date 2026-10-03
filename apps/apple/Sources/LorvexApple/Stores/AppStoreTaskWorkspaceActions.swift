import Foundation
import LorvexCore

extension AppStore {
  var taskWorkspaceIsLoading: Bool {
    taskWorkspaceStorage.isLoading
  }

  var taskWorkspaceHasLoaded: Bool {
    taskWorkspaceStorage.hasLoaded
  }

  var taskWorkspaceLoadFailureMessage: String? {
    taskWorkspaceStorage.loadFailureMessage
  }

  var taskWorkspaceOpenTasks: [LorvexTask] {
    taskWorkspaceStorage.openTasks
  }

  var taskWorkspaceDeferredTasks: [LorvexTask] {
    taskWorkspaceStorage.deferredTasks
  }

  var taskWorkspaceScheduledTasks: [LorvexTask] {
    taskWorkspaceStorage.scheduledTasks
  }

  var taskWorkspaceCompletedTasks: [LorvexTask] {
    taskWorkspaceStorage.completedTasks
  }

  var taskWorkspaceCancelledTasks: [LorvexTask] {
    taskWorkspaceStorage.cancelledTasks
  }

  var taskWorkspaceSomedayTasks: [LorvexTask] {
    taskWorkspaceStorage.somedayTasks
  }

  var taskWorkspaceSelectedTaskIDs: Set<LorvexTask.ID> {
    taskWorkspaceStorage.selectedTaskIDs
  }

  var taskWorkspaceListScopeID: LorvexList.ID? {
    taskWorkspaceStorage.listScopeID
  }

  var taskWorkspaceLoadSignature: String {
    [trimmedSearchText, taskWorkspaceStorage.listScopeID ?? ""].joined(separator: "|")
  }

  var taskWorkspaceSelectedTasks: [LorvexTask] {
    let selected = taskWorkspaceStorage.selectedTaskIDs
    guard !selected.isEmpty else { return [] }
    return taskWorkspaceAllTasks.filter { selected.contains($0.id) }
  }

  var taskWorkspaceSelectionCount: Int {
    taskWorkspaceStorage.selectedTaskIDs.count
  }

  var taskWorkspaceVisibleOrderedTaskIDs: [LorvexTask.ID]? {
    taskWorkspaceStorage.visibleOrderedTaskIDs
  }

  func setTaskWorkspaceVisibleOrderedTaskIDs(_ ids: [LorvexTask.ID]) {
    taskWorkspaceStorage.visibleOrderedTaskIDs = ids
    taskWorkspaceStorage.selectedTaskIDs.formIntersection(Set(ids))
  }

  func taskWorkspaceHasMore(status: TaskWorkspaceSection) -> Bool {
    taskWorkspaceNextOffset(status: status) != nil
  }

  func taskWorkspaceIsLoadingMore(status: TaskWorkspaceSection) -> Bool {
    taskWorkspaceStorage.loadingMoreStatus == status
  }

  func setTaskWorkspaceListScope(_ id: LorvexList.ID?) {
    let scopeID = id?.trimmedNilIfEmpty
    if scopeID != taskWorkspaceStorage.listScopeID {
      // Picking another list shows that list, not the previous scope's search.
      searchText = ""
      clearTaskWorkspaceBuckets()
    }
    taskWorkspaceStorage.listScopeID = scopeID
    pruneTaskWorkspaceSelection()
  }

  /// Empties the workspace before a scope change's load lands. The previous
  /// scope's rows never show under the new scope's header; the workspace shows
  /// its loading state instead, and the new rows arrive without animation, in
  /// a fresh scroll view at the top. Animating one scope's rows into
  /// another's in a scrolled lazy stack can leave SwiftUI re-measuring the
  /// stack without end.
  private func clearTaskWorkspaceBuckets() {
    taskWorkspaceStorage.openTasks = []
    taskWorkspaceStorage.deferredTasks = []
    taskWorkspaceStorage.scheduledTasks = []
    taskWorkspaceStorage.completedTasks = []
    taskWorkspaceStorage.cancelledTasks = []
    taskWorkspaceStorage.somedayTasks = []
    taskWorkspaceStorage.openNextOffset = nil
    taskWorkspaceStorage.deferredNextOffset = nil
    taskWorkspaceStorage.scheduledNextOffset = nil
    taskWorkspaceStorage.completedNextOffset = nil
    taskWorkspaceStorage.cancelledNextOffset = nil
    taskWorkspaceStorage.somedayNextOffset = nil
    taskWorkspaceStorage.visibleOrderedTaskIDs = nil
    taskWorkspaceStorage.hasLoaded = false
    taskWorkspaceStorage.loadedQuery = nil
    taskWorkspaceStorage.loadFailureMessage = nil
    // A page append still in flight belongs to the previous scope.
    taskWorkspaceStorage.loadGeneration &+= 1
  }

  /// Single-flights the full workspace reload: at most one runs at a time, and a
  /// reload requested while one is in flight coalesces into a trailing re-run, so
  /// the latest requester (typically a mutation's awaited reload) observes the
  /// freshest committed state instead of racing an older-started background reload
  /// whose reads predate the write and reverting the buckets to a pre-mutation
  /// snapshot. On `@MainActor` this is race-free: the in-flight task clears
  /// `reloadTask` synchronously right after its final `reloadPending` check (no
  /// `await` between), so no request can slip into the gap and be dropped.
  ///
  /// A failure while the workspace already shows rows raises the error alert
  /// over them. A failure before the scope's first load lands is shown by the
  /// workspace itself, in place of its rows and with a retry, since an alert
  /// would leave a loading row behind it that never ends.
  func loadTaskWorkspace() async {
    do {
      try await loadTaskWorkspaceReportingFailure()
    } catch {
      if taskWorkspaceStorage.hasLoaded {
        await presentUserFacingError(error)
      } else {
        await recordTaskWorkspaceLoadFailure(error)
      }
    }
  }

  private func recordTaskWorkspaceLoadFailure(_ error: Error) async {
    let classification = UserFacingError.classify(error)
    taskWorkspaceStorage.loadFailureMessage = UserFacingError.message(
      for: classification, copy: userFacingErrorCopy)
    try? await core.appendDiagnosticLog(
      source: "macos.ui.task_workspace_load_failed",
      level: "error",
      message: "The task workspace failed to load.",
      details: classification.technicalDetail)
  }

  /// Throwing core of the coalesced workspace load. Post-commit mutation paths
  /// route this through `reconcileAfterCommittedMutation`, so a derived read
  /// failure is diagnostic-only and can never make an already-durable create
  /// look as though it failed.
  private func loadTaskWorkspaceReportingFailure() async throws {
    if let inFlight = taskWorkspaceStorage.reloadTask {
      taskWorkspaceStorage.reloadPending = true
      try await inFlight.value
      return
    }
    let task = Task { @MainActor in
      var finalFailure: (any Error)?
      repeat {
        taskWorkspaceStorage.reloadPending = false
        do {
          try await self.performTaskWorkspaceLoad()
          finalFailure = nil
        } catch {
          finalFailure = error
        }
      } while taskWorkspaceStorage.reloadPending
      taskWorkspaceStorage.reloadTask = nil
      if let finalFailure {
        throw finalFailure
      }
    }
    taskWorkspaceStorage.reloadTask = task
    try await task.value
  }

  private func performTaskWorkspaceLoad() async throws {
    taskWorkspaceStorage.isLoading = true
    defer { taskWorkspaceStorage.isLoading = false }
    taskWorkspaceStorage.loadRequestGeneration &+= 1
    let requestGeneration = taskWorkspaceStorage.loadRequestGeneration
    let query = trimmedSearchText
    let listScopeID = taskWorkspaceStorage.listScopeID
    async let open = taskWorkspacePage(status: .open, query: query, listID: listScopeID)
    async let deferred = taskWorkspacePage(status: .deferred, query: query, listID: listScopeID)
    async let scheduled = taskWorkspacePage(status: .scheduled, query: query, listID: listScopeID)
    async let completed = taskWorkspacePage(status: .completed, query: query, listID: listScopeID)
    async let cancelled = taskWorkspacePage(status: .cancelled, query: query, listID: listScopeID)
    async let someday = taskWorkspacePage(status: .someday, query: query, listID: listScopeID)

    let pages = try await (open, deferred, scheduled, completed, cancelled, someday)
    // Discard a load whose query was superseded while its five reads were in
    // flight, so a slower earlier keystroke can't overwrite the newer query's
    // results. The list scope participates in the same stale-load guard.
    guard query == trimmedSearchText, listScopeID == taskWorkspaceStorage.listScopeID else {
      return
    }
    // A newer full load began while this one's six reads were in flight —
    // discard so an older/slower read (e.g. a background republish- or
    // CloudSync-triggered reload landing late under heavy load) cannot
    // overwrite the newer snapshot's buckets with pre-mutation rows.
    guard requestGeneration == taskWorkspaceStorage.loadRequestGeneration else { return }
    // Replacing the buckets supersedes any page append still in flight.
    taskWorkspaceStorage.loadGeneration &+= 1
    // The open section shows every actionable task (open + started); the
    // Deferred lane is the defer_count-based `get_deferred_tasks` cut (and,
    // under a text search, the open matches narrowed to `defer_count > 0` —
    // see `taskWorkspacePage`). Keep the two disjoint by id so a
    // repeatedly-deferred task appears only under Deferred — in both search and
    // non-search modes — without hiding planned-but-never-deferred tasks from
    // open.
    let deferredIDs = Set(pages.1.tasks.map(\.id))
    // Hidden (defer-until) tasks surface only under Scheduled. The real core
    // already excludes them from the open list query; keep the workspace
    // correct even against a backend that doesn't (e.g. the in-memory fake) by
    // subtracting them from open here, mirroring the deferred treatment.
    let scheduledIDs = Set(pages.2.tasks.map(\.id))
    let openTasks = pages.0.tasks.filter {
      !deferredIDs.contains($0.id) && !scheduledIDs.contains($0.id)
    }
    func applyBuckets() {
      taskWorkspaceStorage.openTasks = openTasks
      taskWorkspaceStorage.deferredTasks = pages.1.tasks
      taskWorkspaceStorage.scheduledTasks = pages.2.tasks
      taskWorkspaceStorage.completedTasks = pages.3.tasks
      taskWorkspaceStorage.cancelledTasks = pages.4.tasks
      taskWorkspaceStorage.somedayTasks = pages.5.tasks
      taskWorkspaceStorage.blockedTaskIDs = pages.0.blockedTaskIDs
        .union(pages.1.blockedTaskIDs).union(pages.2.blockedTaskIDs)
        .union(pages.3.blockedTaskIDs).union(pages.4.blockedTaskIDs)
        .union(pages.5.blockedTaskIDs)
    }
    // A refresh of the same search that changes a few rows (a completed,
    // deferred, or moved task) animates, so the row settles out of the queue
    // instead of vanishing; a first load, a new search, or a change over many
    // rows replaces the rows at once.
    let sections = [openTasks, pages.1.tasks, pages.2.tasks, pages.3.tasks, pages.4.tasks, pages.5.tasks]
    if taskWorkspaceStorage.animatesReplacingSections(with: sections, query: query) {
      lorvexAnimated(TaskRowChangeAnimation.animation) { applyBuckets() }
    } else {
      applyBuckets()
    }
    taskWorkspaceStorage.loadedQuery = query
    taskWorkspaceStorage.openNextOffset = pages.0.nextOffset
    taskWorkspaceStorage.deferredNextOffset = pages.1.nextOffset
    taskWorkspaceStorage.scheduledNextOffset = pages.2.nextOffset
    taskWorkspaceStorage.completedNextOffset = pages.3.nextOffset
    taskWorkspaceStorage.cancelledNextOffset = pages.4.nextOffset
    taskWorkspaceStorage.somedayNextOffset = pages.5.nextOffset
    taskWorkspaceStorage.hasLoaded = true
    taskWorkspaceStorage.loadFailureMessage = nil
    pruneTaskWorkspaceSelection()
    errorMessage = nil
  }

  /// Reloads the workspace once it has loaded, or retries a first load that
  /// failed, so a refresh after a sync or a change elsewhere also recovers a
  /// workspace showing its load failure.
  func reloadTaskWorkspaceIfLoaded() async {
    guard taskWorkspaceStorage.hasLoaded || taskWorkspaceStorage.loadFailureMessage != nil
    else { return }
    await loadTaskWorkspace()
  }

  func reloadTaskWorkspaceIfLoadedReportingFailure() async throws {
    guard taskWorkspaceStorage.hasLoaded || taskWorkspaceStorage.loadFailureMessage != nil
    else { return }
    try await loadTaskWorkspaceReportingFailure()
  }

  func loadMoreTaskWorkspace(status: TaskWorkspaceSection) async {
    guard taskWorkspaceStorage.loadingMoreStatus == nil,
      let nextOffset = taskWorkspaceNextOffset(status: status)
    else {
      return
    }
    taskWorkspaceStorage.loadingMoreStatus = status
    defer { taskWorkspaceStorage.loadingMoreStatus = nil }

    do {
      let query = trimmedSearchText
      let listScopeID = taskWorkspaceStorage.listScopeID
      let loadGeneration = taskWorkspaceStorage.loadGeneration
      let page = try await taskWorkspacePage(
        status: status,
        query: query,
        listID: listScopeID,
        offset: nextOffset
      )
      // Drop the page if the query/scope changed or a full reload replaced the
      // buckets while it was in flight — appending a pre-reload page onto the
      // new arrays would duplicate rows and SwiftUI identities.
      guard query == trimmedSearchText, listScopeID == taskWorkspaceStorage.listScopeID,
        loadGeneration == taskWorkspaceStorage.loadGeneration
      else {
        return
      }
      appendTaskWorkspacePage(page, status: status)
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }

  func taskWorkspaceTask(id: LorvexTask.ID) -> LorvexTask? {
    taskWorkspaceStorage.openTasks.first { $0.id == id }
      ?? taskWorkspaceStorage.deferredTasks.first { $0.id == id }
      ?? taskWorkspaceStorage.scheduledTasks.first { $0.id == id }
      ?? taskWorkspaceStorage.completedTasks.first { $0.id == id }
      ?? taskWorkspaceStorage.cancelledTasks.first { $0.id == id }
      ?? taskWorkspaceStorage.somedayTasks.first { $0.id == id }
  }

  func setTaskWorkspaceSelection(_ ids: Set<LorvexTask.ID>) {
    taskWorkspaceStorage.selectedTaskIDs = ids
    if let selectedTaskID, ids.contains(selectedTaskID) {
      return
    }
    selectedTaskID = ids.sorted().first
  }

  func selectOnlyTaskInWorkspace(_ id: LorvexTask.ID) {
    taskWorkspaceStorage.selectedTaskIDs = [id]
    selectedTaskID = id
  }

  func toggleTaskWorkspaceBatchSelection(_ id: LorvexTask.ID) {
    if taskWorkspaceStorage.selectedTaskIDs.contains(id) {
      taskWorkspaceStorage.selectedTaskIDs.remove(id)
      if selectedTaskID == id {
        selectedTaskID = taskWorkspaceStorage.selectedTaskIDs.sorted().first
      }
    } else {
      taskWorkspaceStorage.selectedTaskIDs.insert(id)
      selectedTaskID = id
    }
  }

  func replaceTaskInWorkspace(_ task: LorvexTask) {
    replaceTask(&taskWorkspaceStorage.openTasks, with: task)
    replaceTask(&taskWorkspaceStorage.deferredTasks, with: task)
    replaceTask(&taskWorkspaceStorage.scheduledTasks, with: task)
    replaceTask(&taskWorkspaceStorage.completedTasks, with: task)
    replaceTask(&taskWorkspaceStorage.cancelledTasks, with: task)
    replaceTask(&taskWorkspaceStorage.somedayTasks, with: task)
  }

  private func replaceTask(_ tasks: inout [LorvexTask], with task: LorvexTask) {
    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
      tasks[index] = task
    }
  }

  private func taskWorkspaceNextOffset(status: TaskWorkspaceSection) -> Int? {
    switch status {
    case .open: return taskWorkspaceStorage.openNextOffset
    case .deferred: return taskWorkspaceStorage.deferredNextOffset
    case .scheduled: return taskWorkspaceStorage.scheduledNextOffset
    case .completed: return taskWorkspaceStorage.completedNextOffset
    case .cancelled: return taskWorkspaceStorage.cancelledNextOffset
    case .someday: return taskWorkspaceStorage.somedayNextOffset
    }
  }

  var taskWorkspaceAllTasks: [LorvexTask] {
    taskWorkspaceStorage.openTasks
      + taskWorkspaceStorage.deferredTasks
      + taskWorkspaceStorage.scheduledTasks
      + taskWorkspaceStorage.completedTasks
      + taskWorkspaceStorage.cancelledTasks
      + taskWorkspaceStorage.somedayTasks
  }

  private func pruneTaskWorkspaceSelection() {
    let validIDs = Set(
      taskWorkspaceAllTasks.filter { task in
        taskWorkspaceStorage.listScopeID == nil || task.listID == taskWorkspaceStorage.listScopeID
      }.map(\.id))
    taskWorkspaceStorage.selectedTaskIDs.formIntersection(validIDs)
  }

  private func appendTaskWorkspacePage(_ page: TaskWorkspacePage, status: TaskWorkspaceSection) {
    taskWorkspaceStorage.blockedTaskIDs.formUnion(page.blockedTaskIDs)
    switch status {
    case .open:
      // Mirror the disjoint-by-id rule from the full load (non-search only) so a
      // deferred or hidden task appended on "load more" doesn't double-appear in
      // open.
      let excludedIDs =
        trimmedSearchText.isEmpty
        ? Set(taskWorkspaceStorage.deferredTasks.map(\.id))
          .union(taskWorkspaceStorage.scheduledTasks.map(\.id))
        : Set<LorvexTask.ID>()
      taskWorkspaceStorage.openTasks.append(
        contentsOf: page.tasks.filter { !excludedIDs.contains($0.id) })
      taskWorkspaceStorage.openNextOffset = page.nextOffset
    case .deferred:
      taskWorkspaceStorage.deferredTasks.append(contentsOf: page.tasks)
      taskWorkspaceStorage.deferredNextOffset = page.nextOffset
    case .scheduled:
      taskWorkspaceStorage.scheduledTasks.append(contentsOf: page.tasks)
      taskWorkspaceStorage.scheduledNextOffset = page.nextOffset
    case .completed:
      taskWorkspaceStorage.completedTasks.append(contentsOf: page.tasks)
      taskWorkspaceStorage.completedNextOffset = page.nextOffset
    case .cancelled:
      taskWorkspaceStorage.cancelledTasks.append(contentsOf: page.tasks)
      taskWorkspaceStorage.cancelledNextOffset = page.nextOffset
    case .someday:
      taskWorkspaceStorage.somedayTasks.append(contentsOf: page.tasks)
      taskWorkspaceStorage.somedayNextOffset = page.nextOffset
    }
  }
}
