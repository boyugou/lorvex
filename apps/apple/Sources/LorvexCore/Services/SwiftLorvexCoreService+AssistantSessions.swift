import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension SwiftLorvexCoreService {
  // MARK: - Assistant sessions

  /// See ``LorvexSystemServicing/recordAssistantActivity(clientName:clientTitle:clientVersion:)``.
  /// Runs as local maintenance: no HLC, no outbox row, no changelog entry, and
  /// no device identity is created for it.
  public func recordAssistantActivity(
    clientName: String, clientTitle: String?, clientVersion: String?
  ) async throws {
    let at = SyncTimestampFormat.formatSyncTimestamp(wallClock())
    try withLocalMaintenanceWrite { db in
      try AssistantSessionsRepo.recordActivity(
        db, name: clientName, title: clientTitle, version: clientVersion, at: at)
    }
  }

  public func loadAssistantSessions() async throws -> [AssistantSessionRecord] {
    try read { db in
      try AssistantSessionsRepo.read(db).compactMap { row in
        guard let at = SyncTimestamp.parse(row.lastActiveAt)?.date else { return nil }
        return AssistantSessionRecord(
          clientName: row.name, clientTitle: row.title, clientVersion: row.version,
          lastActiveAt: at)
      }
    }
  }
}
