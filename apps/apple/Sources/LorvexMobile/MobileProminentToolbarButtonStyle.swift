import SwiftUI

extension View {
  /// The filled ("prominent") toolbar button style for the one action a bar
  /// exists to confirm: a sheet's Save / Create / Add / Import, or a detail's
  /// primary status action. Liquid Glass on iOS and macOS. A `ProgressView` shown inside such a button needs
  /// `.tint(.white)` to stay visible on the filled capsule.
  @ViewBuilder
  func mobileProminentToolbarButtonStyle() -> some View {
    buttonStyle(.glassProminent)
  }
}
