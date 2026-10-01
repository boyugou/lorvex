import LorvexCore

extension AppStore {
  /// Today's selectable rows in the order the main column draws them: the
  /// schedule's unfinished timed tasks in time order, the tasks without a
  /// time, then, while the Done section is open, what it lists. Arrow keys,
  /// shift-click ranges, Select All, batch actions, and the inspector's
  /// refresh check all read this one order, so none of them reaches a row the
  /// page hides or skips one it shows. Finished timed tasks stay out: the
  /// schedule may fold them behind its "earlier" line.
  var todayOrderedTasks: [LorvexTask] {
    let timed = todaySchedule.compactMap { row -> LorvexTask? in
      guard case .task(let task) = row.kind, task.status.isActionable else { return nil }
      return task
    }
    let untimed = todayUntimedItems.map(\.task)
    let done = isTodayDoneCollapsed ? [] : todayDoneListTasks
    var seen = Set<LorvexTask.ID>()
    return (timed + untimed + done).filter { seen.insert($0.id).inserted }
  }

  func taskSelectionCount(on surface: AppStoreBatchCancelSurface) -> Int {
    switch surface {
    case .today: todaySelectionCount
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
    case .today:
      todayOrderedTasks.map(\.id)
    case .taskWorkspace:
      taskWorkspaceVisibleOrderedTaskIDs ?? taskWorkspaceAllTasks.map(\.id)
    case .selectedList:
      selectedListTasks.map(\.id)
    }
  }

  func setTaskSelection(
    _ ids: Set<LorvexTask.ID>,
    on surface: AppStoreBatchCancelSurface
  ) {
    switch surface {
    case .today: setTodaySelection(ids)
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
    case .today: selectOnlyTodayTask(id)
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
