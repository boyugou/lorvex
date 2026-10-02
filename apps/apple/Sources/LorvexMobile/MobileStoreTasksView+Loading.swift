import LorvexCore
import SwiftUI

extension MobileStoreTasksView {
  var loadKey: String {
    "\(String(describing: scope))|\(query.trimmingCharacters(in: .whitespacesAndNewlines))"
      + "|\(store.taskWorkspaceRevision)"
  }

  func load() async {
    // A concurrent `load`/`loadMore` would race on `page`; defer this reload
    // rather than dropping it, and drain it when the in-flight one settles.
    if isLoadingMore || isLoading {
      pendingReload = true
      return
    }
    isLoading = true
    let loaded = await store.taskWorkspacePage(scope: scope, query: query)
    // `.task(id: loadKey)` cancels this load when the status filter or query
    // changes; a superseded load must not overwrite the newer page.
    guard !Task.isCancelled else {
      isLoading = false
      // A reload deferred behind this one (the superseding `.task` parked it
      // because we held `isLoading`) must still run. It can't run on THIS
      // cancelled Task — its own `!Task.isCancelled` guard would abort the
      // recursion — so hand it to a fresh Task, which reloads the now-current
      // scope/query.
      if pendingReload {
        pendingReload = false
        Task { await load() }
      }
      return
    }
    // Animate the row diff so a completed/deferred task glides out of the list
    // after its completion moment instead of snapping away.
    withAnimation(.snappy) {
      page = loaded
    }
    pruneBatchSelection()
    reconcileSelectionAfterLoad()
    isLoading = false
    if pendingReload {
      pendingReload = false
      await load()
    } else {
      loadMoreIfAtLoadedEnd()
    }
  }

  /// Both layouts only ever *drop* a stale selection (its task left the page);
  /// neither auto-picks one. Regular width waits for the placeholder→detail tap;
  /// narrow width uses tap-to-push, where a `List` selection would only paint a
  /// confusing persistent highlight — so no row reads as selected until the user
  /// drives it (touch push, or keyboard nav, which lazily starts from the first).
  private func reconcileSelectionAfterLoad() {
    if horizontalSizeClass == .regular {
      if let current = store.selectedTaskID,
        !page.tasks.contains(where: { $0.id == current })
      {
        store.selectTask(nil)
      }
      return
    }
    if let selectedTaskID, !page.tasks.contains(where: { $0.id == selectedTaskID }) {
      self.selectedTaskID = nil
      store.selectTask(nil)
    }
  }

  func loadMore(offset: Int) async {
    guard !isLoading, !isLoadingMore else { return }
    isLoadingMore = true
    // Identity guard, NOT `Task.isCancelled`: the footer/keyboard launch this
    // from a bare `Task {}`, which is not a child of `.task(id: loadKey)` and so
    // is never cancelled by a scope/query/revision change. Capture the key and
    // re-check it after the await; appending a superseded continuation would mix
    // result sets (e.g. old-query rows under a cleared search field).
    let key = loadKey
    let nextPage = await store.taskWorkspacePage(scope: scope, query: query, offset: offset)
    if key == loadKey {
      page = page.appending(nextPage)
      pruneBatchSelection()
    }
    isLoadingMore = false
    // Run a reload that arrived (and was deferred) while this page loaded.
    if pendingReload {
      pendingReload = false
      await load()
    } else {
      loadMoreIfAtLoadedEnd()
    }
  }

  /// Fetches the next page when the footer below the last loaded row is on
  /// screen and no load is in flight. Runs when the footer appears and again
  /// whenever a load settles, so a page that adds too few rows to push the
  /// footer off screen (a narrowed scope can filter most of a page away) keeps
  /// loading until the screen fills or the scope has no more tasks. A failed
  /// fetch returns an empty last page, which removes the footer and ends the
  /// chain.
  func loadMoreIfAtLoadedEnd() {
    guard isLoadedEndVisible, !isLoading, !isLoadingMore, let nextOffset = page.nextOffset
    else { return }
    Task { await loadMore(offset: nextOffset) }
  }

  func toggleBatchSelectionMode() {
    withAnimation(.snappy) {
      isBatchSelecting.toggle()
      if !isBatchSelecting {
        batchSelectedTaskIDs.removeAll()
      }
    }
  }

  func toggleBatchSelection(_ taskID: LorvexTask.ID) {
    if batchSelectedTaskIDs.contains(taskID) {
      batchSelectedTaskIDs.remove(taskID)
    } else {
      batchSelectedTaskIDs.insert(taskID)
    }
  }

  func batchActionIDs(done: Bool) -> [LorvexTask.ID] {
    // Resolve from the store cache, not just `page.tasks`: a batch selection can
    // span pages the user scrolled through, and a reload can collapse `page`
    // back to the first window. Acting only on currently-visible rows would
    // silently skip selected tasks on the paged-out windows.
    batchSelectedTaskIDs
      .compactMap { store.resolveTask($0) }
      .filter { task in
        let isDone = task.status.isResolved
        return done ? isDone : !isDone
      }
      .map(\.id)
  }

  func performBatchComplete() async {
    let ids = batchActionIDs(done: false)
    guard await store.completeTasks(ids) else { return }
    batchSelectedTaskIDs.subtract(ids)
    await load()
  }

  func performBatchDefer() async {
    let ids = batchActionIDs(done: false)
    guard await store.deferTasksToTomorrow(ids) else { return }
    batchSelectedTaskIDs.subtract(ids)
    await load()
  }

  func performBatchReopen() async {
    let ids = batchActionIDs(done: true)
    guard await store.reopenTasks(ids) else { return }
    batchSelectedTaskIDs.subtract(ids)
    await load()
  }

  func pruneBatchSelection() {
    // Keep a selected id when it is either in the loaded window or still resolves
    // to an in-scope task in the cache. Intersecting only with `page.tasks` would
    // drop multi-page selections the moment a reload collapses `page` to the
    // first window; here only tasks that genuinely left the scope (resolved out
    // of it, or no longer resolvable) are pruned.
    batchSelectedTaskIDs = batchSelectedTaskIDs.filter { id in
      if page.tasks.contains(where: { $0.id == id }) { return true }
      guard let task = store.resolveTask(id) else { return false }
      return scopeIncludesTask(task)
    }
  }

  /// Mirrors the in-memory filter `taskWorkspacePage` applies when building a
  /// page, so an off-window selected task is judged in/out of scope the same way
  /// the loaded rows are.
  private func scopeIncludesTask(_ task: LorvexTask) -> Bool {
    scope.baseStatus.includes(task) && scope.matches(task)
      && (scope.listID == nil || task.listID == scope.listID)
  }

  var keyboardSelectedTaskID: LorvexTask.ID? {
    horizontalSizeClass == .regular ? store.selectedTaskID : selectedTaskID
  }

  func seedTaskListFocusIfNeeded() {
    guard !isTaskListFocused, keyboardSelectedTaskID == nil, !page.tasks.isEmpty else { return }
    isTaskListFocused = true
  }

  func moveTaskSelection(by offset: Int) -> Bool {
    guard !page.tasks.isEmpty else { return false }
    let ids = page.tasks.map(\.id)
    let currentIndex = keyboardSelectedTaskID.flatMap { ids.firstIndex(of: $0) }
    let nextIndex: Int
    if let currentIndex {
      if offset > 0, currentIndex == ids.index(before: ids.endIndex),
        let nextOffset = page.nextOffset
      {
        Task { await loadMoreForKeyboard(offset: nextOffset) }
        return true
      }
      nextIndex = min(max(currentIndex + offset, ids.startIndex), ids.index(before: ids.endIndex))
    } else {
      nextIndex = offset < 0 ? ids.index(before: ids.endIndex) : ids.startIndex
    }
    selectTaskForKeyboard(ids[nextIndex])
    return true
  }

  func loadMoreForKeyboard(offset: Int) async {
    let loadedCount = page.tasks.count
    await loadMore(offset: offset)
    guard page.tasks.count > loadedCount else { return }
    selectTaskForKeyboard(page.tasks[loadedCount].id)
  }

  func openSelectedTaskFromKeyboard() -> Bool {
    guard let taskID = keyboardSelectedTaskID ?? page.tasks.first?.id else { return false }
    selectTaskForKeyboard(taskID)
    if isBatchSelecting {
      toggleBatchSelection(taskID)
    } else if horizontalSizeClass != .regular {
      store.openTaskRouteOnCurrentStack(taskID)
    }
    return true
  }

  private func selectTaskForKeyboard(_ taskID: LorvexTask.ID) {
    selectedTaskID = taskID
    store.selectTask(taskID)
    keyboardScrollTarget = taskID
  }
}
