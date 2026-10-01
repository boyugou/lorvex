import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexMobile

/// The iOS local erase. Every case binds `localDataResetDependencies` to a
/// temporary database so the irreversible branch runs without touching the
/// developer's own App-Group store.
///
/// Scope of what these cases can prove: the ordering, the settings reset, and the
/// failure rollback. Not that the rows are gone. The seam redirects which file is
/// erased, but the reset also closes the injected core for the cutover — and a
/// closed in-memory store reopens against the real managed database on its next
/// read, so anything read after the cutover is the developer's own store rather
/// than the fixture. Assertions here therefore stay on preferences and runtime
/// state, never on post-reset row or selection contents.
@Suite("MobileStore local data reset")
@MainActor
struct MobileStoreLocalDataResetTests {

  private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-reset-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("lorvex.db")
  }

  private func makeStore(defaults: UserDefaults, mode: CloudSyncMode = .off) async throws
    -> MobileStore
  {
    MobileStore(
      core: try await makeSeededInMemoryCore(),
      todayString: { "2026-05-23" },
      defaults: defaults,
      cloudSyncMode: mode)
  }

  @Test
  func resetErasesTheManagedStoreAndReturnsTheDeviceToFirstLaunch() async throws {
    let suiteName = "test.mobile.reset.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = MobileSetupPreferences(defaults: defaults)
    preferences.complete()
    preferences.setCloudSyncMode(.live)
    // Set against its documented default, so a value back at the default after
    // the erase proves the key was removed rather than merely re-read.
    preferences.setBadgeEnabled(false)
    #expect(preferences.setupCompleted)
    #expect(!preferences.badgeEnabled)

    let url = temporaryDatabaseURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = try await makeStore(defaults: defaults, mode: .live)

    let failure = await MobileStore.$localDataResetDependencies.withValue(
      .init(databaseURL: url)
    ) {
      await store.performLocalDataReset()
    }

    #expect(failure == nil, "the erase reports success")
    #expect(!preferences.setupCompleted, "the device returns to a pre-setup state")
    #expect(preferences.cloudSyncMode == .off, "sync is durably off after an erase")
    #expect(
      preferences.badgeEnabled,
      "every owned preference key is cleared, not just sync — badges are back at their default")
    #expect(store.cloudSyncMode == .off, "the runtime mode is off so no cycle repopulates it")
    #expect(store.isLocalDataResetRunning == false, "the in-flight flag is released")
    #expect(store.isSettingCloudSyncMode == false, "the mode-transition gate is released")
  }

  @Test
  func resetIsRejectedWhileAnotherDestructiveOperationHoldsTheStore() async throws {
    let suiteName = "test.mobile.reset.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    MobileSetupPreferences(defaults: defaults).complete()

    let store = try await makeStore(defaults: defaults)
    store.isDataImportRunning = true

    let url = temporaryDatabaseURL()
    let failure = await MobileStore.$localDataResetDependencies.withValue(
      .init(databaseURL: url)
    ) {
      await store.performLocalDataReset()
    }

    #expect(failure != nil, "a busy store refuses the erase instead of racing it")
    #expect(
      MobileSetupPreferences(defaults: defaults).setupCompleted,
      "a refused erase leaves the device's setup state untouched")
    #expect(
      !FileManager.default.fileExists(atPath: url.path),
      "a refused erase never reaches the storage cutover")
  }

  @Test
  func resetRestoresTheRuntimeSyncModeWhenTheCutoverFails() async throws {
    let suiteName = "test.mobile.reset.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    MobileSetupPreferences(defaults: defaults).complete()

    let store = try await makeStore(defaults: defaults, mode: .live)
    // A path whose parent directory can never exist: the reset cannot take its
    // storage lock there, so the cutover throws and the pre-erase state must
    // come back rather than the store reporting a wipe that never happened.
    let url = URL(fileURLWithPath: "/dev/null/lorvex-reset-unwritable/lorvex.db")

    let failure = await MobileStore.$localDataResetDependencies.withValue(
      .init(databaseURL: url)
    ) {
      await store.performLocalDataReset()
    }

    #expect(failure != nil, "a failed erase reports it rather than claiming success")
    #expect(store.cloudSyncMode == .live, "the runtime sync mode is restored")
    #expect(
      MobileSetupPreferences(defaults: defaults).setupCompleted,
      "settings are only reset once the wipe is known to have completed")
    #expect(store.isLocalDataResetRunning == false)
  }
}
