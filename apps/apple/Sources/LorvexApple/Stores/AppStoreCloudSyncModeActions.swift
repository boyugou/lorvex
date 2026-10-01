import LorvexCloudSync
import LorvexCore

extension AppStore {
  /// Turns iCloud sync on from a control (the Settings picker, the setup
  /// wizard's iCloud Sync page): saves the choice to `settings`, then turns
  /// sync on in the running app. A developer environment that pins another
  /// mode (`LORVEX_CLOUD_SYNC`) keeps the running mode, and the saved
  /// choice applies at a launch without that override.
  func turnOnCloudSync(settings: AppSettingsStore) {
    settings.cloudSyncMode = .live
    guard
      CloudSyncFactory.resolveMode(
        persistedMode: .live, environment: settings.environment) == .live,
      let request = makeCloudDeletionReenableRequest()
    else { return }
    turnOnCloudSync(request: request)
  }

  /// Turns iCloud sync on in the running app, with no relaunch.
  ///
  /// The mode switches before this returns, so nothing ever shows the choice
  /// as pending. The returned task finishes the work that waits on iCloud: it
  /// lifts a standing cloud-data deletion pause (turning sync on is that
  /// consent), starts the controller, and runs a full refresh, whose cycle
  /// uploads the local database.
  ///
  /// `request` is captured when the choice is made, so a cloud-data deletion
  /// accepted after it supersedes it. Returns nil, changing nothing, when the
  /// request no longer stands, sync is already live, or the store has no
  /// controller (previews and tests without one).
  @discardableResult
  func turnOnCloudSync(request: CloudDeletionReenableRequest) -> Task<Void, Never>? {
    guard cloudSyncMode != .live, isCurrent(request), let cloudSyncController else { return nil }
    cloudSyncMode = .live
    return Task {
      await liftCloudDeletionPauseForExplicitReenable(request: request)
      await applyCloudSyncControllerState(await cloudSyncController.start())
      await refresh()
    }
  }

  /// Turns iCloud sync off in the running app. Local data, the outbox, and
  /// the engine's state stay, so turning it back on resumes where it stopped.
  func turnOffCloudSync() {
    cloudSyncMode = .off
    guard let cloudSyncController else { return }
    Task { await cloudSyncController.stop() }
  }
}
