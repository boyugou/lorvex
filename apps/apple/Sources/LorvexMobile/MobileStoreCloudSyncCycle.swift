import Foundation
import LorvexCloudSync
import LorvexCore

/// Running one explicit Cloud Sync pass and recording what its report means.
///
/// The controller's engine also syncs on its own (a push, the system
/// scheduler, a retry); those passes arrive through
/// ``handleEngineCloudSyncReport(_:)``. Both paths record a completed pass the
/// same way.
extension MobileStore {
  /// Run one sync pass off the main actor: fetch what changed in iCloud, then
  /// send what this device queued. Best-effort: account gates, pauses, and
  /// errors are recorded in the status fields and never thrown. A no-op while
  /// sync is off or a confirmed import is writing.
  ///
  /// Overlapping triggers coalesce into one serialized pass loop. A trigger
  /// that arrives mid-pass arms a trailing pass and awaits the combined result,
  /// so a foreground refresh never mistakes an in-flight apply for `.noData`.
  ///
  /// No pass starts while a data import runs, except the import's own pass
  /// before it writes (`forDataImport`).
  @discardableResult
  func runCloudSyncCycle(forDataImport: Bool = false) async -> MobileCloudSyncLifecycleResult {
    let outcome = await cloudSyncCycleFlight.run(body: {
      await runCloudSyncCycleBody(forDataImport: forDataImport)
    })
    // A pass that could not run (sync off, account unavailable, paused, or a
    // thrown transport error) leaves the previous report standing.
    if let report = outcome.report {
      lastCloudSyncCycleReport = report
    }
    return outcome.lifecycle
  }

  private func runCloudSyncCycleBody(forDataImport: Bool) async -> MobileCloudSyncCycleOutcome {
    guard forDataImport || !isDataImportRunning, cloudSyncMode == .live, let cloudSyncController else {
      return MobileCloudSyncCycleOutcome(lifecycle: .noData, report: nil)
    }
    // Stopped, failed, or waiting for iCloud: evaluate again, so a transient
    // failure or a returning account recovers on the next pass. A pause waits
    // for the user.
    switch await cloudSyncController.state {
    case .running, .paused: break
    case .stopped, .unavailable, .failed:
      await applyCloudSyncControllerState(await cloudSyncController.start())
    }
    do {
      let report = try await Task.detached(priority: .utility) {
        let signpost = LorvexSignpost.begin(.cloudSync)
        defer { LorvexSignpost.end(signpost) }
        return try await cloudSyncController.syncNow()
      }.value
      guard let report else {
        await applyCloudSyncControllerState(await cloudSyncController.state)
        return MobileCloudSyncCycleOutcome(lifecycle: .noData, report: nil)
      }
      recordCompletedCloudSyncPass(report)
      return MobileCloudSyncCycleOutcome(
        lifecycle: Self.cloudSyncCycleMadeDataAvailable(report) ? .newData : .noData,
        report: report)
    } catch {
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        for: error, source: "ios.cloud_sync.cycle")
      await applyCloudSyncControllerState(await cloudSyncController.state)
      return MobileCloudSyncCycleOutcome(lifecycle: .failed, report: nil)
    }
  }

  /// Adopts a pass the engine ran on its own. When a refresh is running beside
  /// it, that refresh may already have read some surfaces from the pre-apply
  /// state, so one trailing refresh pass re-reads everything instead.
  func handleEngineCloudSyncReport(_ report: CloudSyncCycleReport) async {
    recordCompletedCloudSyncPass(report)
    lastCloudSyncCycleReport = report
    guard Self.cloudSyncCycleMadeDataAvailable(report) else { return }
    if isRefreshing {
      refreshFlight.requestRerun()
    } else {
      await reloadInboundSurfacesIfNeeded(after: .newData)
    }
  }

  /// Records a pass that completed: its time, and the one condition a
  /// completed pass still reports to the user — a full iCloud storage.
  private func recordCompletedCloudSyncPass(_ report: CloudSyncCycleReport) {
    cloudKitAccountAvailability = .available
    cloudSyncPauseReason = nil
    lastCloudSyncRemoteChangeSucceededAt = now()
    lastCloudSyncRemoteChangeErrorMessage =
      report.iCloudStorageFull
      ? String(
        localized: "settings.sync.storage_full",
        defaultValue: "Your iCloud storage is full. Lorvex will finish syncing when there’s space.",
        table: "Localizable", bundle: MobileL10n.bundle)
      : nil
  }

  /// Publishes the controller's state to the status surfaces. A failure's
  /// technical detail goes to the diagnostics log; the status row gets the
  /// user-facing message.
  func applyCloudSyncControllerState(_ state: CloudSyncControllerState) async {
    switch state {
    case .stopped:
      break
    case .running:
      cloudKitAccountAvailability = .available
      cloudSyncPauseReason = nil
    case .unavailable(let availability):
      cloudKitAccountAvailability = availability
    case .paused(let reason):
      cloudKitAccountAvailability = .available
      cloudSyncPauseReason = reason
    case .failed(let detail):
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        forMessage: detail, source: "ios.cloud_sync.controller")
    }
  }

  static func cloudSyncCycleMadeDataAvailable(_ report: CloudSyncCycleReport) -> Bool {
    report.pushedRecordCount > 0
      || report.fetchedRecordCount > 0
      || report.inbound.applied > 0
      || report.inbound.deferred > 0
      || report.inbound.remapped > 0
      || report.inbound.drainReplayed > 0
  }
}
