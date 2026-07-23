import LorvexCore
import SwiftUI

/// Shared color-only picker for draft sheets whose entity has a color but no
/// icon (calendar events). `color` is a `#RRGGBB` hex string; nil means "use
/// the default" (the app accent), exposed as a leading "Default" swatch so the
/// user can clear a choice. Extracted from ``LorvexIconColorField``, which
/// composes this view for its color half — list/habit drafts also carry an
/// icon and use that combined component instead.
struct LorvexColorField: View {
  @Binding var color: String?
  let idPrefix: String

  /// Preset accent colors as `#RRGGBB`, matching the habit auto palette family.
  static let colorChoices: [String] = [
    "#3B82F6", "#14B8A6", "#22C55E", "#F59E0B",
    "#EF4444", "#EC4899", "#8B5CF6", "#6366F1",
  ]

  /// Two-way bridge between the stored `#RRGGBB` string and a `ColorPicker`, so a
  /// custom color outside the eight presets can be chosen (and round-trips back
  /// to a hex string the core persists).
  private var customColorBinding: Binding<Color> {
    Binding(
      get: { Color(lorvexHex: color) ?? .accentColor },
      set: { color = $0.lorvexHexString }
    )
  }

  var body: some View {
    DraftSheetField(
      title: String(localized: "appearance.field.color", defaultValue: "Color", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "paintpalette"
    ) {
      HStack(spacing: 8) {
        swatch(hex: nil)
        ForEach(Self.colorChoices, id: \.self) { hex in
          swatch(hex: hex)
        }
        ColorPicker(
          selection: customColorBinding, supportsOpacity: false
        ) {
          EmptyView()
        }
        .labelsHidden()
        .help(String(localized: "appearance.color.custom", defaultValue: "Custom color", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityLabel(String(localized: "appearance.color.custom", defaultValue: "Custom color", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("\(idPrefix).color.custom")
        Spacer(minLength: 0)
      }
    }
  }

  private func swatch(hex: String?) -> some View {
    let isSelected = color == hex
    let fill = Color(lorvexHex: hex) ?? .secondary
    let label = hex ?? String(localized: "appearance.color.default", defaultValue: "Default color", table: "Localizable", bundle: LorvexL10n.bundle)
    return Button {
      color = hex
    } label: {
      ZStack {
        Circle()
          .fill(hex == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(fill))
          .frame(width: 22, height: 22)
        if hex == nil {
          Image(systemName: "slash.circle")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        Circle()
          .strokeBorder(isSelected ? Color.primary.opacity(0.7) : .clear, lineWidth: 2)
          .frame(width: 26, height: 26)
      }
      .frame(width: 26, height: 26)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("\(idPrefix).color.\(hex ?? "default")")
  }
}
