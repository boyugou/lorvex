import SwiftUI

public struct MobileShellConfiguration: Equatable, Sendable {
  public var appDisplayName: String
  public var defaultChromeStyle: MobileChromeStyle?

  public init(
    appDisplayName: String,
    defaultChromeStyle: MobileChromeStyle? = nil
  ) {
    self.appDisplayName = appDisplayName
    self.defaultChromeStyle = defaultChromeStyle
  }

  public func preferredChromeStyle(
    horizontalSizeClass: UserInterfaceSizeClass?
  ) -> MobileChromeStyle {
    defaultChromeStyle ?? MobileChromeStyle.preferred(horizontalSizeClass: horizontalSizeClass)
  }

  public static let mobile = MobileShellConfiguration(
    appDisplayName: MobileAppMetadata.appDisplayName
  )

  public static let vision = MobileShellConfiguration(
    appDisplayName: VisionAppMetadata.appDisplayName,
    defaultChromeStyle: .sidebar
  )
}
