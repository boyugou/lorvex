import LorvexCore
import SwiftUI

private enum WorkspaceBatchSelectionButtonMetrics {
  static let size: CGFloat = 17
  static let selectedOpacity: Double = 0.82
  static let visibleOpacity: Double = 0.50
}

struct WorkspaceBatchSelectionButton: View {
  let isSelected: Bool
  let isVisible: Bool
  let accessibilityIdentifier: String
  let action: () -> Void
  /// Keyboard focus reveals the control even without a pointer hover, so
  /// Full Keyboard Access users can reach batch selection.
  @FocusState private var isButtonFocused: Bool

  private var accessibilityValue: String {
    if isSelected {
      return String(localized: "common.selected", defaultValue: "Selected", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return String(localized: "common.not_selected", defaultValue: "Not selected", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  var body: some View {
    Button(action: action) {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        .frame(
          width: WorkspaceBatchSelectionButtonMetrics.size,
          height: WorkspaceBatchSelectionButtonMetrics.size
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focused($isButtonFocused)
    .frame(
      width: WorkspaceBatchSelectionButtonMetrics.size,
      height: WorkspaceBatchSelectionButtonMetrics.size
    )
    .opacity(
      isSelected
        ? WorkspaceBatchSelectionButtonMetrics.selectedOpacity
        : ((isVisible || isButtonFocused) ? WorkspaceBatchSelectionButtonMetrics.visibleOpacity : 0)
    )
    .help(String(localized: "tasks.row.batch_select", defaultValue: "Select for batch actions", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityLabel(String(localized: "tasks.row.batch_select", defaultValue: "Select for batch actions", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityValue(accessibilityValue)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}
