import LorvexCore
import SwiftUI

extension MobileStoreTasksView {
  var sectionTitle: String {
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return String(
        localized: "tasks.results.task_count", defaultValue: "\(page.totalMatching) tasks",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    return String(
      localized: "tasks.results.result_count", defaultValue: "\(page.totalMatching) results",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  var loadKey: String {
    "\(String(describing: scope))|\(query.trimmingCharacters(in: .whitespacesAndNewlines))"
      + "|\(store.taskWorkspaceRevision)"
  }

  func debounceSearchIfNeeded() async {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    try? await Task.sleep(for: .milliseconds(250))
  }

  func load() async {
    guard !isLoadingMore else { return }
    isLoading = true
    defer { isLoading = false }
    let loaded = await store.taskWorkspacePage(scope: scope, query: query)
    // `.task(id: loadKey)` cancels this load when the status filter or query
    // changes; a superseded load must not overwrite the newer page.
    guard !Task.isCancelled else { return }
    // Animate the row diff so a completed/deferred task glides out of the list
    // after its completion moment instead of snapping away.
    withAnimation(.snappy) {
      page = loaded
    }
    pruneBatchSelection()
    // Both layouts only ever *drop* a stale selection (its task left the page);
    // neither auto-picks one. Regular width waits for the placeholder→detail tap;
    // narrow width uses tap-to-push, where a `List` selection would only paint a
    // confusing persistent highlight — so no row reads as selected until the user
    // drives it (touch push, or keyboard nav, which lazily starts from the first).
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
    defer { isLoadingMore = false }
    let nextPage = await store.taskWorkspacePage(scope: scope, query: query, offset: offset)
    // A status/query change cancels this load via `.task(id: loadKey)`; appending
    // a stale page to a page from a different query would mix result sets.
    guard !Task.isCancelled else { return }
    page = page.appending(nextPage)
    pruneBatchSelection()
  }

  func mutateAndReload(_ action: () async -> Bool) async {
    guard await action() else { return }
    await load()
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
    page.tasks
      .filter { batchSelectedTaskIDs.contains($0.id) }
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
    let visibleIDs = Set(page.tasks.map(\.id))
    batchSelectedTaskIDs = batchSelectedTaskIDs.intersection(visibleIDs)
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
  }
}
