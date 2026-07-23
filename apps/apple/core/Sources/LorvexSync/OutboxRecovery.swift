import Foundation
import GRDB
import LorvexDomain

extension Outbox {
  /// Why an unsynced row is excluded from the active pending queue.
  ///
  /// `retryWait` is recoverable: after its persisted due time, the canonical
  /// pending read resets its retry budget and tries it again. In contrast,
  /// `authoritativeAdoption` fences pre-snapshot local state that must never be
  /// re-emitted by generic recovery. A genuinely newer local mutation may
  /// replace it through normal LWW coalescing while the session is active;
  /// finalize/cancel otherwise permanently delete that session's owned fence.
  public enum Disposition: String, Sendable, Equatable {
    case retryWait = "retry_wait"
    case authoritativeAdoption = "authoritative_adoption"
    /// A local intent preserved behind an opaque future-authored CloudKit
    /// record. It has no timer and no session owner; only typed reconciliation
    /// may delete or rebuild it.
    case futureRecordHold = "future_record_hold"
  }

  /// Retry-wait delays by recovery round: one hour, six hours, one day, three
  /// days, then one week for every subsequent round. Immediate attempts use the
  /// ordinary retry budget (three repeated identical errors fast-forward that
  /// budget; varying per-record errors can consume all ten). This schedule
  /// starts only after the budget is exhausted, so a persistent poison row
  /// cannot spin in a draining cycle while a repaired app/CloudKit state
  /// eventually recovers.
  static let recoveryDelaySeconds: [TimeInterval] = [
    60 * 60,
    6 * 60 * 60,
    24 * 60 * 60,
    3 * 24 * 60 * 60,
    7 * 24 * 60 * 60,
  ]

  /// Earliest durable wake for a parked outbox row eligible under the active
  /// audit-account binding. Inactive-account audit rows remain durable but do
  /// not wake this account's coordinator. Fail loudly on a malformed timestamp:
  /// silently dropping the timer would strand an eligible row indefinitely in
  /// an otherwise idle app.
  public static func earliestRetryAt(_ db: Database) throws -> Date? {
    guard
      let raw = try String.fetchOne(
        db,
        sql: """
          SELECT MIN(next_retry_at)
          FROM sync_outbox outbox
          WHERE outbox.synced_at IS NULL
            AND outbox.disposition = ?
            AND \(activeAccountAuditEligibilitySQL)
          """,
        arguments: [
          Disposition.retryWait.rawValue, EntityName.aiChangelog,
        ])
    else { return nil }
    guard let parsed = SyncTimestamp.parse(raw), parsed.asString == raw else {
      throw OutboxError.sql("outbox retry timestamp is not canonical RFC 3339 UTC: \(raw)")
    }
    return parsed.date
  }

  /// Move a failed active row into persisted retry wait and return its due time.
  /// A row already fenced by authoritative adoption is deliberately untouched.
  static func parkRetryableFailure(
    _ db: Database, outboxId: Int64, failedAt: String
  ) throws -> String? {
    guard let failedTimestamp = SyncTimestamp.parse(failedAt) else {
      throw OutboxError.sql("outbox retry timestamp is not canonical RFC 3339 UTC: \(failedAt)")
    }
    guard
      let priorRound = try Int64.fetchOne(
        db,
        sql: """
          SELECT recovery_round FROM sync_outbox
          WHERE id = ? AND synced_at IS NULL AND disposition IS NULL
          """,
        arguments: [outboxId])
    else { return nil }

    let nextRound = priorRound == Int64.max ? priorRound : priorRound + 1
    let delayIndex = min(Int(nextRound - 1), recoveryDelaySeconds.count - 1)
    let due = SyncTimestamp(
      date: failedTimestamp.date.addingTimeInterval(recoveryDelaySeconds[delayIndex])
    ).asString
    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET retry_count = ?,
            disposition = ?,
            next_retry_at = ?,
            recovery_round = ?
        WHERE id = ? AND synced_at IS NULL AND disposition IS NULL
        """,
      arguments: [
        maxRetries, Disposition.retryWait.rawValue, due, nextRound, outboxId,
      ])
    return db.changesCount == 1 ? due : nil
  }

  /// Re-arm at most one outbound fetch slice of due retryable failures after
  /// the current drain's exclusive raw-row cursor. Rows behind that cursor stay
  /// parked with their durable deadline intact, so ``earliestRetryAt(_:)``
  /// immediately schedules a fresh drain instead of activating rows that this
  /// drain is no longer allowed to scan.
  /// Authoritative-adoption fences have no due time and are excluded by the
  /// typed predicate, so generic recovery cannot resurrect snapshot-discarded
  /// writes. Returns the number of rows moved back to the active queue.
  @discardableResult
  public static func rearmRetryableFailuresDue(
    _ db: Database, now: String, afterOutboxId: Int64? = nil
  ) throws -> Int {
    guard let canonicalNow = SyncTimestamp.parse(now)?.asString else {
      throw OutboxError.sql("outbox recovery timestamp is not canonical RFC 3339 UTC: \(now)")
    }
    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET retry_count = 0,
            consecutive_error_count = 0,
            disposition = NULL,
            next_retry_at = NULL
        WHERE id IN (
          SELECT outbox.id FROM sync_outbox outbox
          WHERE outbox.synced_at IS NULL
            AND outbox.disposition = ?
            AND outbox.next_retry_at <= ?
            AND outbox.id > ?
            AND \(activeAccountAuditEligibilitySQL)
          ORDER BY outbox.next_retry_at ASC, outbox.id ASC
          LIMIT ?
        )
        """,
      arguments: [
        Disposition.retryWait.rawValue, canonicalNow,
        afterOutboxId ?? 0, EntityName.aiChangelog, maxPendingFetch,
      ])
    return db.changesCount
  }
}
