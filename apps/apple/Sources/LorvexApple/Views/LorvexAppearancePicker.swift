import LorvexCore
import SwiftUI

/// The color and icon choices for a list or habit, shown in the popover a
/// creation sheet's icon tile opens (``CreationSheetHeader``). `icon` is an SF
/// Symbol name; `color` is a `#RRGGBB` hex string. Both are optional — nil
/// means "use the default" (the app accent or the per-habit auto hue, and the
/// default glyph), offered as a leading Default swatch and icon so a choice
/// can be cleared. A row of swatches ends with the system color well for any
/// other color; below it a search field filters the shared icon grid
/// (``LorvexIconCatalog``), the same set the iPhone and iPad picker offers.
struct LorvexAppearancePicker: View {
  @Binding var icon: String?
  @Binding var color: String?
  let idPrefix: String

  /// The width of the popover the picker fills, padded by `Spacing.m`.
  static let popoverWidth: CGFloat = 340

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

  @State private var iconQuery = ""

  private var selectedTint: Color { Color(lorvexHex: color) ?? .accentColor }
  private var customColorBinding: Binding<Color> {
    Binding(
      get: { Color(lorvexHex: color) ?? .accentColor },
      set: { color = $0.lorvexHexString }
    )
  }

  /// The shared icon set (``LorvexIconCatalog``) filtered by the search field.
  private var filteredIcons: [String] { LorvexIconCatalog.choices(matching: iconQuery) }

  /// Return in the search field chooses the first icon the search found, so a
  /// typed name picks without a click; the grid then shows it selected. An
  /// empty search leaves the choice alone.
  private func chooseFirstMatch() {
    guard !iconQuery.trimmingCharacters(in: .whitespaces).isEmpty,
      let first = filteredIcons.first
    else { return }
    icon = first
  }

  /// The icons shown in the grid: the filtered set, with a current icon that is
  /// not in the curated list (e.g. one set via an MCP tool) surfaced first so the
  /// picker reflects and can keep it. Only when not actively searching. A filled
  /// variant chosen on an iPhone (`star.fill`) is its outline's tile, not another.
  private var displayedIcons: [String] {
    var icons = filteredIcons
    if iconQuery.trimmingCharacters(in: .whitespaces).isEmpty,
      let icon, !icon.isEmpty, !icons.contains(LorvexIconCatalog.outlineName(of: icon))
    {
      icons.insert(icon, at: 0)
    }
    return icons
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
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
        .onSubmit(chooseFirstMatch)
        .accessibilityIdentifier("\(idPrefix).icon.search")
      }
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .background(
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
          .fill(Color.secondary.opacity(0.10))
      )

      ScrollView {
        LazyVGrid(columns: columns, spacing: 8) {
          iconButton(name: nil)
          ForEach(displayedIcons, id: \.self) { name in
            iconButton(name: name)
          }
        }
        .padding(.vertical, LorvexDesign.Spacing.xxs)
      }
      .frame(height: 216)
    }
  }

  /// The Default swatch, the preset swatches, and the color well, spread
  /// across the popover's width with equal gaps, so the row spans the same
  /// edges as the search field and the icon grid under it. The well is the
  /// bare control at its own size; its name is its help tag and VoiceOver
  /// label.
  private var colorRow: some View {
    HStack(spacing: 0) {
      colorSwatch(hex: nil)
      ForEach(LorvexColorField.colorChoices, id: \.self) { hex in
        Spacer(minLength: LorvexDesign.Spacing.xs)
        colorSwatch(hex: hex)
      }
      Spacer(minLength: LorvexDesign.Spacing.xs)
      ColorPicker(
        String(localized: "appearance.color.custom", defaultValue: "Custom color", table: "Localizable", bundle: LorvexL10n.bundle),
        selection: customColorBinding,
        supportsOpacity: false
      )
      .labelsHidden()
      .controlSize(.small)
      .fixedSize()
      .help(String(localized: "appearance.color.custom", defaultValue: "Custom color", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("\(idPrefix).color.custom")
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
            .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
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
    let isSelected = icon.map(LorvexIconCatalog.outlineName(of:)) == name.map(LorvexIconCatalog.outlineName(of:))
    let label =
      name.map { LorvexIconCatalog.name(for: $0) ?? $0 }
      ?? String(localized: "appearance.icon.default", defaultValue: "Default icon", table: "Localizable", bundle: LorvexL10n.bundle)
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
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("\(idPrefix).icon.\(name ?? "default")")
  }
}
