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

  func taskForFocusSurface(id: LorvexTask.ID) -> LorvexTask? {
    today.inProgressTasks.first { $0.id == id }
      ?? today.tasks.first { $0.id == id }
      ?? selectedListDetail?.tasks.first { $0.id == id }
      ?? taskWorkspaceTask(id: id)
      ?? taskDetailStorage.loadedTasksByID[id]
      ?? focusStorage.focusSurfaceTaskCache[id]
  }

  var focusSurfaceTaskIDs: [LorvexTask.ID] {
    var seen: Set<LorvexTask.ID> = []
    var ids: [LorvexTask.ID] = []

    for id in currentFocus?.taskIDs ?? [] where seen.insert(id).inserted {
      ids.append(id)
    }
    return ids
  }

  var focusSurfaceTaskSignature: String {
    [
      currentFocus?.date ?? "",
      String(currentFocus?.localChangeSequence ?? 0),
      focusSurfaceTaskIDs.joined(separator: ","),
    ].joined(separator: "|")
  }

  func loadFocusSurfaceTasks() async {
    let ids = focusSurfaceTaskIDs
    guard !ids.isEmpty else {
      focusStorage.focusSurfaceTaskCache = [:]
      return
    }

    for id in ids where taskForFocusSurface(id: id) == nil {
      do {
        focusStorage.focusSurfaceTaskCache[id] = try await core.loadTask(id: id)
      } catch LorvexCoreError.taskNotFound {
        // The task was deleted out from under the focus surface; skip it.
      } catch {
        // A transient load failure shouldn't silently leave a gap in the focus
        // surface — surface it without a blocking alert on a best-effort fill.
        // Route through the classifier so a raw GRDB (SQL / path) detail can't
        // reach the toast; the raw detail is logged to `error_logs`.
        toastMessage = await userFacingBannerMessage(
          for: error, source: "macos.ui.focus_surface_load_failed")
      }
    }

    let needed = Set(ids)
    focusStorage.focusSurfaceTaskCache = focusStorage.focusSurfaceTaskCache.filter {
      needed.contains($0.key)
    }
  }

  var currentFocusTaskCount: Int {
    currentFocus?.taskIDs.count ?? 0
  }

  /// Focus-plan task IDs as a `Set` for O(1) membership tests. Several SwiftUI
  /// rows test focus membership once or twice per `body`; over N rows that was
  /// O(N·F) against the `[String]`. The backing `Set` is rebuilt only when
  /// `currentFocus` is assigned (see ``AppStoreFocusStorage``), so each read
  /// here is a cheap cache lookup.
  var focusedTaskIDSet: Set<String> {
    focusStorage.focusedTaskIDSet
  }

  var selectedTaskIsFocused: Bool {
    guard let id = selectedTask?.id else { return false }
    return focusedTaskIDSet.contains(id)
  }

  var focusWorkspaceSelectedTaskIDs: Set<LorvexTask.ID> {
    focusStorage.selectedTaskIDs
  }

  var focusWorkspaceSelectedTasks: [LorvexTask] {
    let selected = focusStorage.selectedTaskIDs
    guard !selected.isEmpty else { return [] }
    return focusSurfaceOrderedTasks.filter { selected.contains($0.id) }
  }

  var focusWorkspaceSelectionCount: Int {
    focusStorage.selectedTaskIDs.count
  }

  func setFocusWorkspaceSelection(_ ids: Set<LorvexTask.ID>) {
    focusStorage.selectedTaskIDs = ids
    if let selectedTaskID, ids.contains(selectedTaskID) {
      return
    }
    selectedTaskID = ids.sorted().first
  }

  func selectOnlyFocusWorkspaceTask(_ id: LorvexTask.ID) {
    focusStorage.selectedTaskIDs = [id]
    selectTaskFromList(id)
  }

  func toggleFocusWorkspaceTaskBatchSelection(_ id: LorvexTask.ID) {
    if focusStorage.selectedTaskIDs.contains(id) {
      focusStorage.selectedTaskIDs.remove(id)
      if selectedTaskID == id {
        selectTaskFromList(focusStorage.selectedTaskIDs.sorted().first)
      }
    } else {
      focusStorage.selectedTaskIDs.insert(id)
      selectTaskFromList(id)
    }
  }

  var selectedTaskCanComplete: Bool {
    guard let selectedTask else { return false }
    return selectedTask.status.isActive
  }

  /// Defer is offered for the same non-terminal tasks as completion (never a
  /// completed or cancelled task). Shared by the Task menu (⇧⌘D) and the
  /// menu-bar action so the two enablement checks can't disagree.
  var selectedTaskCanDefer: Bool {
    selectedTaskCanComplete
  }

  var selectedTaskCanReopen: Bool {
    guard let selectedTask else { return false }
    return selectedTask.status.isResolved
  }

  /// Start (`open → in_progress`) is offered only for an `open` task. A
  /// dependency-blocked start still surfaces the core's typed error; the row's
  /// `dependsOn` list does not carry blocker statuses, so eligibility is not
  /// pre-filtered on blocked-ness here.
  var selectedTaskCanStart: Bool {
    selectedTask?.status == .open
  }

  /// "Mark as Not Started" (`in_progress → open`) is offered only for a started
  /// task.
  var selectedTaskCanMarkNotStarted: Bool {
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

  /// Started tasks pinned into Today's "In Progress" section, read from the
  /// snapshot's uncapped `inProgressTasks` query so every started task shows —
  /// not just those inside the priority-capped `today.tasks` overview pool. They
  /// are pulled out of the focus and remaining lanes below (which filter
  /// `today.tasks` to non-started work) so a started task shows in exactly one
  /// place.
  var inProgressTodayTasks: [LorvexTask] {
    today.inProgressTasks
  }

  var focusedTasks: [LorvexTask] {
    LorvexTaskSections.focus(order: currentFocus?.taskIDs ?? []) { taskForFocusSurface(id: $0) }
      .filter { $0.status != .inProgress }
  }

  var remainingTodayTasks: [LorvexTask] {
    let focusedIDs = focusedTaskIDSet
    return today.tasks.filter { !focusedIDs.contains($0.id) && $0.status != .inProgress }
  }

  /// Open Today tasks with no planned work day. Tasks that carry a
  /// `planned_date` (the surface stand-in for "deferred") fall into
  /// ``deferredTasks`` instead, so the two groups stay mutually exclusive.
  var openTasks: [LorvexTask] {
    today.tasks.lorvexOpenSection
  }

  /// Open Today tasks that carry a planned work day — the surface stand-in for
  /// "deferred" now that deferral pushes `planned_date` forward and leaves the
  /// status `open` (there is no `deferred` status).
  var deferredTasks: [LorvexTask] {
    today.tasks.lorvexDeferredSection
  }

  /// Calendar lane: planned-first action date (`planned_date ?? due_date`),
  /// mirroring the core's `getScheduledTasks`. A task surfaces on its planned
  /// work day, falling back to its deadline when unplanned.
  var scheduledTasks: [LorvexTask] {
    (calendarScheduledTasks ?? today.tasks).lorvexScheduledSection
  }
}
