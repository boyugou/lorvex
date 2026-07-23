import Foundation
import LorvexCloudSync
import LorvexCore

extension AppStore {
  /// Apply a confirmed restore through the runtime's CloudSync boundary, then
  /// refresh every derived surface only after the coordinator gate is released.
  /// The importer remains record-atomic rather than archive-atomic; this wider
  /// boundary only prevents CloudKit inbound work from interleaving with its
  /// sequence of presence/tombstone decisions.
  func applyDataImport(
    plan: LorvexImportPlan,
    decoded: LorvexDataImporter.DecodedImport
  ) async throws -> LorvexImportSummary {
    guard !isDataImportRunning else {
      throw CloudSyncDataImportBoundary.BoundaryError.importAlreadyRunning
    }
    guard !isLocalFactoryResetRunning, !isCloudDataDeletionRunning,
      !isCloudDeletionMaintenanceRunning
    else {
      throw CloudSyncDataImportBoundary.BoundaryError.dataMaintenanceRunning
    }
    isDataImportRunning = true
    defer { isDataImportRunning = false }
    var preflightStartedAt: Date?
    do {
      preflightStartedAt = try CloudSyncDataImportBoundary.beginLivePreflightIfNeeded(
        mode: cloudSyncMode, pacing: &cloudSyncPacing, now: now())
      let result = try await CloudSyncDataImportBoundary.apply(
        plan: plan,
        decoded: decoded,
        using: core,
        mode: cloudSyncMode,
        liveCoordinator: cloudSyncCoordinator,
        maintenanceCoordinator: cloudDataMaintenanceCoordinator)
      await recordDataImportCloudPreflightSuccess(
        result, startedAt: preflightStartedAt)
      if result.summary.totalImported > 0 {
        DatabaseChangeSignal.broadcastCommittedChangeInProcess(origin: self)
      }
      await refreshAndWaitForLatest()
      return result.summary
    } catch {
      // A failed terminal drain may still have committed a safe inbound prefix.
      // Reload local surfaces, but never retry the user's import implicitly.
      await recordDataImportCloudPreflightFailure(error, startedAt: preflightStartedAt)
      await refreshAndWaitForLatest()
      throw error
    }
  }

  private func recordDataImportCloudPreflightSuccess(
    _ result: CloudSyncDataImportBoundary.Result,
    startedAt: Date?
  ) async {
    guard let report = result.preImportSyncReport, let startedAt else { return }
    cloudKitAccountAvailability = .available
    cloudSyncPauseReason = nil
    lastCloudSyncCycleReport = report
    publishDataImportInboundChangeIfNeeded(report)

    if let warning = result.postTerminalSyncFailure {
      if let retryAfter = warning.serverRetryAfter {
        cloudSyncPacing.recordServerThrottle(retryAfter: retryAfter, now: startedAt)
      }
      cloudSyncPacing.recordFailure()
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        forMessage: warning.errorDescription,
        source: "macos.cloud_sync.import_post_terminal")
    } else if Self.cloudSyncCycleMadeNoProgress(report) {
      cloudSyncPacing.recordFailure()
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        forMessage: "CloudKit push failed without making progress",
        source: "macos.cloud_sync.import_preflight")
    } else {
      cloudSyncPacing.recordSuccess()
      lastCloudSyncRemoteChangeSucceededAt = startedAt
      lastCloudSyncRemoteChangeErrorMessage = nil
    }
  }

  private func recordDataImportCloudPreflightFailure(
    _ error: any Error,
    startedAt: Date?
  ) async {
    guard let startedAt else { return }
    if let partial = error as? CloudSyncPartialCycleFailure {
      lastCloudSyncCycleReport = partial.partialReport
      publishDataImportInboundChangeIfNeeded(partial.partialReport)
    } else if case .terminalBoundaryNotReached(let report) =
      error as? CloudSyncTerminalInboundDrainError
    {
      lastCloudSyncCycleReport = report
      publishDataImportInboundChangeIfNeeded(report)
    } else if case .inboundStateIncomplete(let report, _, _) =
      error as? CloudSyncTerminalInboundDrainError
    {
      lastCloudSyncCycleReport = report
      publishDataImportInboundChangeIfNeeded(report)
    }
    guard !CloudSyncDataImportBoundary.isCancellation(error) else { return }
    if case .accountUnavailable(let availability) =
      error as? CloudSyncTerminalInboundDrainError
    {
      cloudKitAccountAvailability = availability
    }
    if case .syncPaused(let reason) = error as? CloudSyncTerminalInboundDrainError {
      cloudSyncPauseReason = reason
    } else {
      await refreshCloudSyncPauseReason()
    }
    if let retryAfter = CloudSyncTransientClassifier.serverRetryAfter(error) {
      cloudSyncPacing.recordServerThrottle(retryAfter: retryAfter, now: startedAt)
    }
    cloudSyncPacing.recordFailure()
    lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
      for: error, source: "macos.cloud_sync.import_preflight")
  }

  private func publishDataImportInboundChangeIfNeeded(_ report: CloudSyncCycleReport) {
    guard !report.inbound.appliedEntityTypes.isEmpty else { return }
    DatabaseChangeSignal.broadcastCommittedChangeInProcess(origin: self)
  }
}
