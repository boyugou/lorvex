import LorvexCore
import SwiftUI

extension View {
  /// Pads the scrolling content of a detail panel (a habit's or a memory
  /// entry's). On a phone the sides take `Spacing.l`, the inset the Review
  /// pages use, so the panel's cards keep the width a narrow screen has to
  /// give; at regular width they take `Spacing.xl`, the only inset a split's
  /// detail pane has. The top and bottom always take `Spacing.xl`.
  func mobileDetailPanelPadding() -> some View {
    modifier(MobileDetailPanelPadding())
  }
}

/// The side inset of a detail panel for a horizontal size class: `Spacing.l`
/// at compact width and `Spacing.xl` otherwise, including when the size class
/// is unknown.
enum MobileDetailPanelInset {
  static func horizontal(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
    sizeClass == .compact ? LorvexDesign.Spacing.l : LorvexDesign.Spacing.xl
  }
}

private struct MobileDetailPanelPadding: ViewModifier {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, MobileDetailPanelInset.horizontal(for: horizontalSizeClass))
      .padding(.vertical, LorvexDesign.Spacing.xl)
  }
}
