import LorvexCore
import SwiftUI

extension View {
  /// ⌫ on the focused task list cancels the highlighted task(s). When a batch is
  /// staged (active multi-selection > 1) it fans out to the whole selection via
  /// `cancelTaskSelection(on:)` — the same path the batch menu uses, including
  /// the recurring occurrence-vs-series dialog — so the key matches what the
  /// highlighted rows imply. A lone selection routes through the same
  /// `requestCancel` the row context menu uses, registering a reopen undo (via
  /// the environment's `UndoManager`) and routing a recurring task through the
  /// scope dialog. Gated like the context-menu Cancel (skips already
  /// completed/cancelled rows). `onDeleteCommand` only fires while the list —
  /// not a text field — holds focus, so it never disturbs in-place editing.
  func cancelSelectedTaskOnDelete(
    _ store: AppStore,
    on selectionSurface: AppStoreBatchCancelSurface
  ) -> some View {
    modifier(
      CancelSelectedTaskOnDeleteModifier(
        store: store,
        selectionSurface: selectionSurface
      )
    )
  }
}

/// Reads the environment `UndoManager` so the ⌫ cancel registers a reopen undo,
/// matching the context-menu and detail-pane Cancel. A bare `View` extension
/// can't see `@Environment`, hence this modifier.
private struct CancelSelectedTaskOnDeleteModifier: ViewModifier {
  let store: AppStore
  let selectionSurface: AppStoreBatchCancelSurface
  @Environment(\.undoManager) private var undoManager

  func body(content: Content) -> some View {
    content.onDeleteCommand {
      // A staged batch (> 1) cancels the whole selection; a lone selection acts
      // on the single inspector task.
      if store.taskSelectionCount(on: selectionSurface) > 1 {
        Task { await store.cancelTaskSelection(on: selectionSurface) }
        return
      }
      let tasks = selectionSurface.selectedTasks(store)
      guard tasks.count == 1, let task = tasks.first,
        task.status != .completed, task.status != .cancelled
      else { return }
      store.selectOnlyTask(task.id, on: selectionSurface)
      store.requestCancel(task, undoManager: undoManager)
    }
  }
}
