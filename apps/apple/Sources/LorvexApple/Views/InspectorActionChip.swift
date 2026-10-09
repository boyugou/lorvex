import LorvexCore
import SwiftUI

/// The face of an action in an inspector's header row: a symbol and an optional
/// short title in the primary color on a quiet fill. The task inspector's Start,
/// Defer, and overflow controls and the habit inspector's overflow control all
/// wear it, so both inspectors' action rows read as one set of controls.
///
/// Without a title the chip is its symbol alone, such as the overflow's three
/// dots. The symbol is then the control's only content, so the control carries
/// its own accessibility label. Beside a title the symbol is decoration and is
/// hidden from VoiceOver, so a menu does not expose it as a stop of its own.
///
/// `isActive` draws the state a toggle shows while it is on: accent content on
/// an accent tint with a hairline edge.
///
/// The chip fills the height its row offers, so every control in a row is as
/// tall as the row's tallest one. The row sizes itself to its content with
/// `.fixedSize(horizontal: false, vertical: true)`; without that, the chip would
/// take all the height its container proposes. A menu wears the chip through
/// `.menuStyle(.button)`, `.buttonStyle(.plain)`, and `.menuIndicator(.hidden)`:
/// a bordered or borderless menu would redraw the label in its own colors and
/// drop the fill.
struct InspectorActionChip: View {
  /// The SF Symbol name.
  let systemImage: String
  /// The short title beside the symbol, or `nil` for the symbol alone.
  let title: String?
  /// Whether the chip draws the on state of a toggle.
  var isActive = false

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .accessibilityHidden(title != nil)
      if let title {
        Text(title)
          .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
          .fixedSize()
      }
    }
    .foregroundStyle(isActive ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.primary))
    .padding(.horizontal, 10)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .frame(maxHeight: .infinity)
    .background {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .fill(
          isActive
            ? AnyShapeStyle(LorvexDesign.Palette.accent.opacity(0.14))
            : AnyShapeStyle(.quaternary.opacity(0.5)))
    }
    .overlay {
      if isActive {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
          .stroke(LorvexDesign.Palette.accent.opacity(0.35), lineWidth: 0.5)
      }
    }
    .contentShape(Rectangle())
  }
}
