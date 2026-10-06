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
  /// See ``LorvexTaskRow/isBlocked``.
  var isBlocked = false
  /// Show the task's owning list — set on cross-list surfaces (Tasks, Today),
  /// left off in a single list's detail pane.
  var showsOwningList = false
  /// Reveal the Start or Pause and defer controls on hover: set on the Today
  /// list, where starting a task and pushing it to another day are the
  /// dominant inline actions.
  var showsTodayActions = false
  /// See ``LorvexTaskRow/timeLabel``.
  var timeLabel: String? = nil
  /// See ``LorvexTaskRow/timeIsRunning``.
  var timeIsRunning = false
  /// See ``LorvexTaskRow/chips``.
  var chips: [LorvexTaskRowChip] = []
  /// See ``TaskRowItem/searchQuery``.
  var searchQuery = ""

  @State private var isHovering = false

  /// More than one task is selected. A plain click selects the task it opens,
  /// so a single selected task is just the open one; only a real batch shows
  /// the trailing selection controls.
  private var batchIsActive: Bool {
    store.taskSelectionCount(on: selectionSurface) > 1
  }

  /// Select adds the row to the selection, as ⌘-click does; Deselect takes it
  /// out of a batch. The open task outside a batch gets neither.
  private var batchMenuItem: WorkspaceTaskBatchMenuItem? {
    if !isBatchSelected {
      return WorkspaceTaskBatchMenuItem(
        title: String(localized: "tasks.row.select", defaultValue: "Select", table: "Localizable", bundle: LorvexL10n.bundle),
        toggle: toggleBatchSelection)
    }
    guard batchIsActive else { return nil }
    return WorkspaceTaskBatchMenuItem(
      title: String(localized: "tasks.row.deselect", defaultValue: "Deselect", table: "Localizable", bundle: LorvexL10n.bundle),
      toggle: toggleBatchSelection)
  }

  var body: some View {
    TaskRowItem(
      store: store, task: task, isBlocked: isBlocked,
      showsOwningList: showsOwningList, timeLabel: timeLabel, timeIsRunning: timeIsRunning,
      chips: chips, searchQuery: searchQuery,
      dragPayload: { store.taskDragPayload(for: task, on: selectionSurface) },
      dragCount: isBatchSelected && batchIsActive
        ? store.taskSelectionCount(on: selectionSurface) : 1)
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
        // circle. Start and defer sit left of batch-select and reveal on hover;
        // batch-select shows only during a batch, since outside one its circle
        // would read as a second completion circle.
        HStack(spacing: WorkspaceSelectableTaskRowMetrics.trailingControlSpacing) {
          if showsTodayActions, task.status.isActionable {
            // A task held up by an unfinished one shows no Start: its
            // blocked badge already says why.
            if !store.startIsHeldUp(for: task) {
              WorkspaceRowStartButton(store: store, task: task, isVisible: isHovering)
            }
            WorkspaceRowDeferButton(store: store, task: task, isVisible: isHovering)
          }
          WorkspaceBatchSelectionButton(
            isSelected: isBatchSelected && batchIsActive,
            isVisible: isHovering && batchIsActive,
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
        WorkspaceTaskContextMenu(store: store, task: task, batchItem: batchMenuItem)
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
