import LorvexCore

extension AppStore {
  var focusSurfaceOrderedTasks: [LorvexTask] {
    var seen = Set<LorvexTask.ID>()
    return (
      filteredInProgressTodayTasks
        + filteredFocusedTasks
        + filteredRemainingTodayTasks
    ).filter { seen.insert($0.id).inserted }
  }

  func taskSelectionCount(on surface: AppStoreBatchCancelSurface) -> Int {
    switch surface {
    case .focus: focusWorkspaceSelectionCount
    case .taskWorkspace: taskWorkspaceSelectionCount
    case .selectedList: selectedListTaskSelectionCount
    }
  }

  func completeTaskSelection(on surface: AppStoreBatchCancelSurface) async {
    await completeBatch(on: surface)
  }

  func deferTaskSelection(on surface: AppStoreBatchCancelSurface) async {
    await deferBatch(on: surface)
  }

  func cancelTaskSelection(on surface: AppStoreBatchCancelSurface) async {
    await cancelBatch(on: surface)
  }

  func reopenTaskSelection(on surface: AppStoreBatchCancelSurface) async {
    await reopenBatch(on: surface)
  }

  func orderedTaskIDs(on surface: AppStoreBatchCancelSurface) -> [LorvexTask.ID] {
    switch surface {
    case .focus:
      focusSurfaceOrderedTasks.map(\.id)
    case .taskWorkspace:
      taskWorkspaceVisibleOrderedTaskIDs ?? taskWorkspaceAllTasks.map(\.id)
    case .selectedList:
      filteredSelectedListTasks.map(\.id)
    }
  }

  func setTaskSelection(
    _ ids: Set<LorvexTask.ID>,
    on surface: AppStoreBatchCancelSurface
  ) {
    switch surface {
    case .focus: setFocusWorkspaceSelection(ids)
    case .taskWorkspace: setTaskWorkspaceSelection(ids)
    case .selectedList: setSelectedListTaskSelection(ids)
    }
  }

  func extendTaskSelection(
    on surface: AppStoreBatchCancelSurface,
    to id: LorvexTask.ID
  ) {
    let ordered = orderedTaskIDs(on: surface)
    guard let target = ordered.firstIndex(of: id) else { return }
    let anchor = selectedTaskID.flatMap { ordered.firstIndex(of: $0) } ?? target
    let lower = min(anchor, target)
    let upper = max(anchor, target)
    setTaskSelection(Set(ordered[lower...upper]), on: surface)
  }

  func selectAllTasks(on surface: AppStoreBatchCancelSurface) {
    let ordered = orderedTaskIDs(on: surface)
    guard !ordered.isEmpty else { return }
    setTaskSelection(Set(ordered), on: surface)
  }

  func selectOnlyTask(
    _ id: LorvexTask.ID,
    on surface: AppStoreBatchCancelSurface
  ) {
    switch surface {
    case .focus: selectOnlyFocusWorkspaceTask(id)
    case .taskWorkspace: selectOnlyTaskInWorkspace(id)
    case .selectedList: selectOnlySelectedListTask(id)
    }
  }

  func arrowKeyTaskNavigation(
    on surface: AppStoreBatchCancelSurface
  ) -> WorkspaceTaskArrowKeyNavigation {
    WorkspaceTaskArrowKeyNavigation(
      orderedTaskIDs: orderedTaskIDs(on: surface),
      selectedTaskID: selectedTaskID,
      selectOnly: { id in self.selectOnlyTask(id, on: surface) },
      extendSelection: { id in self.extendTaskSelection(on: surface, to: id) }
    )
  }
}
