import Foundation
import LorvexCore

extension AppStore {
  /// Applies a confirmed restore, then refreshes every surface.
  ///
  /// The importer commits record by record, each in its own transaction, so a
  /// sync apply that lands meanwhile interleaves between records and
  /// last-writer-wins settles any overlap. With sync live, one best-effort
  /// sync pass runs first so the importer's skip-if-present decisions see the
  /// other devices' latest rows; the import is local and proceeds when that
  /// pass fails. The imported rows upload with the next pass.
  func applyDataImport(
    plan: LorvexImportPlan,
    decoded: LorvexDataImporter.DecodedImport
  ) async throws -> LorvexImportSummary {
    guard !isDataImportRunning, !isLocalFactoryResetRunning, !isCloudDataDeletionRunning else {
      throw LorvexDataImporter.BusyError()
    }
    isDataImportRunning = true
    defer { isDataImportRunning = false }
    if cloudSyncMode == .live, let cloudSyncController,
      let report = try? await cloudSyncController.syncNow()
    {
      await handleCompletedCloudSyncReport(report)
    }
    let summary = await LorvexDataImporter.apply(plan: plan, decoded: decoded, using: core)
    if summary.totalImported > 0 {
      DatabaseChangeSignal.broadcastCommittedChangeInProcess(origin: self)
    }
    await refreshAndWaitForLatest()
    return summary
  }
}
