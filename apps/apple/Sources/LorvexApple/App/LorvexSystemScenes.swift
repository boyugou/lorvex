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
      .lorvexProductTimeZone(from: store)
  } label: {
    LorvexMenuBarExtraLabel(store: store)
      .lorvexClockLocale()
      .lorvexProductTimeZone(from: store)
  }
  .menuBarExtraStyle(.window)

  Settings {
    LorvexSettingsWindowView(settings: settings, store: store)
      .lorvexClockLocale()
      .lorvexProductTimeZone(from: store)
  }
}
