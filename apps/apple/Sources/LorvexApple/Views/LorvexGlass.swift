import SwiftUI

extension View {
  /// Wraps a floating element — a toast or a milestone celebration — in the
  /// system **Liquid Glass** material.
  ///
  /// Glass is for the floating control layer, not for content: reach for this on
  /// elements that hover over the workspace, never on rows or cards inside it.
  /// The system material supplies its own highlight, border, and shadow, so the
  /// modifier adds none.
  func lorvexFloatingGlass(in shape: some Shape) -> some View {
    glassEffect(.regular, in: shape)
  }
}
