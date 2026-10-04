import LorvexCore
import SwiftUI

/// The top of a list or habit sheet: the thing being made, as it will look.
///
/// An icon tile in the chosen color leads, marked with a small pencil badge;
/// tapping it opens the color and icon choices in a popover
/// (``MobileIconColorPicker``), so appearance never takes rows of its own in the
/// form. Beside the tile the name is typed straight into a large borderless
/// field (`name`; a vertical-axis field there wraps a long name instead of
/// truncating it), with a second line (`subtitle`) for a short secondary field
/// such as a list's description or a habit's encouragement. At accessibility
/// text sizes the tile sits above the text instead of beside it.
///
/// `icon` and `color` are the draft's optional SF Symbol name and `#RRGGBB`
/// hex; nil draws `fallbackIcon` in the default accent. The header is a form
/// row of its own with no card behind it, so it belongs in a `Form` section by
/// itself. The tile's identifier is `<idPrefix>.appearance`. `willChooseAppearance`
/// runs as the tile is tapped, before the popover opens: a sheet resigns its
/// text focus there, so the keyboard does not cover the choices.
struct MobileCreationHeader<Name: View, Subtitle: View>: View {
  @Binding var icon: String?
  @Binding var color: String?
  let fallbackIcon: String
  let iconChoices: [String]
  let idPrefix: String
  var willChooseAppearance: () -> Void = {}
  @ViewBuilder var name: () -> Name
  @ViewBuilder var subtitle: () -> Subtitle

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isChoosingAppearance = false

  /// The tile's side. Larger than ``MobileIconTile/largestScaledSize``, so the
  /// tile keeps this size at every text size.
  private static var tileSize: CGFloat { 56 }

  private var tint: Color { Color(lorvexHex: color) ?? LorvexDesign.Palette.accent }

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: LorvexDesign.Spacing.m))
      : AnyLayout(HStackLayout(alignment: .center, spacing: LorvexDesign.Spacing.m))
    layout {
      tileButton
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        name()
          .font(LorvexDesign.Typography.detailTitle)
        subtitle()
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
      }
      .textFieldStyle(.plain)
    }
    #if DEBUG
      .task {
        // Dev/QA only: `lorvex://sheet/<newlist|editlist|newhabit>/appearance`
        // opens the popover once the sheet has settled, the way a tap on the
        // tile does (text focus resigned first), so it can be captured.
        guard MobileSheetDebugState.takeOpensAppearance() else { return }
        try? await Task.sleep(for: .milliseconds(700))
        willChooseAppearance()
        isChoosingAppearance = true
      }
    #endif
    .listRowBackground(Color.clear)
    .listRowInsets(
      EdgeInsets(
        top: LorvexDesign.Spacing.s, leading: LorvexDesign.Spacing.m + LorvexDesign.Spacing.xxs,
        bottom: LorvexDesign.Spacing.s, trailing: LorvexDesign.Spacing.m + LorvexDesign.Spacing.xxs))
  }

  private var tileButton: some View {
    Button {
      willChooseAppearance()
      isChoosingAppearance = true
    } label: {
      MobileIconTile(icon: icon, fallback: fallbackIcon, tint: tint, size: Self.tileSize)
        .reduceMotionAnimation(.snappy, value: icon)
        .reduceMotionAnimation(.snappy, value: color)
        .overlay(alignment: .bottomTrailing) { pencilBadge }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      String(
        localized: "appearance.choose", defaultValue: "Choose Icon and Color", table: "Localizable",
        bundle: MobileL10n.bundle)
    )
    .accessibilityIdentifier("\(idPrefix).appearance")
    .popover(isPresented: $isChoosingAppearance) {
      MobileIconColorPicker(
        icon: $icon, color: $color, fallbackIcon: fallbackIcon, iconChoices: iconChoices
      )
      .presentationCompactAdaptation(.popover)
    }
  }

  /// Says the tile is a control: it opens the icon and color choices. Pushed
  /// out past the tile's corner by padding, which follows the layout direction.
  /// It stops growing at the default text size, because the tile it marks does
  /// not grow: a larger badge would cover the tile's glyph.
  private var pencilBadge: some View {
    Image(systemName: "pencil.circle.fill")
      .font(LorvexDesign.Typography.secondaryText)
      .dynamicTypeSize(...DynamicTypeSize.large)
      .symbolRenderingMode(.palette)
      .foregroundStyle(.white, tint)
      .padding(.trailing, -LorvexDesign.Spacing.xs)
      .padding(.bottom, -LorvexDesign.Spacing.xs)
      .accessibilityHidden(true)
  }
}
