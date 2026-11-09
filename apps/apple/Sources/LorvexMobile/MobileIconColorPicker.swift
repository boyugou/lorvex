import LorvexCore
import SwiftUI

/// The icons a list or habit sheet puts first in the shared icon grid
/// (``LorvexIconCatalog``), and the glyph each grid icon is drawn and stored as.
enum MobileIconChoices {
  /// Outline names of the icons that suit a list, first in a list sheet's grid.
  static let list: [String] = [
    "tray", "folder", "briefcase", "house", "cart", "book", "graduationcap", "heart", "star",
    "flag", "bolt", "leaf", "airplane", "fork.knife", "gamecontroller", "paintbrush",
    "music.note", "dollarsign.circle",
  ]
  /// Outline names of the icons that suit a habit, first in a habit sheet's grid.
  static let habit: [String] = [
    "repeat", "book", "figure.run", "drop", "bed.double", "dumbbell", "brain.head.profile",
    "fork.knife", "cup.and.saucer", "leaf", "heart", "moon", "sun.max", "pencil", "music.note",
    "camera", "pills", "figure.mind.and.body",
  ]

  /// The glyph the grid draws for each curated icon, which is also the name a
  /// tap stores: the filled variant where this system has one, as iOS draws
  /// its icons, otherwise the outline. The Mac picker treats a filled variant
  /// as its outline's tile, so a choice made here is found there.
  private static let drawn: [String: String] = Dictionary(
    LorvexIconCatalog.choices.map { ($0, LorvexSymbol.name(for: "\($0).fill", fallback: $0)) },
    uniquingKeysWith: { first, _ in first })

  /// The glyph to draw and store for `icon`: a curated outline name becomes
  /// its filled variant where one exists; any other name is kept as it is.
  static func symbol(for icon: String) -> String { drawn[icon] ?? icon }
}

/// The color swatches and SF Symbol grid offered when picking a list or habit's
/// appearance, sized for the popover ``MobileCreationHeader`` opens from its
/// tile. Sets the color and icon the catalog rows render. With no explicit
/// choice a list or habit draws the default accent and its fallback glyph, and
/// the picker shows those two as selected. The grid offers the shared icon set
/// the Mac picker offers (``LorvexIconCatalog``), `leadingIcons` first, under a
/// search field that matches each icon's name and keywords in the user's
/// language; it scrolls, and opens scrolled to the icon that is selected.
struct MobileIconColorPicker: View {
  @Binding var icon: String?
  @Binding var color: String?
  let fallbackIcon: String
  let leadingIcons: [String]

  @State private var iconQuery = ""

  /// The popover's width: six 42-point icon buttons, five 8-point gaps, and
  /// the 14-point content padding on both sides.
  static let width: CGFloat = 320

  /// A friendly, well-separated hue ramp (system colors as Lorvex hex).
  static let colorChoices: [String] = [
    "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#30B0C7",
    "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#8E8E93",
  ]

  /// The swatch that stands for the default accent tint, shown as selected
  /// while a draft has no color.
  static let defaultColor = "#007AFF"

  private var tint: Color { Color(lorvexHex: color) ?? LorvexDesign.Palette.accent }

  /// The hex of the swatch that is selected: the draft's color, or the default.
  private var selectedColor: String { (color ?? Self.defaultColor).uppercased() }

  /// The symbol the tile draws, which is the icon button that is selected: an
  /// emoji or unknown icon resolves to the fallback glyph, as it does there.
  private var selectedSymbol: String { LorvexSymbol.name(for: icon, fallback: fallbackIcon) }

  /// The height of the scrolling icon grid: four rows of buttons and the top
  /// half of a fifth, so the cut row shows that the grid scrolls.
  static let iconGridHeight: CGFloat = 4 * (42 + LorvexDesign.Spacing.s) + 21

  private var isSearching: Bool { !iconQuery.trimmingCharacters(in: .whitespaces).isEmpty }

  /// The icons in the grid: the curated set filtered by the search, with a
  /// current icon from outside it (one an assistant set over MCP) first while
  /// not searching, so the grid shows the selection and can keep it.
  private var displayedIcons: [String] {
    var icons = LorvexIconCatalog.choices(matching: iconQuery, leading: leadingIcons)
    let selectedOutline = LorvexIconCatalog.outlineName(of: selectedSymbol)
    if !isSearching, !icons.contains(selectedOutline) {
      icons.insert(selectedSymbol, at: 0)
    }
    return icons
  }

  /// The entry of `icons` that is selected, the one the grid opens scrolled to.
  private func selectedEntry(in icons: [String]) -> String? {
    let selectedOutline = LorvexIconCatalog.outlineName(of: selectedSymbol)
    return icons.first { LorvexIconCatalog.outlineName(of: $0) == selectedOutline }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        pickerHeader(String(localized: "appearance.color", defaultValue: "Color", table: "Localizable", bundle: MobileL10n.bundle))
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: LorvexDesign.Spacing.s), count: 5),
          spacing: 0
        ) {
          ForEach(Self.colorChoices, id: \.self) { swatch($0) }
        }
      }

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        pickerHeader(String(localized: "appearance.icon", defaultValue: "Icon", table: "Localizable", bundle: MobileL10n.bundle))
        searchField
        iconGrid
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: Self.width)
    // The grids' cells have a fixed size, so the picker's headings and glyphs
    // stop growing at the largest ordinary text size.
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  private func pickerHeader(_ text: String) -> some View {
    Text(text)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.secondary)
  }

  /// One color swatch: a 30-point circle inside a button that is a column wide
  /// and 44 points high, the smallest comfortable touch target, so the grid
  /// itself carries no row gap.
  private func swatch(_ hex: String) -> some View {
    let isSelected = selectedColor == hex
    return Button {
      lorvexAnimated(.snappy) { color = hex }
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
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Each swatch announces its own color name so VoiceOver users can tell them
    // apart — a grid of buttons all labeled "Color" is unusable non-visually.
    .accessibilityLabel(Self.colorName(hex))
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  /// Filters the grid by an icon's name or keywords in the user's language, or
  /// its SF Symbol name. Return chooses the first icon found.
  private var searchField: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField(
        String(localized: "appearance.icon.search", defaultValue: "Search icons", table: "Localizable", bundle: MobileL10n.bundle),
        text: $iconQuery
      )
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.never)
      #endif
      .submitLabel(.done)
      .onSubmit(chooseFirstMatch)
      .accessibilityIdentifier("appearance.icon.search")
      if !iconQuery.isEmpty {
        Button {
          iconQuery = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.tertiary)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "common.clear", defaultValue: "Clear", table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
    .font(LorvexDesign.Typography.primaryText)
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .frame(minHeight: 36)
    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  /// The scrolling grid of icons, or a line saying the search found none. It
  /// keeps one height whatever it holds, so the popover does not resize as a
  /// search narrows it.
  private var iconGrid: some View {
    let icons = displayedIcons
    return ScrollViewReader { proxy in
      ScrollView {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: LorvexDesign.Spacing.s), count: 6),
          spacing: LorvexDesign.Spacing.s
        ) {
          ForEach(icons, id: \.self) { iconButton($0) }
        }
      }
      .scrollDismissesKeyboard(.immediately)
      .overlay {
        if icons.isEmpty {
          Text(
            String(
              format: String(
                localized: "search.empty.title", defaultValue: "No Results for “%@”",
                table: "Localizable", bundle: MobileL10n.bundle),
              iconQuery.trimmingCharacters(in: .whitespaces))
          )
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        }
      }
      .onAppear {
        if let entry = selectedEntry(in: icons) { proxy.scrollTo(entry, anchor: .center) }
      }
    }
    .frame(height: Self.iconGridHeight)
  }

  /// Return in the search field chooses the first icon the search found, so a
  /// typed name picks without a tap; an empty search leaves the choice alone.
  private func chooseFirstMatch() {
    guard isSearching, let first = displayedIcons.first else { return }
    lorvexAnimated(.snappy) { icon = MobileIconChoices.symbol(for: first) }
  }

  private func iconButton(_ entry: String) -> some View {
    let symbol = MobileIconChoices.symbol(for: entry)
    let isSelected =
      LorvexIconCatalog.outlineName(of: selectedSymbol) == LorvexIconCatalog.outlineName(of: entry)
    return Button {
      lorvexAnimated(.snappy) { icon = symbol }
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
    .accessibilityLabel(
      LorvexIconCatalog.name(for: symbol)
        ?? String(localized: "appearance.icon", defaultValue: "Icon", table: "Localizable", bundle: MobileL10n.bundle))
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
}
