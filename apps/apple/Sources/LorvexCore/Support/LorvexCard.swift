import SwiftUI

extension View {
  /// The app's one elevated card chrome: inset the content by `padding`
  /// (`LorvexDesign.Spacing.cardPadding` by default), fill with the opaque
  /// `LorvexDesign.Palette.card` surface at `LorvexDesign.Radius.card`
  /// continuous corners, and draw a hairline `LorvexDesign.Palette.separator`
  /// border. Cards are flat: depth comes from the surface contrast against
  /// `Palette.groupedBackground`, as on the platforms' own grouped surfaces.
  ///
  /// Use this instead of hand-rolling a `.background(…).cornerRadius(…)` wash so
  /// every card shares one chrome. The card fills the available width; the
  /// caller owns the content and its layout.
  public func lorvexCard(padding: CGFloat = LorvexDesign.Spacing.cardPadding) -> some View {
    modifier(LorvexCardModifier(padding: padding))
  }

  /// A nested group inside a card or a workspace column: `Palette.insetFill`
  /// at `Radius.m`, no stroke. Inset the content by `padding`
  /// (`LorvexDesign.Spacing.m` by default). The panel stretches to the offered
  /// width, as a group in a column should; `hugsContent` sizes it to its
  /// content instead, for a panel that stands on its own in a pane.
  public func lorvexInsetPanel(
    padding: CGFloat = LorvexDesign.Spacing.m, hugsContent: Bool = false
  ) -> some View {
    modifier(LorvexInsetPanelModifier(padding: padding, hugsContent: hugsContent))
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
  }
}

private struct LorvexInsetPanelModifier: ViewModifier {
  let padding: CGFloat
  let hugsContent: Bool

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .frame(maxWidth: hugsContent ? nil : .infinity, alignment: .leading)
      .background(
        LorvexDesign.Palette.insetFill,
        in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous))
  }
}
