import LorvexCore
import SwiftUI

/// Identifies the task whose actions sheet is open. The sheet reads the task
/// back from the store by id, so a started or paused task shows its current
/// state rather than the value it opened with.
struct LorvexWatchTaskReference: Identifiable, Hashable {
  let id: LorvexTask.ID
}

/// A task's actions on the wrist, under its title: Start or Pause, Tomorrow,
/// and Cancel. The sheet closes after an action, and as soon as the task leaves
/// Today by any other path.
struct LorvexWatchTaskActionsSheet: View {
  @Bindable var store: LorvexWatchStore
  let taskID: LorvexTask.ID
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    if let task = store.tasks.first(where: { $0.id == taskID }) {
      List {
        Text(userContent: task.title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(4)
          .listRowBackground(Color.clear)
        LorvexWatchStartPauseButton(store: store, task: task) { dismiss() }
          .listRowBackground(Color.clear)
        LorvexWatchDeferButton(store: store, task: task) { dismiss() }
          .listRowBackground(Color.clear)
        LorvexWatchCancelButton(store: store, task: task) { dismiss() }
          .listRowBackground(Color.clear)
        if let reason = store.taskActionUnavailableReason {
          Text(reason)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
        }
      }
      .accessibilityIdentifier("watch.task.actions")
    } else {
      Color.clear
        .task { dismiss() }
    }
  }
}
