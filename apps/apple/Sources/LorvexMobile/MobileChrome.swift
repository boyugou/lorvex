import SwiftUI

public enum MobileChromeStyle: Equatable, Sendable {
  case tabBar
  case sidebar

  public static func preferred(horizontalSizeClass: UserInterfaceSizeClass?) -> MobileChromeStyle {
    #if os(visionOS)
      return .sidebar
    #else
      return horizontalSizeClass == .regular ? .sidebar : .tabBar
    #endif
  }
}
