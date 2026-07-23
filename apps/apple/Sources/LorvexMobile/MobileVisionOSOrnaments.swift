import SwiftUI

// MARK: - Ornament modifier

extension View {
  /// Attaches `content` as a `.bottom`-anchored ornament on visionOS; no-op on all other platforms.
  ///
  /// Use for primary contextual actions that should float below the window in spatial computing.
  /// Content receives full SwiftUI layout and can reference bindings captured at the call site.
  @ViewBuilder
  public func lorvexBottomOrnament<Content: View>(
    isVisible: Bool = true,
    @ViewBuilder _ content: () -> Content
  ) -> some View {
    #if os(visionOS)
      if isVisible {
        self.ornament(
          visibility: .visible,
          attachmentAnchor: .scene(.bottom)
        ) {
          content()
            .frame(maxWidth: 600)
            .padding()
            .glassBackgroundEffect()
        }
      } else {
        self
      }
    #else
      self
    #endif
  }
}
