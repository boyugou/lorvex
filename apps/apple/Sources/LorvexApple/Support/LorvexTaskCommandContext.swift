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
  var singleTaskIsFocused: Bool {
    guard let id = singleTask?.id else { return false }
    return store.focusedTaskIDSet.contains(id)
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
