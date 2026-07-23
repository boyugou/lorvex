import LorvexCore
import SwiftUI

@SceneBuilder
@MainActor
func lorvexPrimaryScenes(
  store: AppStore,
  settings: AppSettingsStore,
  openMainWindow: @escaping () -> Void
) -> some Scene {
  mainWindowScene(store: store, settings: settings, openMainWindow: openMainWindow)
}

@MainActor
private func mainWindowScene(
  store: AppStore,
  settings: AppSettingsStore,
  openMainWindow: @escaping () -> Void
) -> some Scene {
  Window(LorvexWindowID.main.title, id: LorvexWindowID.main.rawValue) {
    LorvexMainWindowView(
      store: store,
      settings: settings,
      openMainWindow: openMainWindow
    )
  }
  .commands {
    LorvexAppCommands(store: store)
  }
  .handlesExternalEvents(matching: [
    LorvexDeepLinkRoute.openHost,
    LorvexDeepLinkRoute.taskHost,
    LorvexDeepLinkRoute.listHost,
    LorvexDeepLinkRoute.habitHost,
    LorvexDeepLinkRoute.reviewHost,
  ])
  .lorvexDefaultWindowPosition()
  .lorvexMainWindowSizing()
  // The main window has no global toolbar/search row; content starts at the
  // top of the window and workspace-specific actions stay inline in content.
  // The sidebar still keeps the standard traffic-light area visible.
  .windowStyle(.hiddenTitleBar)
}
