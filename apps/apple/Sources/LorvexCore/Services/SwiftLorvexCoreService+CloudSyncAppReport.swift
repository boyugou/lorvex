import Foundation
import GRDB

/// What the app on this device last reported about iCloud sync.
///
/// Sync runs only inside the main app (`CloudSyncController`), so a helper
/// that reads the shared database (the MCP host) cannot see whether changes are
/// reaching other devices. The app records its sync mode and state here after
/// each pass, and the helper reads it back. Device-local: it lives in
/// `device_state` and never syncs.
public struct CloudSyncAppReport: Codable, Equatable, Sendable {
  /// `live` while iCloud sync is on in Settings, `off` otherwise.
  public var mode: String
  /// The transport's state: `running`, `stopped`, `unavailable` (no usable
  /// iCloud account), `paused` (waiting for the user), or `failed`.
  public var state: String
  /// When a sync pass last completed, in the sync timestamp format; nil when
  /// none has completed since the app started.
  public var lastCompletedPassAt: String?
  /// When the app wrote this report.
  public var reportedAt: String

  public init(mode: String, state: String, lastCompletedPassAt: String?, reportedAt: String) {
    self.mode = mode
    self.state = state
    self.lastCompletedPassAt = lastCompletedPassAt
    self.reportedAt = reportedAt
  }

  /// Whether `other` says the same thing, apart from when it was written.
  public func reportsTheSame(as other: CloudSyncAppReport) -> Bool {
    mode == other.mode && state == other.state
      && lastCompletedPassAt == other.lastCompletedPassAt
  }
}

/// Recording and reading ``CloudSyncAppReport``.
public protocol CloudSyncAppReporting: Sendable {
  func recordCloudSyncAppReport(_ report: CloudSyncAppReport) async throws
  func loadCloudSyncAppReport() async throws -> CloudSyncAppReport?
}

extension SwiftLorvexCoreService: CloudSyncAppReporting {
  static let cloudSyncAppReportKey = "cloud_sync_app_report"

  /// Records the report as local bookkeeping: no change signal and no change
  /// sequence, so writing it never makes another surface refresh.
  public func recordCloudSyncAppReport(_ report: CloudSyncAppReport) async throws {
    let data = try JSONEncoder().encode(report)
    let value = String(decoding: data, as: UTF8.self)
    try withLocalMaintenanceWrite { db in
      try db.execute(
        sql: """
          INSERT INTO device_state (key, value) VALUES (?, ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value
          """,
        arguments: [Self.cloudSyncAppReportKey, value])
    }
  }

  /// The last report, or nil when the app has not written one or it cannot
  /// be read.
  public func loadCloudSyncAppReport() async throws -> CloudSyncAppReport? {
    let stored = try read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM device_state WHERE key = ?",
        arguments: [Self.cloudSyncAppReportKey])
    }
    guard let stored, let data = stored.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(CloudSyncAppReport.self, from: data)
  }
}
