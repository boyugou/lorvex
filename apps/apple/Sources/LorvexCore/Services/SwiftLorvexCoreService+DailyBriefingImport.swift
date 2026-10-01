import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Restoring exported daily briefings. A briefing is a singleton per date, so
/// the exported date is its identity; the restored row keeps the exported
/// text, timezone, and timestamps and is stamped with a fresh local version.
extension SwiftLorvexCoreService {
  public func importDailyBriefing(_ briefing: ExportDailyBriefing) async throws {
    let date = try Self.importedBriefingDate(briefing.date)
    let now = SyncTimestampFormat.syncTimestampNow()
    try withWrite { db, hlc, deviceId in
      try self.writeImportedDailyBriefingInTx(
        db, hlc: hlc, deviceId: deviceId, date: date, briefing: briefing, now: now)
    }
  }

  public func importDailyBriefingIfAbsent(_ briefing: ExportDailyBriefing) async throws -> Bool {
    let date = try Self.importedBriefingDate(briefing.date)
    let now = SyncTimestampFormat.syncTimestampNow()
    return try withWrite { db, hlc, deviceId in
      // A non-destructive restore skips a date a concurrent write already holds
      // (no overwrite) and one whose briefing the user cleared after the backup
      // (no resurrection at a fresh dominating import version). Both checks
      // share this write lock with the write.
      if try DailyBriefingRepo.briefing(db, date: date) != nil {
        return false
      }
      if try Tombstone.isTombstoned(db, entityType: EntityName.dailyBriefing, entityId: date) {
        return false
      }
      try self.writeImportedDailyBriefingInTx(
        db, hlc: hlc, deviceId: deviceId, date: date, briefing: briefing, now: now)
      return true
    }
  }

  /// Upsert one imported briefing and enqueue its sync envelope inside the
  /// caller's transaction. The text must be non-blank and fit the same payload
  /// budget as an assistant-written briefing. A briefing without a timezone
  /// takes the store's anchored timezone. The write is version-gated: a refused
  /// upsert throws ``StoreError/staleVersion(entity:id:)`` so the write retry
  /// re-runs it at a dominating version instead of regressing a newer row.
  func writeImportedDailyBriefingInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, date: String,
    briefing: ExportDailyBriefing, now: String
  ) throws {
    guard let text = briefing.briefing.trimmedNilIfEmpty else {
      throw LorvexCoreError.validation(
        field: "briefing", message: "A daily briefing must not be blank.")
    }
    if case .failure = PayloadByteBudget.validateEscapedBudget(
      text, field: "briefing", budget: PayloadByteBudget.dayPlanTextEscapedBytes)
    {
      throw LorvexCoreError.validation(
        field: "briefing",
        message: "The daily briefing exceeds the maximum stored size of "
          + "\(PayloadByteBudget.dayPlanTextEscapedBytes) bytes.")
    }
    let createdAt = try Self.canonicalImportTimestamp(
      briefing.createdAt, field: "daily briefing createdAt", fallback: now)
    let updatedAt = try Self.canonicalImportTimestamp(
      briefing.updatedAt, field: "daily briefing updatedAt", fallback: now)
    let timezone =
      try briefing.timezone.trimmedNilIfEmpty ?? WorkflowTimezone.anchoredTimezoneName(db)
    let applied = try DailyBriefingRepo.syncUpsertBriefing(
      db, date: date, briefing: text, timezone: timezone, version: hlc.nextVersionString(),
      createdAt: createdAt, updatedAt: updatedAt, versionCmp: ">")
    guard applied else {
      throw StoreError.staleVersion(entity: EntityName.dailyBriefing, id: date)
    }
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .dailyBriefing, entityId: date)
  }

  private static func importedBriefingDate(_ raw: String) throws -> String {
    guard
      case .success(let date) = IsoDate.parseIsoDate(
        raw.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      throw LorvexCoreError.validation(
        field: "date", message: "A daily briefing date must be a valid YYYY-MM-DD date.")
    }
    return date.canonicalString
  }
}
