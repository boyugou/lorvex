import LorvexCloudSync
import LorvexCore

struct MobileCloudDeletionReenableRequest: Sendable {
  fileprivate let deletionEpoch: UInt64
}

public struct MobileCloudSyncResumeRequest: Sendable {
  fileprivate let adoptionRequest: CloudSyncAccountAdoptionRequest
  fileprivate let deletionEpoch: UInt64
}

extension MobileStore {
  /// Refresh `cloudSyncPauseReason` from the coordinator's durable pause state so
  /// the UI can surface a "sync paused" notice. A no-op when no coordinator is
  /// wired (sync off / non-live).
  func refreshCloudSyncPauseReason() async {
    cloudSyncPauseReason = await cloudSyncCoordinator?.currentPauseReason()
  }

  /// Adopt the currently signed-in iCloud account and resume sync — the resume
  /// path a "sync paused" notice offers after an account switch (or the user
  /// deleting the Lorvex zone). Pushes this device's local data into the current
  /// account's zone, records it as the account this device syncs with, and lifts
  /// the durable pause. A no-op when no coordinator / envelope backend is wired.
  ///
  /// This is deliberately the KEEP-LOCAL adopt: the device's existing local data
  /// is preserved and re-pushed into the adopted account. Whether adoption should
  /// instead WIPE local data and pull the adopted account fresh is a product
  /// decision not settled here.
  public func makeCloudSyncResumeRequest() async -> MobileCloudSyncResumeRequest? {
    guard !isCloudDataDeletionRunning, let pauseReason = cloudSyncPauseReason else {
      return nil
    }
    guard let coordinator = cloudSyncCoordinator ?? cloudDataMaintenanceCoordinator,
      let sync = core as? any EnvelopeSyncServicing,
      let adoptionRequest = await coordinator.makeAccountAdoptionRequest(
        sync: sync, expectedPauseReason: pauseReason),
      !isCloudDataDeletionRunning,
      cloudSyncPauseReason == pauseReason
    else { return nil }
    return MobileCloudSyncResumeRequest(
      adoptionRequest: adoptionRequest, deletionEpoch: cloudDataDeletionEpoch)
  }

  public func adoptCurrentCloudAccountAndResumeSync(
    request: MobileCloudSyncResumeRequest
  ) async {
    guard
      let coordinator = cloudSyncCoordinator,
      let sync = core as? any EnvelopeSyncServicing
    else { return }
    if request.adoptionRequest.pauseReason == .userDeletedZone {
      let authorization: @Sendable () async -> Bool = { [weak self] in
        await MainActor.run {
          guard let self else { return false }
          return !self.isCloudDataDeletionRunning
            && self.cloudDataDeletionEpoch == request.deletionEpoch
        }
      }
      await coordinator.confirmDeletedZoneReenable(
        sync: sync, request: request.adoptionRequest,
        authorization: authorization)
    } else {
      await coordinator.confirmBackfillIntoCurrentAccount(
        sync: sync, request: request.adoptionRequest)
    }
    await refreshCloudSyncPauseReason()
    cloudSyncPacing.reset()
    await refresh()
  }

  /// The explicit re-opt-in that follows an iCloud-data deletion: the user
  /// turned the sync mode back to Live in Settings, which is the consent to
  /// re-create the zone and re-upload this device's data. Lifts ONLY a
  /// `userDeletedZone` pause — an `accountChanged` pause keeps its own
  /// adopt-account consent flow (`adoptCurrentCloudAccountAndResumeSync`).
  /// Runs before the first live cycle so it resumes instead of wedging at the
  /// pause gate.
  func liftCloudDeletionPauseForExplicitReenable() async {
    guard !isCloudDataDeletionRunning else { return }
    await liftCloudDeletionPauseForExplicitReenable(
      request: MobileCloudDeletionReenableRequest(
        deletionEpoch: cloudDataDeletionEpoch))
  }

  func liftCloudDeletionPauseForExplicitReenable(
    request: MobileCloudDeletionReenableRequest
  ) async {
    guard
      let coordinator = cloudSyncCoordinator,
      await coordinator.currentPauseReason() == .userDeletedZone,
      let sync = core as? any EnvelopeSyncServicing
    else {
      await refreshCloudSyncPauseReason()
      return
    }
    guard let adoptionRequest = await coordinator
      .makeSameAccountDeletedZoneReenableRequest(sync: sync)
    else {
      await refreshCloudSyncPauseReason()
      return
    }
    let authorization: @Sendable () async -> Bool = { [weak self] in
      await MainActor.run {
        guard let self else { return false }
        return !self.isCloudDataDeletionRunning
          && self.cloudDataDeletionEpoch == request.deletionEpoch
      }
    }
    await coordinator.confirmDeletedZoneReenable(
      sync: sync, request: adoptionRequest, authorization: authorization)
    await refreshCloudSyncPauseReason()
  }
}
