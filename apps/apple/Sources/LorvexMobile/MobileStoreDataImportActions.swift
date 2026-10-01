import Foundation
import LorvexCore

extension MobileStore {
  /// Applies a confirmed restore, then refreshes every surface.
  ///
  /// The importer commits record by record, each in its own transaction, so a
  /// sync apply that lands meanwhile interleaves between records and
  /// last-writer-wins settles any overlap. With sync live, one best-effort
  /// pass runs first so the importer's skip-if-present decisions see the other
  /// devices' latest rows; the import is local and proceeds when that pass
  /// fails. One more pass at the end uploads the imported rows.
  func applyDataImport(
    plan: LorvexImportPlan,
    decoded: LorvexDataImporter.DecodedImport
  ) async throws -> LorvexImportSummary {
    guard !isDataImportRunning, !isSettingCloudSyncMode, !isCloudDataDeletionRunning,
      !isLocalDataResetRunning
    else {
      throw LorvexDataImporter.BusyError()
    }
    // Busy from the first await, so a second import or a sync-mode change
    // cannot start while the pre-import pass runs.
    isDataImportRunning = true
    _ = await runCloudSyncCycle(forDataImport: true)
    let summary = await LorvexDataImporter.apply(plan: plan, decoded: decoded, using: core)
    if summary.totalImported > 0 {
      DatabaseChangeSignal.broadcastCommittedChangeInProcess(origin: self)
    }
    let localRefresh = await refresh()
    isDataImportRunning = false
    if localRefresh != .failed {
      let syncResult = await runCloudSyncCycle()
      await reloadInboundSurfacesIfNeeded(after: syncResult)
    }
    return summary
  }
}
