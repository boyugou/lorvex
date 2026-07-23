import Foundation
import LorvexCloudSync

extension AppStore {
  /// Replaces the single app-owned retry wake with the deadline implied by the
  /// latest completed/failed cycle. Sleeping never holds the coordinator gate;
  /// the wake re-enters the ordinary serialized cycle and all account,
  /// generation, pacing, and mode guards are evaluated again.
  func updateCloudSyncRetryWake(
    after report: CloudSyncCycleReport?,
    retryCurrentWork: Bool
  ) {
    guard cloudSyncMode == .live, cloudSyncCoordinator != nil else {
      cancelCloudSyncRetryWake()
      return
    }
    let current = now()
    let wakeAt = cloudSyncPacing.automaticRetryWakeAt(
      now: current,
      retryCurrentWork: retryCurrentWork || (report?.failedPushCount ?? 0) > 0,
      continueDraining: report?.moreWorkComing == true,
      nextDeferredRetryAt: report?.nextDeferredRetryAt)
    guard let wakeAt else {
      cancelCloudSyncRetryWake()
      return
    }

    cloudSyncRetryWakeGeneration &+= 1
    let generation = cloudSyncRetryWakeGeneration
    cloudSyncRetryWakeTask?.cancel()
    let delay = max(0, wakeAt.timeIntervalSince(current))
    let sleep = cloudSyncRetrySleep
    cloudSyncRetryWakeTask = Task { @MainActor [weak self] in
      do {
        try await sleep(delay)
      } catch {
        return
      }
      guard !Task.isCancelled, let self,
        self.cloudSyncRetryWakeGeneration == generation
      else { return }
      self.cloudSyncRetryWakeTask = nil
      await self.runCloudSyncCycle()
    }
  }

  func cancelCloudSyncRetryWake() {
    cloudSyncRetryWakeGeneration &+= 1
    cloudSyncRetryWakeTask?.cancel()
    cloudSyncRetryWakeTask = nil
  }
}
