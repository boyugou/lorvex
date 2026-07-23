import Foundation
import Testing

@testable import LorvexApple

@MainActor
@Test
func appSettingsStorePersistsCloudSyncMode() {
  let suiteName = "LorvexAppleTests-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettingsStore(defaults: defaults, environment: [:])
  settings.cloudSyncMode = .live

  let restored = AppSettingsStore(defaults: defaults, environment: [:])
  #expect(restored.cloudSyncMode == .live)
}

@MainActor
@Test
func appSettingsStoreResetToDefaultsRestoresFirstLaunchState() {
  let suiteName = "LorvexAppleTests.reset.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettingsStore(defaults: defaults, environment: [:])
  // Diverge every preference from its default, plus the auxiliary keys.
  settings.cloudSyncMode = .live
  settings.setupCompleted = true
  settings.badgeEnabled = false
  settings.eventKitEnabled = true
  settings.eventKitCalendarFilterMode = .onlySelected
  settings.eventKitIncludedCalendarIDs = ["work"]
  settings.appearance = .dark
  defaults.set(true, forKey: EventKitAccessLatch.calendarKey)
  defaults.set("cal-123", forKey: "eventKit.lorvexCalendarID")

  settings.resetToDefaults()

  #expect(settings.cloudSyncMode == .off)
  #expect(settings.setupCompleted == false)
  #expect(settings.badgeEnabled == true)
  #expect(settings.eventKitEnabled == false)
  #expect(settings.eventKitCalendarFilterMode == .allExcept)
  #expect(settings.eventKitIncludedCalendarIDs.isEmpty)
  #expect(settings.appearance == .system)
  #expect(defaults.bool(forKey: EventKitAccessLatch.calendarKey) == false)
  #expect(defaults.string(forKey: "eventKit.lorvexCalendarID") == nil)

  // The reset is durable: a freshly loaded store sees the defaults too.
  let restored = AppSettingsStore(defaults: defaults, environment: [:])
  #expect(restored.setupCompleted == false)
  #expect(restored.appearance == .system)
}

@MainActor
@Test
func appSettingsStorePersistsEventKitCalendarFilter() {
  let suiteName = "LorvexAppleTests.eventkit-calendar-filter.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettingsStore(defaults: defaults, environment: [:])
  settings.eventKitCalendarFilterMode = .onlySelected
  settings.eventKitIncludedCalendarIDs = ["work", " personal ", ""]
  settings.eventKitExcludedCalendarIDs = ["ignored"]

  let restored = AppSettingsStore(defaults: defaults, environment: [:])

  #expect(restored.eventKitCalendarFilterMode == .onlySelected)
  #expect(restored.eventKitIncludedCalendarIDs == ["work", "personal"])
  #expect(restored.eventKitExcludedCalendarIDs == ["ignored"])
  #expect(restored.eventKitCalendarFilter.allows(calendarID: "work"))
  #expect(!restored.eventKitCalendarFilter.allows(calendarID: "other"))
}

@MainActor
@Test
func appSettingsStoreReflectsLaunchEnvironmentDatabaseOverrideWithoutPersisting() {
  let suiteName = "LorvexAppleTests.env-override.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let plain = AppSettingsStore(defaults: defaults, environment: [:])
  #expect(!plain.usesEnvironmentDatabasePath)

  let overridden = AppSettingsStore(
    defaults: defaults, environment: ["LORVEX_APPLE_DB_PATH": "/tmp/dev.db"])
  #expect(overridden.usesEnvironmentDatabasePath)
  // The dev override is read directly from the environment, never persisted: a
  // fresh store over the same defaults but an empty environment sees no override.
  let reloaded = AppSettingsStore(defaults: defaults, environment: [:])
  #expect(!reloaded.usesEnvironmentDatabasePath)
}
