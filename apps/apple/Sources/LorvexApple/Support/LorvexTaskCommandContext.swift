import LorvexCore
import SwiftUI

struct LorvexTaskCommandContext {
  let store: AppStore
  let selectionSurface: AppStoreBatchCancelSurface?
  let fallbackTaskID: LorvexTask.ID?

  init(
    store: AppStore,
    selectionSurface: AppStoreBatchCancelSurface?,
    fallbackTaskID: LorvexTask.ID? = nil
  ) {
    self.store = store
    self.selectionSurface = selectionSurface
    self.fallbackTaskID = fallbackTaskID
  }

  @MainActor
  var selectedTasks: [LorvexTask] {
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

  @MainActor
  var singleTask: LorvexTask? {
    let tasks = selectedTasks
    return tasks.count == 1 ? tasks[0] : nil
  }

  @MainActor
  var singleTaskIsStarted: Bool {
    singleTask?.status == .inProgress
  }

  /// True while the selection holds a task that can still be planned: one that is
  /// neither finished nor cancelled.
  @MainActor
  var canPlanSelection: Bool {
    selectedTasks.contains { $0.status.isActionable }
  }

  /// Plans the selected tasks on the product day `days` after today, each keeping
  /// its own time of day. Tasks that are finished or cancelled are left alone. The
  /// change registers one undo with `undoManager`.
  @MainActor
  func planSelection(daysFromToday days: Int, undoManager: UndoManager?) async {
    await store.planTasks(
      ids: selectedTasks.map(\.id), daysFromToday: days, undoManager: undoManager)
  }
}

private struct LorvexTaskCommandContextKey: FocusedValueKey {
  typealias Value = LorvexTaskCommandContext
}

extension FocusedValues {
  var lorvexTaskCommandContext: LorvexTaskCommandContext? {
    get { self[LorvexTaskCommandContextKey.self] }
    set { self[LorvexTaskCommandContextKey.self] = newValue }
  }
}
