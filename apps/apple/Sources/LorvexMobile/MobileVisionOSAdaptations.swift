import SwiftUI

// MARK: - Spatial modifiers

extension View {
  /// Applies a glass background on visionOS; no-op on all other platforms.
  ///
  /// Attach to prominent outermost containers (NavigationStack wrappers, sheet roots,
  /// panel-level views). Not intended for rows, sections, or fine-grained list content.
  public func lorvexSpatialBackground() -> some View {
    #if os(visionOS)
      self.glassBackgroundEffect()
    #else
      self
    #endif
  }

  /// Applies generous horizontal and vertical padding on visionOS for spatial comfort;
  /// no-op on all other platforms.
  ///
  /// Use on outermost content containers where extra breathing room improves
  /// readability at immersive viewing distances.
  public func lorvexSpatialContainerPadding() -> some View {
    #if os(visionOS)
      self.padding(.horizontal, 24)
        .padding(.vertical, 16)
    #else
      self
    #endif
  }
}
