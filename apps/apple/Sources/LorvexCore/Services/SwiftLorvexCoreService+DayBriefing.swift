import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// The day's briefing: the assistant's short note on one day — what matters and
/// why, what is at risk, what it moved. Each day's briefing is one row of the
/// `daily_briefings` table, and a day without one has no row. Every surface
/// shows it read-only; only the assistant writes it, through
/// ``setDailyBriefingForMcp(date:briefing:)``.
extension SwiftLorvexCoreService {
  /// The briefing stored for `date`, trimmed, or nil when the day has none.
  static func dayBriefing(_ db: Database, date: String) throws -> String? {
    try DailyBriefingRepo.briefing(db, date: date).trimmedNilIfEmpty
  }

  public func setDailyBriefingForMcp(date: String, briefing: String?) async throws
    -> McpDailyBriefingReceipt
  {
    try writeDailyBriefing(date: date, briefing: briefing)
  }

  /// Store `briefing` (trimmed) as the briefing for `date`, or delete the
  /// day's briefing when it is nil or blank. Writing the briefing already
  /// there, or clearing an absent one, changes nothing: no envelope and no
  /// changelog row.
  private func writeDailyBriefing(date: String, briefing: String?) throws
    -> McpDailyBriefingReceipt
  {
    let day = try Self.canonicalDay(date)
    let text = briefing.trimmedNilIfEmpty
    return try withWrite { db, hlc, deviceId in
      let previous = try Self.dayBriefing(db, date: day)
      guard text != previous else {
        return McpDailyBriefingReceipt(date: day, briefing: previous, previous: previous)
      }
      let before = try Self.payloadIfPresent(
        db, entityType: EntityName.dailyBriefing, entityId: day)
      if let text {
        try DailyBriefingRepo.upsertBriefing(
          db, date: day, briefing: text,
          timezone: try WorkflowTimezone.anchoredTimezoneName(db),
          version: hlc.nextVersionString(), now: SyncTimestampFormat.syncTimestampNow())
        try self.enqueueUpsert(
          db, hlc: hlc, deviceId: deviceId, kind: .dailyBriefing, entityId: day)
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opUpsert, entityType: EntityName.dailyBriefing,
            entityId: day, summary: "Set the briefing for \(day)",
            before: before,
            after: try OutboxEnqueue.readEntityPayloadSnapshot(
              db, entityType: EntityName.dailyBriefing, entityId: day)),
          deviceId: deviceId)
      } else if let before {
        try DailyBriefingRepo.deleteBriefing(db, date: day)
        try self.enqueueDelete(
          db, hlc: hlc, deviceId: deviceId, kind: .dailyBriefing, entityId: day,
          payload: before)
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opDelete, entityType: EntityName.dailyBriefing,
            entityId: day, summary: "Cleared the briefing for \(day)",
            before: before),
          deviceId: deviceId)
      }
      return McpDailyBriefingReceipt(date: day, briefing: text, previous: previous)
    }
  }

  /// The entity's sync payload, or nil when no row exists: the before-state a
  /// write records on its changelog row, so the log shows what the change
  /// replaced.
  static func payloadIfPresent(_ db: Database, entityType: String, entityId: String) throws
    -> JSONValue?
  {
    do {
      return try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: entityType, entityId: entityId)
    } catch EnqueueError.entityNotFound {
      return nil
    }
  }
}
