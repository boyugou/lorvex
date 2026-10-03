import Foundation
import LorvexCore

extension AppStore {
  /// Rows in one page of a list's tasks. The core clamps any request to 500.
  static let listDetailPageSize = 100

  /// How many rows a reload of `listID`'s tasks asks for: one page, or every
  /// row already loaded once the user has paged further, so the reload a
  /// mutation triggers does not drop the rows below the first page out from
  /// under the reader.
  func listDetailReloadLimit(for listID: LorvexList.ID) -> Int {
    guard let detail = selectedListDetail, detail.list.id == listID else {
      return Self.listDetailPageSize
    }
    return max(Self.listDetailPageSize, detail.tasks.count)
  }

  /// Whether the selected list has actionable tasks beyond the loaded rows.
  var selectedListHasMoreTasks: Bool {
    selectedListDetail?.nextOffset != nil
  }

  /// Append the next page of the selected list's actionable tasks below the
  /// loaded rows. A page is dropped when the detail it continues was replaced
  /// while it was in flight — another list was selected, or a reload landed —
  /// since its offset no longer lines up with the rows on screen; a row that
  /// is already loaded is never appended twice.
  func loadMoreSelectedListTasks() async {
    guard !isLoadingMoreSelectedListTasks, let current = selectedListDetail,
      let nextOffset = current.nextOffset
    else {
      return
    }
    isLoadingMoreSelectedListTasks = true
    defer { isLoadingMoreSelectedListTasks = false }
    await perform {
      let page = try await core.loadListDetail(
        id: current.list.id, limit: Self.listDetailPageSize, offset: nextOffset)
      guard selectedListDetail == current else { return }
      let loadedIDs = Set(current.tasks.map(\.id))
      var merged = page
      merged.tasks = current.tasks + page.tasks.filter { !loadedIDs.contains($0.id) }
      merged.blockedTaskIDs = current.blockedTaskIDs.union(page.blockedTaskIDs)
      merged.returned = merged.tasks.count
      merged.limit = merged.tasks.count
      merged.offset = 0
      selectedListDetail = merged
    }
  }

  func loadSelectedListDetailForUI() async {
    await perform {
      try await loadSelectedListDetail()
    }
  }

  /// Reload every surface that shows list membership counts after a task
  /// mutation: the sidebar's list rows (`lists`, whose open/done counts a
  /// status change moves) and the selected list's detail pane. Mutating
  /// actions that only reloaded the detail pane left the sidebar badge stale
  /// until the next full refresh.
  func refreshListSurfaces() async throws {
    lists = try await core.loadLists()
    try await loadSelectedListDetail()
  }

  func loadSelectedListDetail(preservingTaskSelection protectedTaskID: LorvexTask.ID? = nil)
    async throws
  {
    guard let listID = selectedListID else {
      selectedListDetail = nil
      selectedListTaskIDs.removeAll()
      return
    }
    // Drop a detail held for a *different* list before awaiting the new one, so
    // the detail pane shows its loading/placeholder state rather than flashing
    // the previously-selected list's name and tasks while the load is in flight.
    if selectedListDetail?.list.id != listID {
      selectedListDetail = nil
      selectedListTaskIDs.removeAll()
    }
    let detail = try await core.loadListDetail(
      id: listID, limit: listDetailReloadLimit(for: listID), offset: 0)
    // The selection can change while the load is in flight (the user clicks a
    // different list). Discard a result for a list that is no longer selected so
    // it can't overwrite the newer selection's detail.
    guard selectedListID == listID else { return }
    selectedListDetail = detail
    pruneSelectedListTaskSelection(preservingTaskSelection: protectedTaskID)
  }

  func setSelectedListTaskSelection(_ ids: Set<LorvexTask.ID>) {
    selectedListTaskIDs = ids
    if let selectedTaskID, ids.contains(selectedTaskID) {
      return
    }
    selectedTaskID = ids.sorted().first
  }

  func selectOnlySelectedListTask(_ id: LorvexTask.ID) {
    selectedListTaskIDs = [id]
    selectTaskFromList(id)
  }

  func toggleSelectedListTaskBatchSelection(_ id: LorvexTask.ID) {
    if selectedListTaskIDs.contains(id) {
      selectedListTaskIDs.remove(id)
      if selectedTaskID == id {
        selectTaskFromList(selectedListTaskIDs.sorted().first)
      }
    } else {
      selectedListTaskIDs.insert(id)
      selectTaskFromList(id)
    }
  }

  var selectedListTasksForBatch: [LorvexTask] {
    let selected = selectedListTaskIDs
    guard !selected.isEmpty else { return [] }
    return (selectedListDetail?.tasks ?? []).filter { selected.contains($0.id) }
  }

  var selectedListTaskSelectionCount: Int {
    selectedListTaskIDs.count
  }

  private func pruneSelectedListTaskSelection(
    preservingTaskSelection protectedTaskID: LorvexTask.ID? = nil
  ) {
    let validIDs = Set(selectedListDetail?.tasks.map(\.id) ?? [])
    selectedListTaskIDs.formIntersection(validIDs)
    // Only reconcile the global inspector selection against the list pool while
    // the user is actually in the Lists workspace. `loadSelectedListDetail` runs
    // on every mutation (complete/defer/save), so reconciling unconditionally
    // would clobber a selectedTaskID that belongs to another workspace's pool —
    // e.g. mid-save during a Today-workspace edit, where it would erase the
    // user's in-flight navigation target.
    guard selection == .lists else { return }
    if let selectedTaskID, selectedTaskID != protectedTaskID, !validIDs.contains(selectedTaskID) {
      self.selectedTaskID = selectedListTaskIDs.sorted().first
    }
  }
}
