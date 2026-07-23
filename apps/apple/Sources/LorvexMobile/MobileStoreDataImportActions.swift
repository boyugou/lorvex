import Foundation
import LorvexCloudSync
import LorvexCore

extension MobileStore {
  /// Apply a confirmed restore through the shared CloudSync boundary. A queued
  /// mode change is linearized after the import gate releases but before the
  /// final refresh, so an Off request cannot be overtaken by an automatic push
  /// of the newly imported rows.
  func applyDataImport(
    plan: LorvexImportPlan,
    decoded: LorvexDataImporter.DecodedImport
  ) async throws -> LorvexImportSummary {
    guard !isDataImportRunning else {
      throw CloudSyncDataImportBoundary.BoundaryError.importAlreadyRunning
    }
    guard !isSettingCloudSyncMode, !isCloudDataDeletionRunning,
      !isCloudDeletionMaintenanceRunning
    else {
      throw CloudSyncDataImportBoundary.BoundaryError.dataMaintenanceRunning
    }
    isDataImportRunning = true
    var preflightStartedAt: Date?
    do {
      await settleRuntimeBeforeDataImport()
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
      await finishDataImportOperation()
      return result.summary
    } catch {
      // A failed drain can carry an already-committed inbound prefix. Refresh
      // it into the visible snapshot, but do not retry the restore implicitly.
      await recordDataImportCloudPreflightFailure(error, startedAt: preflightStartedAt)
      await finishDataImportOperation()
      throw error
    }
  }

  /// Establish the import intent on the main actor, then join any cycle that
  /// crossed its entry guard before that intent existed. A refresh awaiting the
  /// same cycle is joined as well. Only after both flights settle do we apply a
  /// queued consent mode, so an old Live task can never acquire the coordinator
  /// behind the import and upload restored rows before a requested Off lands.
  private func settleRuntimeBeforeDataImport() async {
    _ = await runCloudSyncCycle()
    if isRefreshing { _ = await refresh() }
    await applyPendingCloudSyncModeIfNeeded(allowDuringDataImport: true)
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
        source: "ios.cloud_sync.import_post_terminal")
    } else if Self.cloudSyncCycleMadeNoProgress(report) {
      cloudSyncPacing.recordFailure()
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        forMessage: "CloudKit push failed without making progress",
        source: "ios.cloud_sync.import_preflight")
    } else {
      cloudSyncPacing.recordSuccess()
      cloudSyncSuccessfulCycleGeneration &+= 1
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
      for: error, source: "ios.cloud_sync.import_preflight")
  }

  private func publishDataImportInboundChangeIfNeeded(_ report: CloudSyncCycleReport) {
    guard !report.inbound.appliedEntityTypes.isEmpty else { return }
    DatabaseChangeSignal.broadcastCommittedChangeInProcess(origin: self)
  }

  private func finishDataImportOperation() async {
    // Honor a mode request captured while the import held the coordinator gate.
    // `refresh()` is deliberately local-only while the import fence is raised,
    // so a later Off request arriving during its fan-out cannot be overtaken by
    // an upload of the newly imported rows.
    await applyPendingCloudSyncModeIfNeeded(allowDuringDataImport: true)
    let localRefresh = await refresh()
    isDataImportRunning = false
    // A request may have arrived during the local fan-out itself. Apply it
    // before any subscription or cycle can observe the imported outbox.
    await applyPendingCloudSyncModeIfNeeded()
    guard localRefresh != .failed, cloudSyncMode == .live else { return }
    await registerCloudSyncSubscriptionIfNeeded()
    let syncResult = await runCloudSyncCycle()
    await reloadInboundSurfacesIfNeeded(after: syncResult)
  }
}
