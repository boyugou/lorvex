import LorvexSystemIntents
import SwiftUI

@main
struct LorvexAppleApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow
  @State private var settings: AppSettingsStore
  @State private var store: AppStore

  init() {
    #if DEBUG
      // Renders desktop design components to a PNG and exits when
      // `--dump-snapshots <dir>` is passed; must run before any CloudKit-touching
      // bootstrap. No-op otherwise.
      LorvexAppleSnapshotDump.runIfRequested()
    #endif
    LorvexAppleBootstrap.configure()
    #if DEBUG
      // `--ui-preview` runs the *real* windows (sidebar/queue/workspaces) against a
      // seeded in-memory core with CloudKit/EventKit off and ephemeral settings
      // (onboarding pre-completed) — the only way to screenshot the macOS
      // workspaces headlessly (ImageRenderer can't render List/Table; the dump
      // only does atoms). It never touches the user's real store or settings.
      if LorvexUIPreview.isActive {
        let settings = LorvexAppleBootstrap.makeUIPreviewSettings()
        _settings = State(initialValue: settings)
        _store = State(initialValue: LorvexAppleBootstrap.makeUIPreviewStore())
      } else {
        let settings = LorvexAppleBootstrap.makeSettings()
        _settings = State(initialValue: settings)
        _store = State(initialValue: LorvexAppleBootstrap.makeStore(settings: settings))
      }
    #else
      let settings = LorvexAppleBootstrap.makeSettings()
      _settings = State(initialValue: settings)
      _store = State(initialValue: LorvexAppleBootstrap.makeStore(settings: settings))
    #endif
    appDelegate.installTerminationStore(store)
  }

  var body: some Scene {
    lorvexPrimaryScenes(store: store, settings: settings) {
      openWindow(.main)
    }

    lorvexWorkspaceScenes(store: store)

    lorvexDetachedScenes(store: store)

    lorvexSystemScenes(store: store, settings: settings)
  }

}
