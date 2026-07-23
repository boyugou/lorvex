import Foundation
import GRDB
import LorvexDomain

/// Durable pending inbox — holds envelopes that cannot be applied immediately
/// (FK parent missing, or `payload_schema_version` ahead of local). Pending
/// entries are re-attempted after each successful batch apply.
///
/// This enum is the store-layer (raw-SQL CRUD) half of the pending-inbox
/// mechanism. It lives in `LorvexStore` because none of these functions need
/// `SyncEnvelope` — they operate purely on the `sync_pending_inbox` columns.
/// The apply-aware enqueue/drain half lives in `LorvexSync.PendingInboxDrain`.
public enum PendingInbox {
  /// Per-entry retry cap. An envelope whose FK target never arrives re-tries up
  /// to this many times before being shed (vs. waiting for the much heavier
  /// horizon-expiry reseed).
  public static let maxAttempts: Int64 = 50

  /// A row from the `sync_pending_inbox` table.
  public struct Entry: Sendable, Equatable {
    public var id: Int64
    public var envelopeJSON: String
    public var reason: String
    public var missingEntityType: String?
    public var missingEntityID: String?
    public var firstAttemptedAt: String
    public var lastAttemptedAt: String
    public var attemptCount: Int64

    init(_ row: Row) {
      id = row["id"]
      envelopeJSON = row["envelope"]
      reason = row["reason"]
      missingEntityType = row["missing_entity_type"]
      missingEntityID = row["missing_entity_id"]
      firstAttemptedAt = row["first_attempted_at"]
      lastAttemptedAt = row["last_attempted_at"]
      attemptCount = row["attempt_count"]
    }
  }

  // MARK: - reads

  /// Fetch a single pending row by id (drain loop re-reads each candidate just
  /// before processing so a side-effecting prior apply that removed the row is
  /// observed as `nil`).
  public static func pendingEntry(_ db: Database, id: Int64) throws -> Entry? {
    try Row.fetchOne(
      db,
      sql: """
        SELECT id, envelope, reason, missing_entity_type, missing_entity_id,
               first_attempted_at, last_attempted_at, attempt_count
        FROM sync_pending_inbox
        WHERE id = ?
        LIMIT 1
        """,
      arguments: [id]
    ).map(Entry.init)
  }

  /// Candidate ids for one drain pass, ordered `last_attempted_at ASC, id ASC`.
  public static func pendingEntryIDsForDrain(_ db: Database, limit: Int) throws -> [Int64] {
    try Int64.fetchAll(
      db,
      sql: """
        SELECT id
        FROM sync_pending_inbox
        ORDER BY last_attempted_at ASC, id ASC
        LIMIT ?
        """,
      arguments: [limit])
  }

  /// All pending envelopes for re-attempt, ordered `id ASC` (FIFO).
  public static func getAllPending(_ db: Database) throws -> [Entry] {
    try Row.fetchAll(
      db,
      sql: """
        SELECT id, envelope, reason, missing_entity_type, missing_entity_id,
               first_attempted_at, last_attempted_at, attempt_count
        FROM sync_pending_inbox
        ORDER BY id ASC
        """
    ).map(Entry.init)
  }

  /// Count of pending inbox entries.
  public static func countPending(_ db: Database) throws -> UInt64 {
    let count = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_pending_inbox") ?? 0
    return UInt64(count)
  }

  /// `true` iff any pending row is waiting on the just-created
  /// `(entityType, entityID)` FK target. The outbox-enqueue path calls this
  /// after a successful local Upsert so a child deferred for a missing parent
  /// gets a chance to drain in the same transaction the parent landed in.
  public static func hasPendingForTarget(
    _ db: Database, entityType: String, entityID: String
  ) throws -> Bool {
    try Int64.fetchOne(
      db,
      sql: """
        SELECT 1 FROM sync_pending_inbox \
        WHERE missing_entity_type = ? AND missing_entity_id = ? \
        LIMIT 1
        """,
      arguments: [entityType, entityID]) != nil
  }

  /// Read the post-write `attempt_count` for a pending row, or `nil` if the row
  /// has been deleted out from under the caller.
  public static func readAttemptCount(_ db: Database, id: Int64) throws -> Int64? {
    try Int64.fetchOne(
      db, sql: "SELECT attempt_count FROM sync_pending_inbox WHERE id = ?", arguments: [id])
  }

  // MARK: - writes

  /// Remove a successfully resolved pending entry.
  public static func removePending(_ db: Database, id: Int64) throws {
    try db.execute(sql: "DELETE FROM sync_pending_inbox WHERE id = ?", arguments: [id])
  }

  /// Delete pending-inbox rows older than `horizonDays` (their parent has not
  /// arrived in the horizon window and never will). Also GCs
  /// `sync_quarantine_blocklist` on the same horizon (best-effort — a failure
  /// there is swallowed via `error_logs`, not folded into the returned count).
  /// The sync retention caller must persist `reseed_required` before invoking
  /// this method whenever either table has expired rows, so removing durable
  /// unmaterialized debt cannot make terminal completeness appear healthy.
  /// Returns the number of pending-inbox rows deleted.
  ///
  /// `exemptReasonSQL`, when supplied, is a SQL boolean expression over the bare
  /// `reason` column selecting rows the reap must SKIP regardless of age. The
  /// retention sweep passes the budget-exempt HOLD predicate here: a parked
  /// forward-compat / standing-refusal envelope is the only local copy of its
  /// record (the sync transport's change token has already advanced past it),
  /// so deleting it at the horizon would silently lose newer-peer data. `nil`
  /// reaps every expired row.
  public static func gcExpiredEntries(
    _ db: Database, horizonDays: UInt32, exemptReasonSQL: String? = nil
  ) throws -> Int {
    let exemptClause = exemptReasonSQL.map { "AND NOT (\($0))" } ?? ""
    try db.execute(
      sql: """
        DELETE FROM sync_pending_inbox \
        WHERE first_attempted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?) \
        \(exemptClause)
        """,
      arguments: ["-\(horizonDays) days"])
    let deleted = db.changesCount
    do {
      try db.execute(
        sql: """
          DELETE FROM sync_quarantine_blocklist \
          WHERE quarantined_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
          """,
        arguments: ["-\(horizonDays) days"])
    } catch {
      ErrorLog.appendBestEffort(
        db, source: "sync.pending_inbox.blocklist_gc",
        message:
          "sync_quarantine_blocklist GC failed at horizon=\(horizonDays)d: \(error)",
        details: nil, level: "warn")
    }
    return deleted
  }

  /// Increment `attempt_count` and update `last_attempted_at`. Used for the
  /// deferral / FK-stalled paths; leaves `last_error` untouched.
  public static func recordReattempt(_ db: Database, id: Int64) throws {
    try db.execute(
      sql: """
        UPDATE sync_pending_inbox
        SET attempt_count = attempt_count + 1,
            last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE id = ?
        """,
      arguments: [id])
  }

  /// Bump `attempt_count` (+ refresh `last_attempted_at`) ONLY when the row's
  /// `last_attempted_at` is older than `minInterval` (a SQLite datetime modifier,
  /// e.g. `"-300 seconds"`). Returns whether the bump happened.
  ///
  /// The drain runs once per inbound chunk. During one large multi-chunk pull an
  /// entry waiting on an FK parent that arrives thousands of records later would
  /// otherwise burn its whole 50-attempt budget in seconds — quarantined mid-sync,
  /// losing a legitimately-waiting row. Gating the bump on wall-clock elapsed
  /// since the last attempt makes the retry budget measure elapsed time, not chunk
  /// count, so the entry survives the pull and still sheds within the horizon if
  /// its parent genuinely never arrives. A no-bump leaves `last_attempted_at`
  /// unchanged so the interval is measured from the last real bump.
  @discardableResult
  public static func recordReattemptTimeGated(
    _ db: Database, id: Int64, minInterval: String
  ) throws -> Bool {
    try db.execute(
      sql: """
        UPDATE sync_pending_inbox
        SET attempt_count = attempt_count + 1,
            last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE id = ?
          AND last_attempted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
        """,
      arguments: [id, minInterval])
    return db.changesCount > 0
  }

  /// Re-record `last_attempted_at` WITHOUT bumping `attempt_count`. Used for
  /// attempts that should remain pending without consuming the retry budget
  /// (for example transient SQLite busy/locked errors or schema-too-new gates).
  public static func recordAttemptTimestamp(_ db: Database, id: Int64) throws {
    try db.execute(
      sql: """
        UPDATE sync_pending_inbox
        SET last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE id = ?
        """,
      arguments: [id])
  }

  /// Transient busy/locked attempts also refresh only the timestamp.
  public static func recordReattemptBusy(_ db: Database, id: Int64) throws {
    try recordAttemptTimestamp(db, id: id)
  }

  /// Like `recordReattempt` but also records `new_error` into `last_error`.
  /// Returns the `last_error` value stored on the row BEFORE this update so
  /// callers can dedup `error_logs` writes.
  @discardableResult
  public static func recordReattemptWithError(
    _ db: Database, id: Int64, newError: String
  ) throws -> String? {
    let prior =
      try Optional<String>.fetchOne(
        db, sql: "SELECT last_error FROM sync_pending_inbox WHERE id = ?", arguments: [id])
      ?? nil
    try db.execute(
      sql: """
        UPDATE sync_pending_inbox
        SET attempt_count = attempt_count + 1,
            last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
            last_error = ?
        WHERE id = ?
        """,
      arguments: [newError, id])
    return prior
  }

  /// Bump `attempt_count` to at least `target`. Used by the drain's
  /// unparseable-envelope branch to push a poison row toward the cap. The
  /// `MAX(attempt_count, ?)` guard prevents ratcheting the count back down.
  public static func bumpAttemptCountToCap(_ db: Database, id: Int64, target: Int64) throws {
    try db.execute(
      sql: """
        UPDATE sync_pending_inbox
        SET attempt_count = MAX(attempt_count, ?),
            last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE id = ?
        """,
      arguments: [target, id])
  }

  /// Rewrite a deferred entry's stored envelope + identity columns, returning
  /// the row id that remains active afterward.
  ///
  /// Drain re-records a still-deferred (or post-remap) entry here. When a remap
  /// rewrote the envelope so its `(entity_type, entity_id, version)` triple now
  /// collides with a DIFFERENT pending row, this folds the two rows together —
  /// the collision row absorbs the merged metadata (`MIN(first_attempted_at)`,
  /// `MAX(last_attempted_at)`, `MAX(attempt_count)`, `COALESCE(last_error)`) and
  /// the original row at `id` is deleted; the returned id is the surviving
  /// collision row. With no collision the row at `id` is updated in place and
  /// returned unchanged.
  ///
  /// `envelopeJSON` is the serialized current envelope; `envelopeEntityType` /
  /// `envelopeEntityID` / `envelopeVersion` are its identity triple (kept in
  /// sync with the body so a later enqueue of the post-remap identity coalesces
  /// via the UNIQUE index instead of duplicating).
  public static func updatePendingEntry(
    _ db: Database, id: Int64, envelopeJSON: String, reason: String,
    missingEntityType: String?, missingEntityID: String?,
    envelopeEntityType: String, envelopeEntityID: String, envelopeVersion: String
  ) throws -> Int64 {
    let collisionID =
      try Int64.fetchOne(
        db,
        sql: """
          SELECT id FROM sync_pending_inbox
          WHERE envelope_entity_type = ?
            AND envelope_entity_id = ?
            AND envelope_version = ?
            AND id <> ?
          LIMIT 1
          """,
        arguments: [envelopeEntityType, envelopeEntityID, envelopeVersion, id])

    if let collisionID {
      try db.execute(
        sql: """
          UPDATE sync_pending_inbox
          SET envelope = ?,
              reason = ?,
              missing_entity_type = COALESCE(?, missing_entity_type),
              missing_entity_id = COALESCE(?, missing_entity_id),
              first_attempted_at = MIN(
                  first_attempted_at,
                  (SELECT first_attempted_at FROM sync_pending_inbox WHERE id = ?)
              ),
              last_attempted_at = MAX(
                  last_attempted_at,
                  (SELECT last_attempted_at FROM sync_pending_inbox WHERE id = ?)
              ),
              attempt_count = MAX(
                  attempt_count,
                  (SELECT attempt_count FROM sync_pending_inbox WHERE id = ?)
              ),
              last_error = COALESCE(
                  last_error,
                  (SELECT last_error FROM sync_pending_inbox WHERE id = ?)
              )
          WHERE id = ?
          """,
        arguments: [
          envelopeJSON, reason, missingEntityType, missingEntityID,
          id, id, id, id, collisionID,
        ])
      try removePending(db, id: id)
      return collisionID
    }

    try db.execute(
      sql: """
        UPDATE sync_pending_inbox
        SET envelope = ?,
            reason = ?,
            missing_entity_type = ?,
            missing_entity_id = ?,
            envelope_entity_type = ?,
            envelope_entity_id = ?,
            envelope_version = ?
        WHERE id = ?
        """,
      arguments: [
        envelopeJSON, reason, missingEntityType, missingEntityID,
        envelopeEntityType, envelopeEntityID, envelopeVersion, id,
      ])
    return id
  }
}
