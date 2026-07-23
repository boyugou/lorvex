import SwiftUI

extension View {
  /// Wraps a floating element — the focus dock, a toast, the command palette,
  /// capsule pills — in the system **Liquid Glass** material on macOS 26+, and in
  /// a bordered `.regularMaterial` shape with a soft drop shadow on earlier
  /// releases.
  ///
  /// Glass is for the floating control layer, not for content: reach for this on
  /// elements that hover over the workspace, never on rows or cards inside it. On
  /// macOS 26 the system material supplies its own highlight, border, and shadow,
  /// so the modifier adds none; the pre-26 fallback hand-rolls an equivalent so
  /// the same element still reads as a distinct floating surface.
  @ViewBuilder
  func lorvexFloatingGlass(in shape: some Shape) -> some View {
    if #available(macOS 26.0, iOS 26.0, *) {
      glassEffect(.regular, in: shape)
    } else {
      background(.regularMaterial, in: shape)
        .overlay { shape.stroke(.separator.opacity(0.55), lineWidth: 1) }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
    }
  }
}
