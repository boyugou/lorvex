import LorvexCore
import SwiftUI

private enum WorkspaceRowDeferButtonMetrics {
  static let size: CGFloat = 17
}

/// A hover-revealed defer control for Today rows — a quick way to push a task to
/// tomorrow / in a few days / next week without opening it. Mirrors
/// `WorkspaceBatchSelectionButton`'s reveal-on-hover treatment so the trailing
/// affordances read as a set: hidden until the row is hovered or the control
/// holds focus, then drawn in the secondary style at full strength, since a
/// control has to be legible to be aimed at.
struct WorkspaceRowDeferButton: View {
  @Bindable var store: AppStore
  let task: LorvexTask
  let isVisible: Bool
  @FocusState private var isButtonFocused: Bool

  var body: some View {
    TaskDeferMenu(store: store, onDefer: { date in
      Task { await store.deferTaskFromRow(task, until: date) }
    }) {
      Image(systemName: "clock.arrow.circlepath")
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(
          width: WorkspaceRowDeferButtonMetrics.size,
          height: WorkspaceRowDeferButtonMetrics.size
        )
        .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .focused($isButtonFocused)
    .frame(
      width: WorkspaceRowDeferButtonMetrics.size,
      height: WorkspaceRowDeferButtonMetrics.size
    )
    .opacity((isVisible || isButtonFocused) ? 1 : 0)
    .help(String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityLabel(String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("today.row.defer.\(task.id)")
  }
}

/// A hover-revealed Start or Pause control for Today rows, beside the defer
/// control: starting marks the task as begun, and pausing takes the mark off.
/// Shown only for tasks that can start or pause: started, or open and not held
/// up by an unfinished task (``AppStore/startIsHeldUp(for:)``).
struct WorkspaceRowStartButton: View {
  @Bindable var store: AppStore
  let task: LorvexTask
  let isVisible: Bool
  @FocusState private var isButtonFocused: Bool

  private var isStarted: Bool { task.status == .inProgress }

  var body: some View {
    Button {
      Task {
        if isStarted {
          await store.pauseTaskFromRow(task)
        } else {
          await store.startTaskFromRow(task)
        }
      }
    } label: {
      Image(systemName: isStarted ? "pause.circle" : "play.circle")
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(
          width: WorkspaceRowDeferButtonMetrics.size,
          height: WorkspaceRowDeferButtonMetrics.size
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focused($isButtonFocused)
    .opacity((isVisible || isButtonFocused) ? 1 : 0)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityIdentifier("today.row.start.\(task.id)")
  }

  private var title: String {
    isStarted
      ? String(
        localized: "task.action.pause", defaultValue: "Pause", table: "Localizable",
        bundle: LorvexL10n.bundle)
      : String(
        localized: "task.action.start", defaultValue: "Start", table: "Localizable",
        bundle: LorvexL10n.bundle)
  }
}
