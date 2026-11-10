import Foundation
import LorvexCloudSync
import LorvexCore

/// Telling the assistant, through the shared database, whether this Mac is
/// syncing (``CloudSyncAppReport``).
extension AppStore {
  /// How long a report that says the same thing stands before it is written
  /// again, so its `reportedAt` shows the app is still running.
  static let cloudSyncAppReportRefreshInterval: TimeInterval = 10 * 60

  /// Writes the sync mode, the transport's state, and when a pass last
  /// completed, when they changed or the last report has aged. Best-effort.
  func reportCloudSyncToAssistant() async {
    guard let reporter = core as? any CloudSyncAppReporting else { return }
    let state = await cloudSyncController?.state
    let report = CloudSyncAppReport(
      mode: cloudSyncMode == .live ? "live" : "off",
      state: Self.reportedCloudSyncState(state, mode: cloudSyncMode),
      lastCompletedPassAt: lastCloudSyncRemoteChangeSucceededAt.map(Self.reportTimestamp),
      reportedAt: Self.reportTimestamp(now()))
    if let last = lastCloudSyncAppReport, last.report.reportsTheSame(as: report),
      now().timeIntervalSince(last.at) < Self.cloudSyncAppReportRefreshInterval
    {
      return
    }
    do {
      try await reporter.recordCloudSyncAppReport(report)
      lastCloudSyncAppReport = (report, now())
    } catch {}
  }

  static func reportedCloudSyncState(
    _ state: CloudSyncControllerState?, mode: CloudSyncMode
  ) -> String {
    guard mode == .live, let state else { return "stopped" }
    switch state {
    case .stopped: return "stopped"
    case .unavailable: return "unavailable"
    case .paused: return "paused"
    case .failed: return "failed"
    case .running: return "running"
    }
  }

  static func reportTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
