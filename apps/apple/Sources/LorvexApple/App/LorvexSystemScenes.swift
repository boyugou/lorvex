import SwiftUI

@SceneBuilder
@MainActor
func lorvexSystemScenes(
  store: AppStore,
  settings: AppSettingsStore
) -> some Scene {
  MenuBarExtra {
    LorvexMenuBarExtraView(store: store)
      .lorvexClockLocale()
  } label: {
    LorvexMenuBarExtraLabel(store: store)
      .lorvexClockLocale()
  }
  .menuBarExtraStyle(.window)

  Settings {
    LorvexSettingsWindowView(settings: settings, store: store)
      .lorvexClockLocale()
  }
}
