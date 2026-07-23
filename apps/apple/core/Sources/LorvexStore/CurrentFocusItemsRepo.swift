import Foundation
import GRDB
import LorvexDomain

/// Outcome of a ``CurrentFocusItemsRepo/upsertCurrentFocusHeader`` call.
public enum UpsertOutcome: Sendable, Equatable {
  case created
  case updated
  /// Row existed but the LWW gate rejected the write (stale version);
  /// the on-disk row is unchanged.
  case lwwRejected
}

/// `current_focus` parent + `current_focus_items` child operations.
///
/// Local writers must use ``materializeFocusItemsWithHeaderBump`` so the
/// parent's `(version, updated_at)` advance in lockstep with the rebuilt
/// children. Sync-apply paths use ``materializeFocusItems`` after writing
/// the parent header from the envelope payload (timezone immutability on
/// local writes; the envelope is authoritative on sync apply).
public enum CurrentFocusItemsRepo {

  // -- parent: current_focus ----------------------------------------------

  /// Create or update the `current_focus` parent row.
  ///
  /// Timezone immutability: on UPDATE the existing timezone is preserved;
  /// the `timezone` argument is only used on INSERT. The UPDATE branch is
  /// LWW-gated on `?version > current_focus.version`; the three outcomes
  /// (``UpsertOutcome``) distinguish fresh insert / accepted update /
  /// stale-version no-op so callers know whether the write landed.
  public static func upsertCurrentFocusHeader(
    _ db: Database,
    date: String,
    briefing: String?,
    timezone: String,
    version: String,
    now: String
  ) throws -> UpsertOutcome {
    // Local-write funnel only (sync applies through syncUpsertCurrentFocus, and
    // inbound size is bounded by the wire cap): the briefing byte budget keeps
    // a locally-authored current_focus payload provably under the sync cap.
    if let briefing,
      case .failure = PayloadByteBudget.validateEscapedBudget(
        briefing, field: "briefing", budget: PayloadByteBudget.dayPlanTextEscapedBytes)
    {
      throw StoreError.validation(
        "current_focus.briefing exceeds the maximum stored size of "
          + "\(PayloadByteBudget.dayPlanTextEscapedBytes) bytes")
    }
    let exists =
      try Int.fetchOne(
        db, sql: "SELECT 1 FROM current_focus WHERE date = ?", arguments: [date]) != nil

    if exists {
      try db.execute(
        sql: """
          UPDATE current_focus SET briefing = ?, version = ?, updated_at = ? \
          WHERE date = ? AND ? > version
          """,
        arguments: [briefing, version, now, date, version])
      return db.changesCount == 0 ? .lwwRejected : .updated
    }

    try db.execute(
      sql: """
        INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at) \
        VALUES (?, ?, ?, ?, ?, ?)
        """,
      arguments: [date, briefing, timezone, version, now, now])
    return .created
  }

  /// Sync-mode upsert: full-entity replacement from another device's
  /// envelope. Overwrites `timezone` and `created_at` because the remote
  /// envelope is authoritative. `versionCmp` is `">"` for normal sync or
  /// `">="` when capability negotiation allows equal-version acceptance.
  /// Returns `true` when the version check passed.
  public static func syncUpsertCurrentFocus(
    _ db: Database,
    date: String,
    briefing: String?,
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
        message:
          "syncUpsertCurrentFocus: versionCmp must be \">\" or \">=\", got \(versionCmp)")
    }
    let sql = """
      INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at) \
      VALUES (?, ?, ?, ?, ?, ?) \
      ON CONFLICT(date) DO UPDATE SET \
         briefing = excluded.briefing, timezone = excluded.timezone, \
         created_at = excluded.created_at, updated_at = excluded.updated_at, \
         version = excluded.version \
      WHERE excluded.version \(op) current_focus.version
      """
    try db.execute(
      sql: sql,
      arguments: [date, briefing, timezone, version, createdAt, updatedAt])
    return db.changesCount > 0
  }

  /// Delete the `current_focus` parent row. CASCADE removes child items.
  /// Returns `true` if a row was deleted.
  @discardableResult
  public static func deleteCurrentFocus(_ db: Database, date: String) throws -> Bool {
    try db.execute(
      sql: "DELETE FROM current_focus WHERE date = ?", arguments: [date])
    return db.changesCount > 0
  }

  // -- child: current_focus_items -----------------------------------------

  /// Materialize focus items for a given date. Deletes all existing items,
  /// then inserts `taskIds` with sequential positions. Silently deduplicates
  /// (first occurrence wins).
  ///
  /// Sync-apply paths only. Local writers must use
  /// ``materializeFocusItemsWithHeaderBump`` so the parent header stays
  /// in lockstep with the rebuilt children.
  public static func materializeFocusItems(
    _ db: Database, date: String, taskIds: [String]
  ) throws {
    try db.execute(
      sql: "DELETE FROM current_focus_items WHERE date = ?", arguments: [date])
    var seen = Set<String>()
    var position: Int64 = 0
    for taskId in taskIds {
      if seen.insert(taskId).inserted {
        try db.execute(
          sql: """
            INSERT INTO current_focus_items (date, position, task_id) \
            VALUES (?, ?, ?)
            """,
          arguments: [date, position, taskId])
        position += 1
      }
    }
  }

  /// Local-writer variant of ``materializeFocusItems`` that bumps the
  /// parent `current_focus.{version, updated_at}` in the same call.
  ///
  /// LWW gate is `>=` so the canonical "upsert header at V, then rebuild
  /// children at V" orchestration succeeds as a benign version re-stamp.
  /// A strictly-older `version` is rejected with
  /// ``StoreError/staleVersion(entity:id:)``; missing parent row also
  /// surfaces as `.staleVersion` so child rows never orphan.
  public static func materializeFocusItemsWithHeaderBump(
    _ db: Database, date: String, taskIds: [String], version: String, now: String
  ) throws {
    // Local-write funnel only (sync rebuilds children via materializeFocusItems
    // directly): the item-count cap keeps a locally-authored current_focus
    // payload provably under the sync byte cap (PayloadByteBudget).
    guard taskIds.count <= PayloadByteBudget.maxFocusTasks else {
      throw StoreError.validation(
        "a focus plan holds at most \(PayloadByteBudget.maxFocusTasks) tasks "
          + "(got \(taskIds.count))")
    }
    try db.execute(
      sql: """
        UPDATE current_focus SET version = ?, updated_at = ? \
        WHERE date = ? AND ? >= version
        """,
      arguments: [version, now, date, version])
    if db.changesCount == 0 {
      throw StoreError.staleVersion(entity: "current_focus", id: date)
    }
    try materializeFocusItems(db, date: date, taskIds: taskIds)
  }

  /// Query `task_id`s from the child sub-table for `date`, position-ordered.
  public static func queryFocusTaskIds(
    _ db: Database, date: String
  ) throws -> [String] {
    try String.fetchAll(
      db,
      sql: """
        SELECT task_id FROM current_focus_items WHERE date = ? \
        ORDER BY position ASC
        """,
      arguments: [date])
  }
}
