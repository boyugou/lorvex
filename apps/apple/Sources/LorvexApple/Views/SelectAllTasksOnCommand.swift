import AppKit
import SwiftUI

extension View {
  /// ⌘A on the focused task list highlights every task the list shows, the
  /// selection the batch menu's Select All makes. Like ⌫
  /// (``cancelSelectedTaskOnDelete(_:on:)``), the command reaches the list only
  /// while the list, not a text field, holds focus, so Select All inside a
  /// field stays the field's own. The Tasks table is left out: its rows are an
  /// `NSTableView`, which answers the command itself and reports the selection
  /// through its binding.
  func selectAllTasksOnCommand(
    _ store: AppStore,
    on selectionSurface: AppStoreBatchCancelSurface
  ) -> some View {
    onCommand(#selector(NSResponder.selectAll(_:))) {
      store.selectAllTasks(on: selectionSurface)
    }
  }
}
