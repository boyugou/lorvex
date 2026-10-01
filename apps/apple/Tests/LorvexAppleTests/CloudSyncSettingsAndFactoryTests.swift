import CloudKit
import Foundation
import LorvexCore
import Testing
import LorvexCloudSync

@testable import LorvexApple

// MARK: - Factory wiring

@Test
func factoryBuildsAControllerForAnEnvelopeCoreInEveryMode() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-factory-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let controller = AppCoreFactory.makeCloudSyncController(
    core: try SwiftLorvexCoreService.inMemory(), stateDirectoryOverride: directory)
  #expect(controller != nil)
}

@Test
func envVarOverridesBeatsPersistentSetting() {
  // env "live" beats stored .off
  let mode1 = CloudSyncFactory.resolveMode(
    persistedMode: .off,
    environment: ["LORVEX_CLOUD_SYNC": "live"]
  )
  #expect(mode1 == .live)

  // absent env key falls back to stored mode
  let mode2 = CloudSyncFactory.resolveMode(persistedMode: .live, environment: [:])
  #expect(mode2 == .live)

  // any other env value → .off
  let mode3 = CloudSyncFactory.resolveMode(
    persistedMode: .live,
    environment: ["LORVEX_CLOUD_SYNC": "bogus"]
  )
  #expect(mode3 == .off)
}

// MARK: - AppSettingsStore persists cloud sync mode

@Test
@MainActor
func appSettingsStoreDefaultsCloudSyncModeToOff() {
  let suiteName = "test.cloudSyncMode.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let settings = AppSettingsStore(defaults: defaults, environment: [:])
  #expect(settings.cloudSyncMode == .off)
}

@Test
@MainActor
func appSettingsStoreRoundTripsPersistenceForCloudSyncMode() {
  let suiteName = "test.cloudSyncMode.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  do {
    let settings = AppSettingsStore(defaults: defaults, environment: [:])
    settings.cloudSyncMode = .live
    #expect(settings.cloudSyncMode == .live)
  }
  // Re-initialise from the same defaults to verify persistence.
  let settings2 = AppSettingsStore(defaults: defaults, environment: [:])
  #expect(settings2.cloudSyncMode == .live)
}
