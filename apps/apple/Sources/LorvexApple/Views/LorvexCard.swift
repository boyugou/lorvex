import LorvexCore
import SwiftUI

extension View {
  /// Wrap the view in the app's one elevated card chrome, built from the shared
  /// card design tokens: inset the content by `padding`
  /// (`LorvexDesign.Spacing.cardPadding` by default), fill with the opaque
  /// elevated `LorvexDesign.Palette.card` surface at `LorvexDesign.Radius.card`
  /// continuous corners, draw a hairline `LorvexDesign.Palette.separator`
  /// border, and apply the `LorvexDesign.Elevation.cardShadow*` drop shadow.
  ///
  /// Use this instead of hand-rolling a `.background(…).cornerRadius(…)` wash, so
  /// every card across the app shares one chrome. Colors are system-semantic, so
  /// the card renders correctly in light and dark. The card fills the available
  /// width; it is chrome only — the caller owns the content and its layout.
  func lorvexCard(padding: CGFloat = LorvexDesign.Spacing.cardPadding) -> some View {
    modifier(LorvexCardModifier(padding: padding))
  }
}

private struct LorvexCardModifier: ViewModifier {
  let padding: CGFloat

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous)
  }

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(LorvexDesign.Palette.card, in: shape)
      .overlay(shape.strokeBorder(LorvexDesign.Palette.separator.opacity(0.5), lineWidth: 0.5))
      .shadow(
        color: LorvexDesign.Elevation.cardShadowColor,
        radius: LorvexDesign.Elevation.cardShadowRadius,
        y: LorvexDesign.Elevation.cardShadowY)
  }
}
