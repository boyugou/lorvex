import LorvexCore
import SwiftUI

/// Shared icon + color picker for the list and habit draft sheets. `icon` is an
/// SF Symbol name (rendered by ``LorvexListIconView``); `color` is a `#RRGGBB`
/// hex string. Both are optional — nil means "use the default" (the app accent /
/// the per-habit auto hue and the default glyph), exposed as a leading "Default"
/// swatch and icon so the user can clear a choice.
struct LorvexIconColorField: View {
  @Binding var icon: String?
  @Binding var color: String?
  let idPrefix: String

  /// Curated SF Symbols covering common planning / life-area metaphors, grouped
  /// loosely (general → time/comms → health/fitness → home/leisure → work/money).
  static let iconChoices: [String] = [
    "list.bullet", "checklist", "checkmark.seal", "star", "flag", "flag.checkered",
    "tag", "bolt", "heart", "leaf", "flame", "drop", "moon", "moon.stars", "sun.max",
    "sun.haze", "cloud", "snowflake", "sparkles", "lightbulb", "target", "trophy",
    "rosette", "pencil", "book", "books.vertical", "doc.text", "newspaper", "bookmark",
    "paperclip", "folder", "tray", "archivebox", "calendar", "calendar.badge.clock",
    "clock", "alarm", "hourglass", "timer", "stopwatch", "bell", "bell.badge",
    "envelope", "phone", "message", "bubble.left.and.bubble.right", "video", "person.2",
    "hand.raised", "figure.run", "figure.walk", "figure.hiking", "figure.cooldown",
    "bicycle", "dumbbell", "sportscourt", "bed.double", "pills", "cross.case", "cross",
    "stethoscope", "lungs", "brain.head.profile", "eye", "fork.knife", "cup.and.saucer",
    "wineglass", "carrot", "house", "cart", "bag", "shippingbox", "gift", "pawprint",
    "camera", "film", "gamecontroller", "headphones", "music.note", "guitars",
    "theatermasks", "puzzlepiece", "paintbrush", "hammer", "wrench.and.screwdriver",
    "gearshape", "key", "wifi", "briefcase", "laptopcomputer", "terminal", "globe",
    "map", "mountain.2", "umbrella", "thermometer", "airplane", "graduationcap",
    "dollarsign.circle", "creditcard", "banknote", "chart.bar", "chart.pie",
    "chart.line.uptrend.xyaxis",
  ]

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

  @State private var iconQuery = ""

  private var selectedTint: Color { Color(lorvexHex: color) ?? .accentColor }
  private var customColorBinding: Binding<Color> {
    Binding(
      get: { Color(lorvexHex: color) ?? .accentColor },
      set: { color = $0.lorvexHexString }
    )
  }

  /// Curated icons filtered by the search box (case-insensitive substring on the
  /// SF Symbol name). Empty query shows the whole set.
  private var filteredIcons: [String] {
    let query = iconQuery.trimmingCharacters(in: .whitespaces).lowercased()
    guard !query.isEmpty else { return Self.iconChoices }
    return Self.iconChoices.filter { $0.contains(query) }
  }

  /// The icons shown in the grid: the filtered set, with a current icon that is
  /// not in the curated list (e.g. one set via an MCP tool) surfaced first so the
  /// picker reflects and can keep it. Only when not actively searching.
  private var displayedIcons: [String] {
    var icons = filteredIcons
    if iconQuery.trimmingCharacters(in: .whitespaces).isEmpty,
      let icon, !icon.isEmpty, !icons.contains(icon)
    {
      icons.insert(icon, at: 0)
    }
    return icons
  }

  var body: some View {
    DraftSheetField(
      title: String(localized: "appearance.field.icon", defaultValue: "Appearance", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "paintpalette"
    ) {
      VStack(alignment: .leading, spacing: 8) {
        colorRow

        HStack(spacing: LorvexDesign.Spacing.xs) {
          Image(systemName: "magnifyingglass")
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
          TextField(
            String(localized: "appearance.icon.search", defaultValue: "Search icons", table: "Localizable", bundle: LorvexL10n.bundle),
            text: $iconQuery
          )
          .textFieldStyle(.plain)
          .font(LorvexDesign.Typography.primaryText)
          .accessibilityIdentifier("\(idPrefix).icon.search")
        }
        .padding(.horizontal, LorvexDesign.Spacing.s)
        .padding(.vertical, LorvexDesign.Spacing.xs)
        .background(
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
            .fill(Color.secondary.opacity(0.10))
        )

        // Two visible rows keep the sheet compact while search still exposes the
        // full curated icon set.
        ScrollView {
          LazyVGrid(columns: columns, spacing: 8) {
            iconButton(name: nil)
            ForEach(displayedIcons, id: \.self) { name in
              iconButton(name: name)
            }
          }
          .padding(.vertical, 2)
        }
        .frame(height: 76)
        .scrollIndicators(.automatic)
      }
    }
  }

  private var colorRow: some View {
    HStack(spacing: 8) {
      colorSwatch(hex: nil)
      ForEach(LorvexColorField.colorChoices, id: \.self) { hex in
        colorSwatch(hex: hex)
      }
      ColorPicker(selection: customColorBinding, supportsOpacity: false) {
        EmptyView()
      }
      .labelsHidden()
      .controlSize(.small)
      .help(String(localized: "appearance.color.custom", defaultValue: "Custom color", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "appearance.color.custom", defaultValue: "Custom color", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("\(idPrefix).color.custom")
      Spacer(minLength: 0)
    }
  }

  private func colorSwatch(hex: String?) -> some View {
    let isSelected = color == hex
    let fill = Color(lorvexHex: hex) ?? .secondary
    let label = hex ?? String(localized: "appearance.color.default", defaultValue: "Default color", table: "Localizable", bundle: LorvexL10n.bundle)
    return Button {
      color = hex
    } label: {
      ZStack {
        Circle()
          .fill(hex == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(fill))
          .frame(width: 20, height: 20)
        if hex == nil {
          Image(systemName: "slash.circle")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        Circle()
          .strokeBorder(isSelected ? Color.primary.opacity(0.7) : .clear, lineWidth: 2)
          .frame(width: 24, height: 24)
      }
      .frame(width: 24, height: 24)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("\(idPrefix).color.\(hex ?? "default")")
  }

  private func iconButton(name: String?) -> some View {
    let isSelected = icon == name
    return Button {
      icon = name
    } label: {
      Image(systemName: name ?? "slash.circle")
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(name == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(selectedTint))
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
            .fill(isSelected ? selectedTint.opacity(0.18) : Color.secondary.opacity(0.10))
        )
        .overlay(
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
            .strokeBorder(isSelected ? selectedTint : .clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous))
    }
    .buttonStyle(.plain)
    .help(name ?? String(localized: "appearance.icon.default", defaultValue: "Default icon", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityLabel(name ?? String(localized: "appearance.icon.default", defaultValue: "Default icon", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("\(idPrefix).icon.\(name ?? "default")")
  }
}
