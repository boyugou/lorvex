import AppKit
import LorvexCore
import SwiftUI

private enum WorkspaceSelectableTaskRowMetrics {
  static let batchControlTrailingPadding: CGFloat = 6
  static let batchControlTopPadding: CGFloat = 7
  static let trailingControlSpacing: CGFloat = 4
}

struct WorkspaceSelectableTaskRow: View {
  let task: LorvexTask
  @Bindable var store: AppStore
  let selectionSurface: AppStoreBatchCancelSurface
  let isBatchSelected: Bool
  let batchAccessibilityIdentifier: String
  let toggleBatchSelection: () -> Void
  let openTask: () -> Void
  var isFocused = false
  /// Show the task's owning list — set on cross-list surfaces (Tasks, Today),
  /// left off in a single list's detail pane.
  var showsOwningList = false
  /// Reveal a quick defer control on hover — set on the Today list, where
  /// pushing a task to another day is the dominant inline action.
  var showsDeferButton = false

  @State private var isHovering = false

  var body: some View {
    TaskRowItem(store: store, task: task, isFocused: isFocused, showsOwningList: showsOwningList)
      // macOS multi-select conventions: ⌘-click toggles a row in/out of the
      // batch, ⇧-click extends the range from the last plain-clicked anchor, a
      // plain click opens the task. Modifiers are read at click time via
      // `NSEvent` because SwiftUI's `TapGesture` doesn't surface them.
      .onTapGesture {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
          toggleBatchSelection()
        } else if flags.contains(.shift) {
          store.extendTaskSelection(on: selectionSurface, to: task.id)
        } else if store.selectedTaskID == task.id {
          // Re-clicking the open task collapses its detail, matching the
          // inspector's ✕ and the habit / calendar panels.
          store.selectedTaskID = nil
        } else {
          openTask()
        }
      }
      .overlay(alignment: .topTrailing) {
        // Trailing affordances are secondary. Keep them out of the leading scan
        // path so selected rows do not grow a noisy gutter beside the completion
        // circle. Defer sits left of batch-select; both reveal on hover.
        HStack(spacing: WorkspaceSelectableTaskRowMetrics.trailingControlSpacing) {
          if showsDeferButton {
            WorkspaceRowDeferButton(store: store, task: task, isVisible: isHovering)
          }
          WorkspaceBatchSelectionButton(
            isSelected: isBatchSelected,
            isVisible: isHovering,
            accessibilityIdentifier: batchAccessibilityIdentifier,
            action: toggleBatchSelection
          )
        }
        .padding(.top, WorkspaceSelectableTaskRowMetrics.batchControlTopPadding)
        .padding(.trailing, WorkspaceSelectableTaskRowMetrics.batchControlTrailingPadding)
      }
      // VoiceOver / Full Keyboard Access: the default activation opens the
      // task detail inspector, matching a plain mouse click. The "Complete"
      // named action remains on the row via `LorvexTaskRow`'s accessibilityAction.
      .accessibilityAction(.default, openTask)
      // Full Keyboard Access: a keyboard-only user tabbing through the row
      // list needs a focus ring and a way to trigger the row's primary action,
      // matching the pattern already used on calendar event blocks and habit
      // cards (`CalendarWeekGridEventBlock`, `HabitMomentumCard`).
      .focusable(true)
      .onKeyPress(.return) {
        openTask()
        return .handled
      }
      .onKeyPress(.space) {
        openTask()
        return .handled
      }
      .onHover { isHovering = $0 }
      .contextMenu {
        WorkspaceTaskContextMenu(store: store, task: task)
      }
      .background {
        if isBatchSelected {
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
            .fill(.tint.opacity(0.035))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
