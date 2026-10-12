import Foundation
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
    let content = todayColumnContent
    let timed = content.schedule.compactMap { row -> LorvexTask? in
      guard case .task(let task) = row.kind, task.status.isActionable else { return nil }
      return task
    }
    let untimed = content.untimedItems.map(\.task)
    let done = isTodayDoneCollapsed ? [] : content.doneListTasks
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

  func completeTaskSelection(
    on surface: AppStoreBatchCancelSurface, undoManager: UndoManager? = nil
  ) async {
    await completeBatch(on: surface, undoManager: undoManager)
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
    if surface == .today { return todayArrowKeyNavigation() }
    return WorkspaceTaskArrowKeyNavigation(
      orderedTaskIDs: orderedTaskIDs(on: surface),
      selectedTaskID: selectedTaskID,
      selectOnly: { id in self.selectOnlyTask(id, on: surface) },
      extendSelection: { id in self.extendTaskSelection(on: surface, to: id) }
    )
  }

  /// Today's arrow-key stops in the order the main column draws them: the
  /// schedule's events and unfinished timed tasks in time order (an event the
  /// schedule folds behind its "earlier" line is not drawn, so it is not a
  /// stop), the tasks without a time, then what the Done section lists while
  /// it is open. An event's stop is its calendar id, which never equals a task id.
  func todayArrowKeyStops() -> (ids: [String], eventIDs: Set<String>) {
    let content = todayColumnContent
    let fold = LorvexTodayTimeline.earlierFold(content.schedule)
    var eventIDs = Set<String>()
    var ids = [String]()
    for (index, row) in content.schedule.enumerated() {
      switch row.kind {
      case .task(let task) where task.status.isActionable:
        ids.append(task.id)
      case .event(let event) where !fold.contains(index):
        ids.append(event.id)
        eventIDs.insert(event.id)
      default:
        break
      }
    }
    ids += content.untimedItems.map(\.task.id)
    if !isTodayDoneCollapsed { ids += content.doneListTasks.map(\.id) }
    var seen = Set<String>()
    return (ids.filter { seen.insert($0).inserted }, eventIDs)
  }

  private func todayArrowKeyNavigation() -> WorkspaceTaskArrowKeyNavigation {
    let stops = todayArrowKeyStops()
    let eventID = selection == .today ? selectedCalendarEventID : nil
    return WorkspaceTaskArrowKeyNavigation(
      orderedTaskIDs: stops.ids,
      selectedTaskID: selectedTaskID ?? eventID,
      selectOnly: { id in
        if stops.eventIDs.contains(id) {
          guard let event = self.todayScheduleEvents.first(where: { $0.id == id }) else { return }
          self.selectedTaskID = nil
          self.selectCalendarEvent(event)
        } else {
          self.selectOnlyTask(id, on: .today)
        }
      },
      extendSelection: { id in
        // A range grows over tasks only; landing on an event, or growing from
        // one, opens that row alone.
        if stops.eventIDs.contains(id) || self.selectedTaskID == nil {
          self.arrowKeyTaskNavigation(on: .today).selectOnly(id)
        } else {
          self.extendTaskSelection(on: .today, to: id)
        }
      }
    )
  }
}
