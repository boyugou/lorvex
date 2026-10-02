import LorvexCore
import SwiftUI

/// The title of an inspector field's popover editor and, when the field is
/// easy to confuse with another (Do on and Due), a one-line hint saying what
/// it means. The task and habit inspectors' editors share it.
struct InspectorEditorHeader: View {
  let title: String
  let hint: String?

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Text(title).font(LorvexDesign.Typography.primaryEmphasis)
      if let hint {
        Text(hint)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// A one-click choice inside an inspector field's popover editor, in the
/// task and habit inspectors alike. The chosen one is tinted, not filled: the
/// only solid control in the app is the new-task button.
struct InspectorEditorPill: View {
  let label: String
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(LorvexDesign.Typography.secondaryText)
        .fixedSize()
        .foregroundStyle(isOn ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.primary))
        .padding(.horizontal, LorvexDesign.Spacing.s + 2)
        .padding(.vertical, LorvexDesign.Spacing.xs + 1)
        .background(
          Capsule().fill(isOn ? LorvexDesign.Palette.selectionFill : LorvexDesign.Palette.insetFill))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}
