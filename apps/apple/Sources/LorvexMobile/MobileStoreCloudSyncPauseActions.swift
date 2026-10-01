import LorvexCloudSync
import LorvexCore

public struct MobileCloudSyncResumeRequest: Sendable {
  fileprivate let pauseReason: CloudSyncPauseReason
  fileprivate let deletionEpoch: UInt64
}

extension MobileStore {
  /// Refresh `cloudSyncPauseReason` from the controller's durable pause state
  /// so the UI can surface a "sync paused" notice. A no-op without a
  /// controller (previews and tests).
  func refreshCloudSyncPauseReason() async {
    guard let cloudSyncController else { return }
    cloudSyncPauseReason = await cloudSyncController.currentPauseReason()
  }

  /// Captures consent for the action a "Sync Paused" notice offers. After an
  /// account change it uploads this device's data into the current account and
  /// merges it with what is there; after a cloud-data deletion it uploads into
  /// a new zone. The request is made before the UI spawns its Task, so a cloud
  /// deletion accepted afterwards voids it.
  public func makeCloudSyncResumeRequest() async -> MobileCloudSyncResumeRequest? {
    guard !isCloudDataDeletionRunning, let pauseReason = cloudSyncPauseReason,
      cloudSyncController != nil
    else { return nil }
    return MobileCloudSyncResumeRequest(
      pauseReason: pauseReason, deletionEpoch: cloudDataDeletionEpoch)
  }

  public func adoptCurrentCloudAccountAndResumeSync(
    request: MobileCloudSyncResumeRequest
  ) async {
    guard let controller = cloudSyncController, !isCloudDataDeletionRunning,
      cloudDataDeletionEpoch == request.deletionEpoch,
      await controller.currentPauseReason() == request.pauseReason
    else { return }
    let state: CloudSyncControllerState
    switch request.pauseReason {
    case .userDeletedZone:
      state = (try? await controller.reenableAfterCloudDeletion()) ?? .failed("reenable failed")
    case .accountChanged:
      state = (try? await controller.adoptCurrentAccount()) ?? .failed("adoption failed")
    }
    await applyCloudSyncControllerState(state)
    await refresh()
  }

  /// The explicit re-opt-in that follows an iCloud-data deletion: turning
  /// sync back on is the consent to create a new zone and upload this
  /// device's data. Lifts only a `userDeletedZone` pause; an `accountChanged`
  /// pause keeps its own consent flow
  /// (``adoptCurrentCloudAccountAndResumeSync(request:)``). `deletionEpoch` is
  /// the epoch the user's request was captured at; a deletion accepted after
  /// it voids the lift.
  func liftCloudDeletionPauseForExplicitReenable(deletionEpoch: UInt64) async {
    guard let controller = cloudSyncController, !isCloudDataDeletionRunning,
      cloudDataDeletionEpoch == deletionEpoch,
      await controller.currentPauseReason() == .userDeletedZone
    else { return }
    await applyCloudSyncControllerState(
      (try? await controller.reenableAfterCloudDeletion()) ?? .failed("reenable failed"))
  }
}
