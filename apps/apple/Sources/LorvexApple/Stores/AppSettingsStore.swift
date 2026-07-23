import Foundation
import LorvexCore
import Observation
import SwiftUI
import LorvexCloudSync

/// Persisted app settings.
///
/// Storage is fixed: every surface opens the single Lorvex-managed App Group
/// database (see ``AppCoreFactory/make()``); cross-device sync is CloudKit-only.
/// There is no runtime database selection here — a launch-time
/// `LORVEX_APPLE_DB_PATH` override is honored directly by the core's storage
/// locator on unsandboxed dev/source builds, never routed through this store.
@MainActor
@Observable
final class AppSettingsStore {
  let defaults: UserDefaults
  let environment: [String: String]

  /// Persisted Cloud Sync mode. Defaults to `.off`. The env var
  /// `LORVEX_CLOUDKIT_EXPORT` overrides this at runtime; see
  /// `AppCoreFactory.resolveCloudSyncMode(settings:environment:)`.
  /// Changing this setting takes effect at next app launch.
  var cloudSyncMode: CloudSyncMode {
    didSet { defaults.set(cloudSyncMode.rawValue, forKey: Key.cloudSyncMode) }
  }

  /// Whether the first-run setup wizard has been completed. Defaults to
  /// `false`; set to `true` when the user finishes or dismisses the wizard,
  /// preventing it from appearing again.
  var setupCompleted: Bool {
    didSet { defaults.set(setupCompleted, forKey: Key.setupCompleted) }
  }

  /// Whether the app-icon badge should reflect the count of due/overdue tasks.
  /// Defaults to `true`; set by the user via Settings > Notifications.
  var badgeEnabled: Bool {
    didSet { defaults.set(badgeEnabled, forKey: Key.badgeEnabled) }
  }

  /// Whether the EventKit two-way calendar integration is enabled. Defaults to
  /// `false`; never auto-enabled. When `false`, no system-calendar events are
  /// ingested into the local mirror, no permission prompt is issued, and the
  /// dedicated Lorvex calendar is not written.
  var eventKitEnabled: Bool {
    didSet { defaults.set(eventKitEnabled, forKey: Key.eventKitEnabled) }
  }

  /// Calendar-filter mode for EventKit ingest. `.allExcept` mirrors all user
  /// calendars except muted rows; `.onlySelected` mirrors just checked rows.
  var eventKitCalendarFilterMode: EventKitCalendarFilterMode {
    didSet { defaults.set(eventKitCalendarFilterMode.rawValue, forKey: Key.eventKitCalendarFilterMode) }
  }

  /// EventKit allow-list for the `.onlySelected` mode (the checked calendars).
  /// In `.allExcept` mode this is empty and ignored. Note the empty set is
  /// mode-dependent: empty in `.allExcept` mirrors all (minus excludes), but
  /// empty in `.onlySelected` mirrors nothing (see `EventKitCalendarFilter`).
  var eventKitIncludedCalendarIDs: Set<String> {
    didSet {
      defaults.set(
        Self.persistedCalendarIDs(eventKitIncludedCalendarIDs),
        forKey: Key.eventKitIncludedCalendarIDs)
    }
  }

  /// EventKit deny-list. Exclusions win over the allow-list and are applied
  /// before events enter the local provider mirror.
  var eventKitExcludedCalendarIDs: Set<String> {
    didSet {
      defaults.set(
        Self.persistedCalendarIDs(eventKitExcludedCalendarIDs),
        forKey: Key.eventKitExcludedCalendarIDs)
    }
  }

  var eventKitCalendarFilter: EventKitCalendarFilter {
    EventKitCalendarFilter(
      mode: eventKitCalendarFilterMode,
      selectedCalendarIDs: eventKitIncludedCalendarIDs,
      excludedCalendarIDs: eventKitExcludedCalendarIDs)
  }

  /// The user's chosen app appearance. Defaults to `.system` (follow macOS).
  /// Applied app-wide via `NSApp.appearance` so every window — main, settings,
  /// detached — honors it, not just the SwiftUI scene that sets it.
  var appearance: AppAppearance {
    didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
  }

  init(
    defaults: UserDefaults = .standard,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.defaults = defaults
    self.environment = environment

    if let storedCloud = defaults.string(forKey: Key.cloudSyncMode),
      let mode = CloudSyncMode(rawValue: storedCloud)
    {
      cloudSyncMode = mode
    } else {
      cloudSyncMode = .off
    }

    setupCompleted = defaults.bool(forKey: Key.setupCompleted)
    eventKitEnabled = defaults.bool(forKey: Key.eventKitEnabled)
    eventKitCalendarFilterMode =
      defaults.string(forKey: Key.eventKitCalendarFilterMode)
      .flatMap(EventKitCalendarFilterMode.init(rawValue:)) ?? .allExcept
    eventKitIncludedCalendarIDs = Self.loadedCalendarIDs(
      defaults.stringArray(forKey: Key.eventKitIncludedCalendarIDs))
    eventKitExcludedCalendarIDs = Self.loadedCalendarIDs(
      defaults.stringArray(forKey: Key.eventKitExcludedCalendarIDs))
    badgeEnabled = defaults.object(forKey: Key.badgeEnabled) == nil
      ? true
      : defaults.bool(forKey: Key.badgeEnabled)
    appearance =
      defaults.string(forKey: Key.appearance)
      .flatMap(AppAppearance.init(rawValue:)) ?? .system
  }
}
