import Foundation
import GRDB

/// The monotonic `local_change_seq` counter used by the outbox.
///
/// The counter lives in the `local_counters` table as an `INTEGER NOT NULL`
/// `value` column keyed by `name`. The upsert is a single
/// `INSERT ... ON CONFLICT DO UPDATE SET value = value + 1 RETURNING value`
/// against an INTEGER column so a bad input cannot truncate the counter back to
/// zero and break the strict-monotonicity invariant every consumer depends on.
public enum LocalChangeSeq {
  /// The `local_counters.name` key for the local change sequence.
  public static let key = "local_change_seq"

  /// Read the current `local_change_seq` counter.
  ///
  /// A missing row reads as `0`; a negative stored value is treated as
  /// corruption and surfaced as ``RuntimeError/corruptLocalChangeSeq`` rather
  /// than silently resetting (a stale-but-positive seq would pass the "is
  /// newer" check the reconciler downstream uses).
  public static func read(_ db: Database) throws -> UInt64 {
    let value = try Int64.fetchOne(
      db, sql: "SELECT value FROM local_counters WHERE name = ?1", arguments: [key])
    switch value {
    case nil:
      return 0
    case let .some(v) where v < 0:
      throw RuntimeError.corruptLocalChangeSeq(String(v))
    case let .some(v):
      return UInt64(v)
    }
  }

  /// Atomically increment `local_change_seq` and return the post-increment
  /// value. Stamps the `updated_at` audit column with the current wall-clock
  /// epoch-milliseconds (any monotonic value satisfies that contract).
  @discardableResult
  public static func bump(_ db: Database) throws -> UInt64 {
    let updatedAt = auditTimestampMillis()
    let next =
      try Int64.fetchOne(
        db,
        sql: """
          INSERT INTO local_counters (name, value, updated_at) VALUES (?1, 1, ?2)
          ON CONFLICT(name) DO UPDATE SET
            value = local_counters.value + 1,
            updated_at = excluded.updated_at
          RETURNING value
          """,
        arguments: [key, updatedAt]) ?? 0
    if next < 0 {
      throw RuntimeError.corruptLocalChangeSeq(String(next))
    }
    return UInt64(next)
  }

  /// Current wall-clock epoch milliseconds for the `updated_at` audit column,
  /// clamped to `Int64.max` on year-2262 overflow and floored at 0 before 1970.
  /// The column only needs any monotonic value, so a reading outside the `Int64`
  /// range saturates rather than trapping.
  private static func auditTimestampMillis() -> Int64 {
    let raw = (Date().timeIntervalSince1970 * 1000).rounded(.down)
    if raw < 0 { return 0 }
    if raw >= Double(Int64.max) { return Int64.max }
    return Int64(raw)
  }
}
