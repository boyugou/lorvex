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
    .lorvexClockLocale()
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
  // The title bar text is hidden: each workspace names itself with a large
  // in-content title, while its navigation and actions ride in the unified
  // toolbar the workspaces populate through `.toolbar`. The sidebar keeps the
  // standard traffic-light area visible.
  .windowStyle(.hiddenTitleBar)
}
