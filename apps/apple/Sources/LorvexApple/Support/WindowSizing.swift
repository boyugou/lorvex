import SwiftUI

extension View {
  func lorvexMinimumWindowSize(_ windowID: LorvexWindowID) -> some View {
    frame(
      minWidth: windowID.minimumContentSize.width,
      minHeight: windowID.minimumContentSize.height
    )
  }
}

extension Scene {
  func lorvexDefaultWindowPosition() -> some Scene {
    defaultPosition(.center)
  }

  func lorvexMainWindowSizing() -> some Scene {
    defaultSize(width: 1180, height: 720)
      .windowResizability(.contentMinSize)
  }
}
