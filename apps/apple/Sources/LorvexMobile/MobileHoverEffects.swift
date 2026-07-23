import SwiftUI

extension View {
  /// Applies a pointer (iPad) / gaze (visionOS) hover highlight where available.
  @ViewBuilder
  func lorvexRowHoverEffect() -> some View {
    #if os(iOS) || os(visionOS)
      contentShape(Rectangle())
        .hoverEffect(.highlight)
    #else
      self
    #endif
  }

  /// Adds a lightweight lift affordance to high-value toolbar controls.
  @ViewBuilder
  func lorvexToolbarHoverEffect() -> some View {
    #if os(iOS) || os(visionOS)
      hoverEffect(.lift)
    #else
      self
    #endif
  }
}
