import SwiftUI

extension View {
  /// Sets the spacing after a list section on iOS, where a page's opening
  /// section (a header, a summary) introduces the list under it and so sits
  /// closer than the gap between two cards. Section spacing is an iOS list
  /// feature; the macOS SwiftPM build of this module keeps the default.
  @ViewBuilder
  func mobileListSectionSpacing(_ spacing: CGFloat) -> some View {
    #if os(iOS)
      listSectionSpacing(spacing)
    #else
      self
    #endif
  }
}
