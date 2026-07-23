import LorvexCore
import SwiftUI

/// SF Symbol sets offered when picking a list / habit icon.
enum MobileIconChoices {
  static let list: [String] = [
    "tray.fill", "folder.fill", "briefcase.fill", "house.fill", "cart.fill",
    "book.fill", "graduationcap.fill", "heart.fill", "star.fill", "flag.fill",
    "bolt.fill", "leaf.fill", "airplane", "fork.knife", "gamecontroller.fill",
    "paintbrush.fill", "music.note", "dollarsign.circle.fill",
  ]
  static let habit: [String] = [
    "repeat", "book.fill", "figure.run", "drop.fill", "bed.double.fill",
    "dumbbell.fill", "brain.head.profile", "fork.knife", "cup.and.saucer.fill",
    "leaf.fill", "heart.fill", "moon.fill", "sun.max.fill", "pencil",
    "music.note", "camera.fill", "pills.fill", "figure.mind.and.body",
  ]
}

/// A live identity editor — a large tile preview over a color swatch row + an
/// SF-Symbol grid — for the list / habit create + edit sheets. Sets the color
/// and icon the catalog rows render; without an explicit choice a list/habit
/// falls back to the default accent + fallback glyph.
struct MobileIconColorPicker: View {
  @Binding var icon: String?
  @Binding var color: String?
  let fallbackIcon: String
  let iconChoices: [String]

  /// A friendly, well-separated hue ramp (system colors as Lorvex hex).
  static let colorChoices: [String] = [
    "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#30B0C7",
    "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#8E8E93",
  ]

  private var tint: Color { Color(lorvexHex: color) ?? LorvexDesign.Palette.accent }

  var body: some View {
    VStack(spacing: LorvexDesign.Spacing.l) {
      MobileIconTile(icon: icon, fallback: fallbackIcon, tint: tint, size: 72)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: icon)
        .animation(.snappy, value: color)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        pickerHeader(String(localized: "appearance.color", defaultValue: "Color", table: "Localizable", bundle: MobileL10n.bundle))
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: LorvexDesign.Spacing.s), count: 5),
          spacing: LorvexDesign.Spacing.m
        ) {
          ForEach(Self.colorChoices, id: \.self) { swatch($0) }
        }
      }

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        pickerHeader(String(localized: "appearance.icon", defaultValue: "Icon", table: "Localizable", bundle: MobileL10n.bundle))
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: LorvexDesign.Spacing.s), count: 6),
          spacing: LorvexDesign.Spacing.s
        ) {
          ForEach(iconChoices, id: \.self) { iconButton($0) }
        }
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
  }

  private func pickerHeader(_ text: String) -> some View {
    Text(text)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
  }

  private func swatch(_ hex: String) -> some View {
    let isSelected = color == hex
    return Button {
      withAnimation(.snappy) { color = hex }
    } label: {
      Circle()
        .fill(Color(lorvexHex: hex) ?? .accentColor)
        .frame(width: 30, height: 30)
        .overlay {
          Image(systemName: "checkmark")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .opacity(isSelected ? 1 : 0)
        }
        .overlay {
          Circle()
            .strokeBorder(Color.primary.opacity(isSelected ? 0.3 : 0), lineWidth: 2)
            .padding(-3)
        }
        .scaleEffect(isSelected ? 1.12 : 1)
    }
    .buttonStyle(.plain)
    // Each swatch announces its own color name so VoiceOver users can tell them
    // apart — a grid of buttons all labeled "Color" is unusable non-visually.
    .accessibilityLabel(Self.colorName(hex))
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private func iconButton(_ symbol: String) -> some View {
    let isSelected = icon == symbol
    return Button {
      withAnimation(.snappy) { icon = symbol }
    } label: {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .frame(width: 42, height: 42)
        .background(
          isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.secondary.opacity(0.12)),
          in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
    .buttonStyle(.plain)
    // Icon-only buttons otherwise read the raw SF Symbol name ("figure.run");
    // give each a human, localized label.
    .accessibilityLabel(Self.iconName(symbol))
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  /// A localized human name for a color swatch's Lorvex hex, for VoiceOver.
  static func colorName(_ hex: String) -> String {
    switch hex.uppercased() {
    case "#FF3B30": return String(localized: "appearance.color.red", defaultValue: "Red", table: "Localizable", bundle: MobileL10n.bundle)
    case "#FF9500": return String(localized: "appearance.color.orange", defaultValue: "Orange", table: "Localizable", bundle: MobileL10n.bundle)
    case "#FFCC00": return String(localized: "appearance.color.yellow", defaultValue: "Yellow", table: "Localizable", bundle: MobileL10n.bundle)
    case "#34C759": return String(localized: "appearance.color.green", defaultValue: "Green", table: "Localizable", bundle: MobileL10n.bundle)
    case "#30B0C7": return String(localized: "appearance.color.teal", defaultValue: "Teal", table: "Localizable", bundle: MobileL10n.bundle)
    case "#007AFF": return String(localized: "appearance.color.blue", defaultValue: "Blue", table: "Localizable", bundle: MobileL10n.bundle)
    case "#5856D6": return String(localized: "appearance.color.indigo", defaultValue: "Indigo", table: "Localizable", bundle: MobileL10n.bundle)
    case "#AF52DE": return String(localized: "appearance.color.purple", defaultValue: "Purple", table: "Localizable", bundle: MobileL10n.bundle)
    case "#FF2D55": return String(localized: "appearance.color.pink", defaultValue: "Pink", table: "Localizable", bundle: MobileL10n.bundle)
    case "#8E8E93": return String(localized: "appearance.color.gray", defaultValue: "Gray", table: "Localizable", bundle: MobileL10n.bundle)
    default: return String(localized: "appearance.color", defaultValue: "Color", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  /// A localized human name for an SF Symbol offered in the icon grid, for
  /// VoiceOver. Falls back to a generic "Icon" for an unmapped symbol.
  static func iconName(_ symbol: String) -> String {
    switch symbol {
    case "tray.fill": return String(localized: "appearance.icon.inbox", defaultValue: "Inbox", table: "Localizable", bundle: MobileL10n.bundle)
    case "folder.fill": return String(localized: "appearance.icon.folder", defaultValue: "Folder", table: "Localizable", bundle: MobileL10n.bundle)
    case "briefcase.fill": return String(localized: "appearance.icon.briefcase", defaultValue: "Briefcase", table: "Localizable", bundle: MobileL10n.bundle)
    case "house.fill": return String(localized: "appearance.icon.home", defaultValue: "Home", table: "Localizable", bundle: MobileL10n.bundle)
    case "cart.fill": return String(localized: "appearance.icon.cart", defaultValue: "Cart", table: "Localizable", bundle: MobileL10n.bundle)
    case "book.fill": return String(localized: "appearance.icon.book", defaultValue: "Book", table: "Localizable", bundle: MobileL10n.bundle)
    case "graduationcap.fill":
      return String(localized: "appearance.icon.graduation", defaultValue: "Graduation", table: "Localizable", bundle: MobileL10n.bundle)
    case "heart.fill": return String(localized: "appearance.icon.heart", defaultValue: "Heart", table: "Localizable", bundle: MobileL10n.bundle)
    case "star.fill": return String(localized: "appearance.icon.star", defaultValue: "Star", table: "Localizable", bundle: MobileL10n.bundle)
    case "flag.fill": return String(localized: "appearance.icon.flag", defaultValue: "Flag", table: "Localizable", bundle: MobileL10n.bundle)
    case "bolt.fill": return String(localized: "appearance.icon.lightning", defaultValue: "Lightning", table: "Localizable", bundle: MobileL10n.bundle)
    case "leaf.fill": return String(localized: "appearance.icon.leaf", defaultValue: "Leaf", table: "Localizable", bundle: MobileL10n.bundle)
    case "airplane": return String(localized: "appearance.icon.airplane", defaultValue: "Airplane", table: "Localizable", bundle: MobileL10n.bundle)
    case "fork.knife": return String(localized: "appearance.icon.dining", defaultValue: "Dining", table: "Localizable", bundle: MobileL10n.bundle)
    case "gamecontroller.fill": return String(localized: "appearance.icon.games", defaultValue: "Games", table: "Localizable", bundle: MobileL10n.bundle)
    case "paintbrush.fill": return String(localized: "appearance.icon.paintbrush", defaultValue: "Paintbrush", table: "Localizable", bundle: MobileL10n.bundle)
    case "music.note": return String(localized: "appearance.icon.music", defaultValue: "Music", table: "Localizable", bundle: MobileL10n.bundle)
    case "dollarsign.circle.fill": return String(localized: "appearance.icon.money", defaultValue: "Money", table: "Localizable", bundle: MobileL10n.bundle)
    case "repeat": return String(localized: "appearance.icon.repeat", defaultValue: "Repeat", table: "Localizable", bundle: MobileL10n.bundle)
    case "figure.run": return String(localized: "appearance.icon.running", defaultValue: "Running", table: "Localizable", bundle: MobileL10n.bundle)
    case "drop.fill": return String(localized: "appearance.icon.water", defaultValue: "Water", table: "Localizable", bundle: MobileL10n.bundle)
    case "bed.double.fill": return String(localized: "appearance.icon.sleep", defaultValue: "Sleep", table: "Localizable", bundle: MobileL10n.bundle)
    case "dumbbell.fill": return String(localized: "appearance.icon.workout", defaultValue: "Workout", table: "Localizable", bundle: MobileL10n.bundle)
    case "brain.head.profile": return String(localized: "appearance.icon.mind", defaultValue: "Mind", table: "Localizable", bundle: MobileL10n.bundle)
    case "cup.and.saucer.fill": return String(localized: "appearance.icon.coffee", defaultValue: "Coffee", table: "Localizable", bundle: MobileL10n.bundle)
    case "moon.fill": return String(localized: "appearance.icon.moon", defaultValue: "Moon", table: "Localizable", bundle: MobileL10n.bundle)
    case "sun.max.fill": return String(localized: "appearance.icon.sun", defaultValue: "Sun", table: "Localizable", bundle: MobileL10n.bundle)
    case "pencil": return String(localized: "appearance.icon.pencil", defaultValue: "Pencil", table: "Localizable", bundle: MobileL10n.bundle)
    case "camera.fill": return String(localized: "appearance.icon.camera", defaultValue: "Camera", table: "Localizable", bundle: MobileL10n.bundle)
    case "pills.fill": return String(localized: "appearance.icon.medication", defaultValue: "Medication", table: "Localizable", bundle: MobileL10n.bundle)
    case "figure.mind.and.body":
      return String(localized: "appearance.icon.mindfulness", defaultValue: "Mindfulness", table: "Localizable", bundle: MobileL10n.bundle)
    default: return String(localized: "appearance.icon", defaultValue: "Icon", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}
