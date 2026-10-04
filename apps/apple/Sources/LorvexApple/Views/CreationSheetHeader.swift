import LorvexCore
import SwiftUI

private enum CreationSheetHeaderMetrics {
  static let tileSize: CGFloat = 52
  static let tileCornerRadius: CGFloat = 14
}

/// The top of a create or edit sheet: the thing being made, as it will look.
///
/// A large icon tile in the chosen color leads, marked with a small pencil
/// badge; clicking it opens the color and icon choices in a popover, so appearance never takes a form row of its own.
/// Beside it the name is typed straight into a large borderless field, with an
/// optional second line (`subtitle`) for a short secondary field such as a
/// habit's encouragement. The name field takes focus when the sheet opens.
///
/// `icon` and `color` are the draft's optional SF Symbol name and `#RRGGBB`
/// hex; nil draws `defaultIcon` in `defaultTint`. Identifiers: the tile is
/// `<idPrefix>.appearance`, the name field `<idPrefix>.name`, and the
/// popover's controls follow ``LorvexAppearancePicker``.
struct CreationSheetHeader<Subtitle: View>: View {
  @Binding var icon: String?
  @Binding var color: String?
  @Binding var name: String
  let defaultIcon: String
  var defaultTint: Color = .accentColor
  let namePrompt: String
  let nameAccessibilityLabel: String
  let idPrefix: String
  @ViewBuilder var subtitle: () -> Subtitle

  @State private var isChoosingAppearance = false
  @FocusState private var nameFocused: Bool

  private var tint: Color { Color(lorvexHex: color) ?? defaultTint }

  var body: some View {
    HStack(alignment: .center, spacing: LorvexDesign.Spacing.m) {
      Button {
        isChoosingAppearance = true
      } label: {
        Image(systemName: LorvexSymbol.name(for: icon, fallback: defaultIcon))
          .font(LorvexDesign.Typography.screenTitle)
          .foregroundStyle(tint)
          .frame(width: CreationSheetHeaderMetrics.tileSize, height: CreationSheetHeaderMetrics.tileSize)
          .background(
            tint.opacity(0.14),
            in: RoundedRectangle(cornerRadius: CreationSheetHeaderMetrics.tileCornerRadius, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: CreationSheetHeaderMetrics.tileCornerRadius, style: .continuous))
          .overlay(alignment: .bottomTrailing) {
            // Says the tile is a control: it opens the icon and color choices.
            Image(systemName: "pencil.circle.fill")
              .font(LorvexDesign.Typography.secondaryText)
              .symbolRenderingMode(.palette)
              .foregroundStyle(.white, tint)
              .padding(.trailing, -LorvexDesign.Spacing.xs)
              .padding(.bottom, -LorvexDesign.Spacing.xs)
              .accessibilityHidden(true)
          }
      }
      .buttonStyle(.plain)
      .help(appearanceLabel)
      .accessibilityLabel(appearanceLabel)
      .accessibilityIdentifier("\(idPrefix).appearance")
      .popover(isPresented: $isChoosingAppearance, arrowEdge: .bottom) {
        LorvexAppearancePicker(icon: $icon, color: $color, idPrefix: idPrefix)
          .padding(LorvexDesign.Spacing.m)
          .frame(width: LorvexAppearancePicker.popoverWidth)
      }

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        TextField(namePrompt, text: $name)
          .font(LorvexDesign.Typography.sectionHeader)
          .textFieldStyle(.plain)
          .focused($nameFocused)
          .accessibilityLabel(nameAccessibilityLabel)
          .accessibilityIdentifier("\(idPrefix).name")
        subtitle()
      }
    }
    .task {
      await Task.yield()
      nameFocused = true
    }
  }

  private var appearanceLabel: String {
    String(
      localized: "appearance.choose", defaultValue: "Choose Icon and Color", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
}

extension CreationSheetHeader where Subtitle == EmptyView {
  init(
    icon: Binding<String?>, color: Binding<String?>, name: Binding<String>, defaultIcon: String,
    defaultTint: Color = .accentColor, namePrompt: String, nameAccessibilityLabel: String,
    idPrefix: String
  ) {
    self.init(
      icon: icon, color: color, name: name, defaultIcon: defaultIcon, defaultTint: defaultTint,
      namePrompt: namePrompt, nameAccessibilityLabel: nameAccessibilityLabel, idPrefix: idPrefix
    ) { EmptyView() }
  }
}
