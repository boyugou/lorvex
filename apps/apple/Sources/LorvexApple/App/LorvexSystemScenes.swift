import SwiftUI

@SceneBuilder
@MainActor
func lorvexSystemScenes(
  store: AppStore,
  settings: AppSettingsStore
) -> some Scene {
  MenuBarExtra {
    LorvexMenuBarExtraView(store: store)
  } label: {
    LorvexMenuBarExtraLabel(store: store)
  }
  .menuBarExtraStyle(.window)

  Settings {
    LorvexSettingsWindowView(settings: settings, store: store)
  }
}
