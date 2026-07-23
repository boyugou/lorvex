import Foundation
import LorvexCloudSync
import LorvexCore

extension MobileStore {
  /// Resolve and retain the sole live-wired coordinator this store may use.
  /// Production injects it eagerly; the lazy fallback keeps previews and tests
  /// inert until an explicit cloud-data action while still caching the first
  /// value for every later action/mode transition.
  func cloudDataCoordinatorForMaintenance() -> CloudSyncEngineCoordinator? {
    if let cloudDataMaintenanceCoordinator { return cloudDataMaintenanceCoordinator }
    // A live-mode service resolution already had the opportunity to supply the
    // coordinator. Nil here means this build has no live backend; do not invoke
    // the factory again during the refresh that follows that same transition.
    guard cloudSyncMode != .live else { return nil }
    let coordinator = cloudSyncServiceFactory(.live).coordinator
    cloudDataMaintenanceCoordinator = coordinator
    return coordinator
  }

  /// Continue a durable remote deletion without turning ordinary sync back on.
  /// The coordinator itself verifies the `.deleted` singleton before touching a
  /// zone, so a peer's explicit re-enable makes this a safe no-op.
  func retryPendingCloudDataDeletionCleanup() async {
    guard !isSettingCloudSyncMode, !isDataImportRunning,
      !isCloudDataDeletionRunning, !isCloudDeletionMaintenanceRunning,
      let sync = core as? any EnvelopeSyncServicing
    else { return }
    // Off mode has no ordinary sync coordinator, but the store retains the one
    // maintenance coordinator actor graph so retries and later mode transitions
    // share a gate and durable-state actors.
    let coordinator = cloudDataCoordinatorForMaintenance()
    guard let coordinator else { return }
    isCloudDeletionMaintenanceRunning = true
    _ = try? await Task.detached(priority: .utility) {
      try await coordinator.retryPendingCloudDataDeletionCleanup(sync: sync)
    }.value
    isCloudDeletionMaintenanceRunning = false
    await applyPendingCloudSyncModeIfNeeded()
  }

  /// Delete every Lorvex record from the signed-in iCloud account — for all
  /// devices that sync with it — leaving the local database untouched, then
  /// turn sync off durably. Sync stays off (and the engine stays paused behind
  /// the `userDeletedZone` re-opt-in gate) until the user explicitly turns it
  /// back on, which re-uploads this device's data.
  ///
  /// Returns `nil` on success, or a localized user-facing error message when
  /// nothing was deleted: no usable iCloud account, the zone delete failed on
  /// the wire (the engine restores the prior sync state, so a retry starts
  /// clean), or no CloudKit backend exists in this build. Works with sync off
  /// — the common case is a user who disabled sync and now wants the cloud
  /// copy gone too — through the same retained coordinator used by live mode,
  /// so only one file-backed store actor set is live per sync-state directory.
  public func deleteCloudDataEverywhere() async -> String? {
    let outcome = await performCloudDataDeletion()
    if outcome.deletionBarrierPublished {
      // The deletion's durable OFF (plus the `userDeletedZone` re-opt-in gate)
      // supersedes any mode toggle queued while it ran; re-enabling must be a
      // fresh, explicit post-deletion act.
      pendingCloudSyncMode = nil
    } else {
      // The deletion changed nothing, so honor a mode request queued while it
      // was in flight.
      await applyPendingCloudSyncModeIfNeeded()
    }
    return outcome.failureMessage
  }

  private func performCloudDataDeletion() async -> CloudDataDeletionOutcome {
    guard !isSettingCloudSyncMode, !isDataImportRunning, !isCloudDataDeletionRunning,
      !isCloudDeletionMaintenanceRunning
    else {
      return .failedBeforeBarrier(
        String(
          localized: "settings.sync.delete_cloud.error.busy",
          defaultValue: "Cloud Sync is updating. Try again in a moment.", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
    isCloudDataDeletionRunning = true
    defer { isCloudDataDeletionRunning = false }
    isSettingCloudSyncMode = true
    defer { isSettingCloudSyncMode = false }

    guard let coordinator = cloudDataCoordinatorForMaintenance()
    else {
      return .failedBeforeBarrier(
        String(
          localized: "settings.sync.delete_cloud.error.unavailable",
          defaultValue: "iCloud sync isn’t available in this build.", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
    guard let sync = core as? any EnvelopeSyncServicing else {
      return .failedBeforeBarrier(
        String(
          localized: "settings.sync.delete_cloud.error.unavailable",
          defaultValue: "iCloud sync isn’t available in this build.", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
    var cleanupFailureMessage: String?
    do {
      try await Task.detached(priority: .userInitiated) {
        try await coordinator.deleteAllCloudData(sync: sync)
      }.value
    } catch let deletionError as CloudSyncCloudDataDeletionError {
      switch deletionError {
      case .accountUnavailable:
        return .failedBeforeBarrier(
          String(
            localized: "settings.sync.delete_cloud.error.no_account",
            defaultValue: "No usable iCloud account. Sign in to iCloud and try again.",
            table: "Localizable", bundle: MobileL10n.bundle))
      case .cleanupIncomplete(let detail):
        cleanupFailureMessage = String(
          format: String(
            localized: "settings.sync.delete_cloud.error.failed",
            defaultValue:
              "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
            table: "Localizable", bundle: MobileL10n.bundle),
          detail)
      }
    } catch {
      return .failedBeforeBarrier(
        String(
          format: String(
            localized: "settings.sync.delete_cloud.error.failed",
            defaultValue:
              "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
            table: "Localizable", bundle: MobileL10n.bundle),
          error.localizedDescription))
    }

    // The remote deletion barrier is now durable (including the
    // cleanup-incomplete case). Invalidate every mode token captured before
    // this point before the next MainActor suspension.
    cloudDataDeletionEpoch &+= 1

    // The cloud copy is gone; honor "sync stays off until re-enabled" at the
    // app level too. Ordinary live sync is detached while the maintenance
    // coordinator remains retained. Re-enable therefore reuses its gate and
    // durable-state actors; the engine pause is a second consent boundary
    // against any path that enables live mode without explicit re-opt-in.
    MobileSetupPreferences(defaults: defaults).setCloudSyncMode(.off)
    let services = cloudSyncServiceFactory(.off)
    cloudSyncMode = .off
    cloudSyncSubscriber = services.subscriber
    cloudSyncCoordinator = nil
    hasRegisteredSubscription = false
    cloudSyncPacing.reset()
    // Set directly rather than via `refreshCloudSyncPauseReason()` — the
    // the ordinary live coordinator is detached now, but the durable state this
    // deletion just wrote IS `userDeletedZone`; the retained maintenance value
    // and the re-enable path read that same state.
    cloudSyncPauseReason = .userDeletedZone
    await loadRuntimeDiagnostics()
    return CloudDataDeletionOutcome(
      failureMessage: cleanupFailureMessage,
      deletionBarrierPublished: true)
  }
}

private struct CloudDataDeletionOutcome {
  let failureMessage: String?
  let deletionBarrierPublished: Bool

  static func failedBeforeBarrier(_ message: String) -> Self {
    Self(failureMessage: message, deletionBarrierPublished: false)
  }
}
