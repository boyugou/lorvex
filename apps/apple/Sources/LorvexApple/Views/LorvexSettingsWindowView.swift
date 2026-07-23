import SwiftUI

struct LorvexSettingsWindowView: View {
  let settings: AppSettingsStore
  let store: AppStore

  var body: some View {
    SettingsView(settings: settings, store: store)
      .tint(.accentColor)
      // The Settings scene is its own window; without this it had no error
      // surface, so working-hours validation, diagnostics, runtime-apply, and
      // factory-reset failures set store.errorMessage but were never shown.
      .lorvexErrorAlert(store)
  }
}
