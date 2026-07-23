import LorvexCore
import SwiftUI

@MainActor
struct LorvexCommandDispatcher {
  let store: AppStore
  var openWindow: (LorvexWindowID) -> Void
  var activateApplication: () -> Void = {}
  var terminateApplication: () -> Void = {}

  func perform(_ action: AppCommandAction) {
    switch action {
    case .focusQuickAdd:
      // Capture happens inline in the current surface. Today and Tasks (whether
      // scoped to a list or showing all tasks) both host a `QuickAddRow`; any
      // other workspace has none, so route to Tasks first, then signal focus.
      if store.selection != .today, store.selection != .tasks {
        store.selection = .tasks
      }
      store.requestQuickAddFocus()
    case .refreshStore:
      Task { await store.refresh() }
    }
  }

  func perform(
    _ action: TaskCommandAction,
    selectionSurface: AppStoreBatchCancelSurface? = nil,
    fallbackTaskID: LorvexTask.ID? = nil,
    openTaskDetail: ((LorvexTask.ID) -> Void)? = nil
  ) {
    let selectedTasks = taskCommandSelection(
      on: selectionSurface,
      fallbackTaskID: fallbackTaskID
    )
    switch action {
    case .openTaskDetail:
      guard let task = singleTask(in: selectedTasks) else { return }
      activate(task, on: selectionSurface)
      if let openTaskDetail {
        openTaskDetail(task.id)
      } else {
        openWindow(.taskDetail)
      }
    case .saveSelectedTaskDraft:
      guard let task = singleTask(in: selectedTasks) else { return }
      activate(task, on: selectionSurface)
      Task { await store.saveSelectedTaskDraft() }
    case .toggleSelectedTaskFocus:
      guard let task = singleTask(in: selectedTasks) else { return }
      activate(task, on: selectionSurface)
      Task { await store.toggleSelectedTaskFocus() }
    case .deferSelectedTask:
      if let selectionSurface, selectedTasks.count > 1 {
        Task { await store.deferTaskSelection(on: selectionSurface) }
      } else if let task = singleTask(in: selectedTasks) {
        activate(task, on: selectionSurface)
        Task { await store.deferSelectedTask() }
      }
    case .completeSelectedTask:
      if let selectionSurface, selectedTasks.count > 1 {
        Task { await store.completeTaskSelection(on: selectionSurface) }
      } else if let task = singleTask(in: selectedTasks) {
        activate(task, on: selectionSurface)
        Task { await store.completeSelectedTask() }
      }
    case .reopenSelectedTask:
      if let selectionSurface, selectedTasks.count > 1 {
        Task { await store.reopenTaskSelection(on: selectionSurface) }
      } else if let task = singleTask(in: selectedTasks) {
        activate(task, on: selectionSurface)
        Task { await store.reopenSelectedTask() }
      }
    case .cancelSelectedTask:
      // A multi-selection in the active workspace fans out to the batch cancel
      // (which raises the occurrence-vs-series dialog for recurring tasks);
      // otherwise route a single task through `requestCancel` so it gets the
      // same scope dialog, matching the context menus and detail pane.
      if let selectionSurface, selectedTasks.count > 1 {
        Task { await store.cancelTaskSelection(on: selectionSurface) }
      } else if let task = singleTask(in: selectedTasks) {
        activate(task, on: selectionSurface)
        store.requestCancel(task)
      }
    }
  }

  private func taskCommandSelection(
    on selectionSurface: AppStoreBatchCancelSurface?,
    fallbackTaskID: LorvexTask.ID?
  ) -> [LorvexTask] {
    guard let selectionSurface else {
      return store.selectedTask.map { [$0] } ?? []
    }
    let surfaceTasks = selectionSurface.selectedTasks(store)
    guard surfaceTasks.isEmpty,
      let fallbackTaskID,
      store.selectedTask?.id == fallbackTaskID
    else { return surfaceTasks }
    return store.selectedTask.map { [$0] } ?? []
  }

  private func singleTask(in tasks: [LorvexTask]) -> LorvexTask? {
    tasks.count == 1 ? tasks[0] : nil
  }

  private func activate(
    _ task: LorvexTask,
    on selectionSurface: AppStoreBatchCancelSurface?
  ) {
    guard let selectionSurface else { return }
    store.selectOnlyTask(task.id, on: selectionSurface)
  }

  func perform(_ action: MainToolbarCommandAction) {
    switch action {
    case .appCommand(let appAction):
      perform(appAction)
    case .openWindow(let windowID):
      openWindow(windowID)
    }
  }

  func perform(_ action: MenuBarStatusCommandAction) {
    switch action {
    case .openWindow(let windowID):
      openWindow(windowID)
      activateApplication()
    case .appCommand(let appAction):
      perform(appAction)
      if appAction == .focusQuickAdd {
        activateApplication()
      }
    case .taskCommand(let taskAction):
      perform(taskAction)
      if taskAction == .openTaskDetail {
        activateApplication()
      }
    case .quitApplication:
      terminateApplication()
    }
  }
}
