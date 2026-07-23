#if DEBUG
  import LorvexCore
  import SwiftUI

  /// DEBUG-only `--ui-preview` mode. Runs the *real* macOS windows (sidebar,
  /// task queue, calendar, detail panes) against a seeded real in-memory core with
  /// CloudKit and EventKit off, so the workspaces can be screenshotted headlessly
  /// (`ImageRenderer`/`--dump-snapshots` only renders the design atoms — `List`
  /// and `Table` containers collapse to placeholders).
  ///
  /// `swift run LorvexApple --ui-preview` (then `screencapture` the window).
  enum LorvexUIPreview {
    static var isActive: Bool {
      CommandLine.arguments.contains("--ui-preview")
    }
    // Navigation is driven by osascript sidebar clicks after launch, not a route
    // arg: setting `store.selection` during `init` (even to its current value)
    // fires the didSet and stops the WindowGroup window from opening.
  }

  extension LorvexAppleBootstrap {
    /// The full app store, but over a seeded in-memory core. `AppStore(core:)`
    /// defaults every other dependency to a no-op — no CloudKit coordinator, no
    /// EventKit, no-op schedulers/publishers — which is exactly what the snapshot
    /// dump uses; here the scene body renders the live windows instead of exiting.
    @MainActor
    static func makeUIPreviewStore() -> AppStore {
      AppStore(core: LorvexPreviewCoreFactory.makeUIPreviewSeededBlocking(
        todaySchedule: true,
        focusSchedule: CommandLine.arguments.contains("-uiPreviewFocusSchedule")))
    }

    /// Ephemeral settings for `--ui-preview`: a throwaway UserDefaults suite,
    /// wiped on each launch so the preview never reads or writes the user's real
    /// settings, with onboarding pre-completed so the setup wizard doesn't block
    /// the workspace under capture.
    @MainActor
    static func makeUIPreviewSettings() -> AppSettingsStore {
      let suite = "com.lorvex.apple.ui-preview"
      let defaults = UserDefaults(suiteName: suite) ?? .standard
      defaults.removePersistentDomain(forName: suite)
      let settings = AppSettingsStore(defaults: defaults)
      settings.setupCompleted = true
      return settings
    }
  }
#endif
