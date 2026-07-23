import Foundation
import LorvexCloudSync

extension MobileStore {
  /// Replaces the single main-app retry wake. The sleeping task owns no
  /// CloudKit or database capability; after waking it re-enters the normal
  /// coordinator/store gates and then adopts any inbound rows into the UI.
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
      let result = await self.runCloudSyncCycle()
      await self.reloadInboundSurfacesIfNeeded(after: result)
    }
  }

  func cancelCloudSyncRetryWake() {
    cloudSyncRetryWakeGeneration &+= 1
    cloudSyncRetryWakeTask?.cancel()
    cloudSyncRetryWakeTask = nil
  }
}
