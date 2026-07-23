import LorvexCore
import SwiftUI

private enum WorkspaceRowDeferButtonMetrics {
  static let size: CGFloat = 17
  static let visibleOpacity: Double = 0.55
}

/// A hover-revealed defer control for Today rows — a quick way to push a task to
/// tomorrow / in a few days / next week without opening it. Mirrors
/// `WorkspaceBatchSelectionButton`'s reveal-on-hover treatment so the trailing
/// affordances read as a set.
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
        .foregroundStyle(.tertiary)
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
    .opacity((isVisible || isButtonFocused) ? WorkspaceRowDeferButtonMetrics.visibleOpacity : 0)
    .help(String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityLabel(String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("today.row.defer.\(task.id)")
  }
}
