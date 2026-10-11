import AppKit
import LorvexCore
import SwiftUI

extension View {
  /// ⌘C on the focused task list copies the highlighted task(s) as plain text
  /// (``AppStore/shareText(for:)``), the same text the row menu's Copy as Text
  /// puts on the clipboard; several tasks follow one another, set apart by a
  /// rule. Like ⌫ (``cancelSelectedTaskOnDelete(_:on:)``), the command reaches
  /// the list only while the list, not a text field, holds focus, so copying
  /// inside a field stays the field's own.
  func copySelectedTasksAsText(
    _ store: AppStore,
    on selectionSurface: AppStoreBatchCancelSurface
  ) -> some View {
    onCopyCommand {
      let tasks = selectionSurface.selectedTasks(store)
      guard !tasks.isEmpty else { return [] }
      return [NSItemProvider(object: store.shareText(for: tasks) as NSString)]
    }
  }
}
