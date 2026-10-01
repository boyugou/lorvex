import Foundation
import GRDB
import LorvexDomain

/// The `daily_briefings` table: the assistant's short note on one day, keyed by
/// its `YYYY-MM-DD` date. A day without a briefing has no row, and the stored
/// text is never blank.
///
/// Local writers use ``upsertBriefing(_:date:briefing:timezone:version:now:)``
/// (the day's timezone is fixed when the row is created); sync apply uses
/// ``syncUpsertBriefing(_:date:briefing:timezone:version:createdAt:updatedAt:versionCmp:)``,
/// where the envelope is authoritative for every column.
public enum DailyBriefingRepo {
  /// The briefing stored for `date`, or nil when the day has none.
  public static func briefing(_ db: Database, date: String) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT briefing FROM daily_briefings WHERE date = ?", arguments: [date])
  }

  /// Create the briefing for `date`, or replace the text of the existing one.
  ///
  /// The text must be non-blank and fit the sync payload budget. An update
  /// keeps the row's timezone and is gated on `version` being newer than the
  /// stored one; a rejected update throws ``StoreError/staleVersion(entity:id:)``.
  public static func upsertBriefing(
    _ db: Database,
    date: String,
    briefing: String,
    timezone: String,
    version: String,
    now: String
  ) throws {
    guard !briefing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw StoreError.validation("a daily briefing must not be blank")
    }
    if case .failure = PayloadByteBudget.validateEscapedBudget(
      briefing, field: "briefing", budget: PayloadByteBudget.dayPlanTextEscapedBytes)
    {
      throw StoreError.validation(
        "a daily briefing exceeds the maximum stored size of "
          + "\(PayloadByteBudget.dayPlanTextEscapedBytes) bytes")
    }
    try db.execute(
      sql: """
        INSERT INTO daily_briefings (date, briefing, timezone, version, created_at, updated_at) \
        VALUES (?1, ?2, ?3, ?4, ?5, ?5) \
        ON CONFLICT(date) DO UPDATE SET \
           briefing = excluded.briefing, version = excluded.version, \
           updated_at = excluded.updated_at \
        WHERE excluded.version > daily_briefings.version
        """,
      arguments: [date, briefing, timezone, version, now])
    if db.changesCount == 0 {
      throw StoreError.staleVersion(entity: EntityName.dailyBriefing, id: date)
    }
  }

  /// Sync-mode upsert: full replacement from another device's envelope,
  /// including `timezone` and `created_at`. `versionCmp` is `">"` for normal
  /// sync or `">="` when equal-version acceptance is negotiated. Returns `true`
  /// when the version gate accepted the row.
  public static func syncUpsertBriefing(
    _ db: Database,
    date: String,
    briefing: String,
    timezone: String?,
    version: String,
    createdAt: String,
    updatedAt: String,
    versionCmp: String
  ) throws -> Bool {
    let op: String
    switch versionCmp {
    case ">": op = ">"
    case ">=": op = ">="
    default:
      throw DatabaseError(
        resultCode: .SQLITE_MISUSE,
        message: "syncUpsertBriefing: versionCmp must be \">\" or \">=\", got \(versionCmp)")
    }
    try db.execute(
      sql: """
        INSERT INTO daily_briefings (date, briefing, timezone, version, created_at, updated_at) \
        VALUES (?, ?, ?, ?, ?, ?) \
        ON CONFLICT(date) DO UPDATE SET \
           briefing = excluded.briefing, timezone = excluded.timezone, \
           created_at = excluded.created_at, updated_at = excluded.updated_at, \
           version = excluded.version \
        WHERE excluded.version \(op) daily_briefings.version
        """,
      arguments: [date, briefing, timezone, version, createdAt, updatedAt])
    return db.changesCount > 0
  }

  /// Delete the briefing for `date`. Returns `true` when a row was deleted.
  @discardableResult
  public static func deleteBriefing(_ db: Database, date: String) throws -> Bool {
    try db.execute(sql: "DELETE FROM daily_briefings WHERE date = ?", arguments: [date])
    return db.changesCount > 0
  }
}
