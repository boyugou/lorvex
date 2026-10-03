import Foundation
import LorvexCore

extension AppStore {
  var selectedTask: LorvexTask? {
    guard let selectedTaskID else { return nil }
    // Search each pool with short-circuit instead of allocating a combined
    // `today.tasks + selectedListDetail.tasks` array on every access (this is
    // read from many UI sites per render).
    return today.inProgressTasks.first { $0.id == selectedTaskID }
      ?? today.tasks.first { $0.id == selectedTaskID }
      ?? selectedListDetail?.tasks.first { $0.id == selectedTaskID }
      ?? taskWorkspaceTask(id: selectedTaskID)
      ?? taskDetailStorage.loadedTasksByID[selectedTaskID]
  }

  /// The task with `id` among the rows Today can show: the day's list, what
  /// is done today, then the other loaded pools.
  func todayTask(id: LorvexTask.ID) -> LorvexTask? {
    today.tasks.first { $0.id == id }
      ?? today.inProgressTasks.first { $0.id == id }
      ?? doneTodayTasks.first { $0.id == id }
      ?? selectedListDetail?.tasks.first { $0.id == id }
      ?? taskWorkspaceTask(id: id)
      ?? taskDetailStorage.loadedTasksByID[id]
  }

  var todaySelectedTaskIDs: Set<LorvexTask.ID> {
    todayStorage.selectedTaskIDs
  }

  var todaySelectedTasks: [LorvexTask] {
    let selected = todayStorage.selectedTaskIDs
    guard !selected.isEmpty else { return [] }
    return todayOrderedTasks.filter { selected.contains($0.id) }
  }

  var todaySelectionCount: Int {
    todayStorage.selectedTaskIDs.count
  }

  func setTodaySelection(_ ids: Set<LorvexTask.ID>) {
    todayStorage.selectedTaskIDs = ids
    if let selectedTaskID, ids.contains(selectedTaskID) {
      return
    }
    selectedTaskID = ids.sorted().first
  }

  func selectOnlyTodayTask(_ id: LorvexTask.ID) {
    todayStorage.selectedTaskIDs = [id]
    selectTaskFromList(id)
  }

  /// Drop selected ids that Today no longer shows, after a change took tasks
  /// off the list.
  func pruneTodaySelection() {
    let visibleIDs = Set(todayOrderedTasks.map(\.id))
    todayStorage.selectedTaskIDs.formIntersection(visibleIDs)
  }

  func toggleTodayTaskBatchSelection(_ id: LorvexTask.ID) {
    if todayStorage.selectedTaskIDs.contains(id) {
      todayStorage.selectedTaskIDs.remove(id)
      if selectedTaskID == id {
        selectTaskFromList(todayStorage.selectedTaskIDs.sorted().first)
      }
    } else {
      todayStorage.selectedTaskIDs.insert(id)
      selectTaskFromList(id)
    }
  }

  var selectedTaskCanComplete: Bool {
    guard let selectedTask else { return false }
    return selectedTask.status.isActive
  }

  var selectedTaskCanReopen: Bool {
    guard let selectedTask else { return false }
    return selectedTask.status.isResolved
  }

  /// Start (`open → in_progress`) is shown only for an `open` task. Whether it
  /// is available also depends on the tasks it waits on, which the task's
  /// `dependsOn` list names without their statuses; the detail reads them
  /// separately (``refreshSelectedTaskStartGate()``) and keeps Start shown
  /// but unavailable while one is unfinished.
  var selectedTaskCanStart: Bool {
    selectedTask?.status == .open
  }

  /// Pause (`in_progress → open`) is offered only for a started task.
  var selectedTaskCanPause: Bool {
    selectedTask?.status == .inProgress
  }

  /// Move-to-Someday is offered only for an active `open` task — a completed,
  /// cancelled, or already-someday task has nothing to park.
  var selectedTaskCanMarkSomeday: Bool {
    selectedTask?.status == .open
  }

  /// A someday task is activated (someday → open) by its own "Move to Open"
  /// action, distinct from the completed/cancelled `selectedTaskCanReopen` path,
  /// so the two carry their own label and glyph.
  var selectedTaskIsSomeday: Bool {
    selectedTask?.status == .someday
  }

  var selectedTaskCanCancel: Bool {
    guard let selectedTask else { return false }
    return selectedTask.status.isActive
  }

  var selectedTaskCanSave: Bool {
    selectedTaskCanSave(draftHasChanges: selectedTaskDraftHasChanges)
  }

  func selectedTaskCanSave(draftHasChanges: Bool) -> Bool {
    draftHasChanges
      && taskDetailTitleIsValid
      && taskDetailEstimateIsValid
  }

  /// True when `task` carries a deadline the logical day has already passed.
  func isOverdue(_ task: LorvexTask) -> Bool {
    LorvexTaskSections.isOverdue(task, logicalDay: logicalTodayDateString)
  }

  /// True when something `task` depends on is unfinished, as the loaded
  /// surfaces read it: Today's snapshot, the Tasks workspace's pages, the
  /// selected list's rows, and the selected task's own check
  /// (``heldUpTaskID``). One answer for every surface, so a task reads the
  /// same wherever it shows.
  func isBlocked(_ task: LorvexTask) -> Bool {
    today.blockedTaskIDs.contains(task.id)
      || taskWorkspaceStorage.blockedTaskIDs.contains(task.id)
      || selectedListDetail?.blockedTaskIDs.contains(task.id) == true
      || heldUpTaskID == task.id
  }

  /// Calendar lane: planned-first action date (`planned_date ?? due_date`),
  /// mirroring the core's `getScheduledTasks`. A task surfaces on its planned
  /// work day, falling back to its deadline when unplanned.
  ///
  /// The `today.tasks` fallback only covers the window before
  /// `calendarScheduledTasks` has loaded, and is bounded by the day pool: the
  /// calendar's own read is what surfaces other days' work.
  var scheduledTasks: [LorvexTask] {
    (calendarScheduledTasks ?? today.tasks).lorvexScheduledSection
  }
}
