import AppKit
import LorvexCore
import SwiftUI

struct LorvexMainWindowView: View {
  let store: AppStore
  let settings: AppSettingsStore
  let openMainWindow: () -> Void

  var body: some View {
    ContentView(store: store, settings: settings)
      .tint(.accentColor)
      .lorvexMinimumWindowSize(.main)
      .lorvexMainWindowLifecycle(store, openMainWindow: openMainWindow)
      // App-lifetime, not per-window: the store retains these observers so they
      // keep running after this window closes (the menu-bar extra keeps the app
      // alive). A `.task` here would cancel them on window close, leaving open
      // workspace windows stale and notification-action failures dropped.
      .onAppear { store.startLifetimeObserversIfNeeded() }
      .onAppear { Self.apply(settings.appearance) }
      .onChange(of: settings.appearance) { _, newValue in Self.apply(newValue) }
  }

  /// Force the chosen appearance across every window by setting the
  /// application-level `NSAppearance` (nil = follow the system). Applied at the
  /// app level rather than per-scene so the settings and detached windows honor
  /// the choice too.
  private static func apply(_ appearance: AppAppearance) {
    switch appearance {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
  }
}
