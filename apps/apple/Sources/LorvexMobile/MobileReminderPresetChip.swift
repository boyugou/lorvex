import LorvexCore
import SwiftUI

/// A single tappable preset chip for the reminder composer. Renders a static
/// label, reflects selection with a tinted/filled capsule, and reports taps.
/// Selection is driven by an explicit identity (the caller's chosen preset),
/// not by date equality — now-relative presets recompute their target on each
/// render, so equality comparison would spuriously deselect them.
struct MobileReminderPresetChip: View {
  let title: String
  let systemImage: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
          in: Capsule()
        )
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}
