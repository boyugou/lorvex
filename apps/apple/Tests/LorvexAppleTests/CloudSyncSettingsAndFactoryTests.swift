import CloudKit
import Foundation
import LorvexCore
import Testing
import LorvexCloudSync

@testable import LorvexApple

// MARK: - Factory wiring resolves correct services

@Test
func factoryResolvesOffModeToNoopServices() {
  let subscriber = AppCoreFactory.makeCloudSyncSubscriber(persistedMode: .off, environment: [:])
  let coordinator = AppCoreFactory.makeCloudSyncCoordinator(
    persistedMode: .off,
    environment: [:]
  )
  #expect(subscriber is NoOpCloudSyncSubscriber)
  #expect(coordinator == nil)
}

@Test
func factoryResolvesRecordPlanModeToSubscriberButNoCoordinator() {
  let subscriber = AppCoreFactory.makeCloudSyncSubscriber(
    persistedMode: .recordPlan,
    environment: [:]
  )
  let coordinator = AppCoreFactory.makeCloudSyncCoordinator(
    persistedMode: .recordPlan,
    environment: [:]
  )
  #expect(subscriber is CloudKitCloudSyncSubscriber)
  // The engine sync coordinator is built only for .live; record-plan registers
  // the push subscription but runs no sync cycle.
  #expect(coordinator == nil)
}

@Test
func factoryResolvesLiveModeToCoordinator() {
  let coordinator = AppCoreFactory.makeCloudSyncCoordinator(
    persistedMode: .live,
    environment: [:]
  )
  #expect(coordinator != nil)
}

@Test
func envVarOverridesBeatsPersistentSetting() {
  // env "live" beats stored .off
  let mode1 = AppCoreFactory.resolveCloudSyncMode(
    persistedMode: .off,
    environment: ["LORVEX_CLOUDKIT_EXPORT": "live"]
  )
  #expect(mode1 == .live)

  // env "record-plan" beats stored .live
  let mode2 = AppCoreFactory.resolveCloudSyncMode(
    persistedMode: .live,
    environment: ["LORVEX_CLOUDKIT_EXPORT": "record-plan"]
  )
  #expect(mode2 == .recordPlan)

  // absent env key falls back to stored mode
  let mode3 = AppCoreFactory.resolveCloudSyncMode(persistedMode: .live, environment: [:])
  #expect(mode3 == .live)

  // unknown env value → .off
  let mode4 = AppCoreFactory.resolveCloudSyncMode(
    persistedMode: .live,
    environment: ["LORVEX_CLOUDKIT_EXPORT": "unknown-value"]
  )
  #expect(mode4 == .off)
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
