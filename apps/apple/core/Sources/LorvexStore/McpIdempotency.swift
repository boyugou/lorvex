import Foundation
import GRDB
import LorvexDomain
import Synchronization

/// MCP idempotency cache: dedup of repeated tool calls keyed on
/// `(tool_name, idempotency_key)` with a request checksum that rejects a
/// same-key reuse carrying a different payload.
///
/// On a same-tool / same-key hit whose stored checksum matches the supplied
/// checksum, the cached response payload is safe to replay byte-for-byte. A
/// checksum disagreement means the assistant reused the token for a
/// semantically different request — surfaced as ``LookupOutcome/checksumMismatch``
/// so the caller raises a validation error rather than replaying a stale
/// response. Rows past `expires_at` never satisfy a hit and are reaped by
/// ``sweepExpired(_:)`` at MCP-server boot.
public enum McpIdempotency {

  /// Default retention window for idempotency records, in hours.
  public static let defaultTtlHours: Int64 = 24

  /// Result of a cache lookup attempt.
  public enum LookupOutcome: Equatable, Sendable {
    /// No cached row for this tool/key pair (or the row has expired).
    case miss
    /// A cached row exists and the supplied checksum matches the stored
    /// checksum — the carried response payload is safe to replay.
    case hit(String)
    /// A cached row exists but its stored checksum disagrees with the
    /// caller's; the caller must surface a validation error rather than
    /// silently replay the prior response.
    case checksumMismatch(storedTool: String, storedChecksum: String, suppliedChecksum: String)
  }

  /// Result of atomically claiming a tool/key immediately before its domain
  /// mutation in the same writer transaction.
  public enum MutationClaimOutcome: Equatable, Sendable {
    case acquired
    case owned
    case replay(String)
    case checksumMismatch(storedChecksum: String, suppliedChecksum: String)
  }

  /// Compute the canonical SHA-256 checksum of the caller-supplied request
  /// representation. Callers normalize the input (e.g. canonical JSON) so
  /// logically equivalent payloads produce the same hash. Returns the digest
  /// as a 64-char lowercase hex string.
  public static func computeRequestChecksum(_ requestRepr: String) -> String {
    Sha256Checksum.hexDigest(Data(requestRepr.utf8))
  }

  /// Look up a cached response for `toolName`/`key` against `now`, verifying
  /// its stored checksum matches `suppliedChecksum`.
  public static func lookupCheckedAt(
    _ db: Database,
    toolName: String,
    key: String,
    suppliedChecksum: String,
    now: Date
  ) throws -> LookupOutcome {
    let row = try Row.fetchOne(
      db,
      sql: """
        SELECT tool_name, request_checksum, response_payload \
        FROM mcp_idempotency \
        WHERE tool_name = ?1 AND key = ?2 AND expires_at > ?3
        """,
      arguments: [toolName, key, SyncTimestampFormat.formatSyncTimestamp(now)])
    guard let row else { return .miss }
    let storedTool: String = row[0]
    let storedChecksum: String = row[1]
    let payload: String = row[2]
    if storedChecksum == suppliedChecksum {
      return .hit(payload)
    }
    return .checksumMismatch(
      storedTool: storedTool, storedChecksum: storedChecksum, suppliedChecksum: suppliedChecksum)
  }

  /// Look up a cached response with checksum verification against the canonical
  /// wall clock.
  public static func lookupChecked(
    _ db: Database, toolName: String, key: String, suppliedChecksum: String
  ) throws -> LookupOutcome {
    try lookupCheckedAt(db, toolName: toolName, key: key, suppliedChecksum: suppliedChecksum, now: Date())
  }

  /// Record a cached response for `(toolName, key)` at `now` with the given TTL.
  /// A live row with a different checksum is rejected rather than overwritten.
  /// An expired row is deleted before insertion so expiry is the only path that
  /// permits a key to represent a new request.
  public static func recordAt(
    _ db: Database,
    key: String,
    toolName: String,
    requestChecksum: String,
    responsePayload: String,
    now: Date,
    ttlHours: Int64
  ) throws {
    if requestChecksum.isEmpty {
      throw StoreError.validation("request_checksum must not be empty")
    }
    let nowString = SyncTimestampFormat.formatSyncTimestamp(now)
    if let existing = try Row.fetchOne(
      db,
      sql: """
        SELECT request_checksum, expires_at FROM mcp_idempotency
        WHERE tool_name = ?1 AND key = ?2
        """,
      arguments: [toolName, key])
    {
      let storedChecksum: String = existing[0]
      let expiresAt: String = existing[1]
      if expiresAt > nowString {
        guard storedChecksum == requestChecksum else {
          throw StoreError.validation(
            "idempotency key checksum mismatch for \(toolName)")
        }
        try db.execute(
          sql: """
            UPDATE mcp_idempotency SET response_payload = ?3
            WHERE tool_name = ?1 AND key = ?2 AND request_checksum = ?4
            """,
          arguments: [toolName, key, responsePayload, requestChecksum])
        return
      }
      try db.execute(
        sql: "DELETE FROM mcp_idempotency WHERE tool_name = ?1 AND key = ?2",
        arguments: [toolName, key])
    }
    try insert(
      db, key: key, toolName: toolName, requestChecksum: requestChecksum,
      responsePayload: responsePayload, now: now, ttlHours: ttlHours)
  }

  /// Record the cached response with the default 24h TTL, stamping `created_at`
  /// from the canonical sync clock.
  public static func record(
    _ db: Database, key: String, toolName: String, requestChecksum: String, responsePayload: String
  ) throws {
    try recordAt(
      db, key: key, toolName: toolName, requestChecksum: requestChecksum,
      responsePayload: responsePayload, now: Date(), ttlHours: defaultTtlHours)
  }

  /// Atomically claim an idempotency key inside the domain mutation's writer
  /// transaction. A claim owned by this logical tool call permits subsequent
  /// domain transactions of a batch tool; any other live row prevents the body
  /// from running.
  public static func claimMutation(
    _ db: Database,
    key: String,
    toolName: String,
    requestChecksum: String,
    claimPayload: String,
    now: Date = Date(),
    ttlHours: Int64 = defaultTtlHours
  ) throws -> MutationClaimOutcome {
    guard !requestChecksum.isEmpty else {
      throw StoreError.validation("request_checksum must not be empty")
    }
    let nowString = SyncTimestampFormat.formatSyncTimestamp(now)
    if let row = try Row.fetchOne(
      db,
      sql: """
        SELECT request_checksum, response_payload, expires_at
        FROM mcp_idempotency WHERE tool_name = ?1 AND key = ?2
        """,
      arguments: [toolName, key])
    {
      let storedChecksum: String = row[0]
      let storedPayload: String = row[1]
      let expiresAt: String = row[2]
      if expiresAt > nowString {
        guard storedChecksum == requestChecksum else {
          return .checksumMismatch(
            storedChecksum: storedChecksum, suppliedChecksum: requestChecksum)
        }
        return storedPayload == claimPayload ? .owned : .replay(storedPayload)
      }
      try db.execute(
        sql: "DELETE FROM mcp_idempotency WHERE tool_name = ?1 AND key = ?2",
        arguments: [toolName, key])
    }
    try insert(
      db, key: key, toolName: toolName, requestChecksum: requestChecksum,
      responsePayload: claimPayload, now: now, ttlHours: ttlHours)
    return .acquired
  }

  /// Replace this call's private transaction claim with the full replay
  /// response. The compare-and-swap prevents a caller from overwriting another
  /// request's checksum or claim.
  public static func finalizeMutation(
    _ db: Database,
    key: String,
    toolName: String,
    requestChecksum: String,
    claimPayload: String,
    responsePayload: String
  ) throws {
    guard !requestChecksum.isEmpty else {
      throw StoreError.validation("request_checksum must not be empty")
    }
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT request_checksum, response_payload FROM mcp_idempotency
          WHERE tool_name = ?1 AND key = ?2
          """,
        arguments: [toolName, key])
    else {
      // A successful keyed mutation commits its private claim in the same
      // transaction as the domain effect. Missing here therefore means this
      // finalizer has no ownership proof (for example, a storage cutover landed
      // between mutation and response persistence). Never recreate the row in a
      // potentially different database and misrepresent that response as local.
      throw StoreError.invariant(
        "idempotency response finalization found no durable claim")
    }
    let storedChecksum: String = row[0]
    let storedPayload: String = row[1]
    guard storedChecksum == requestChecksum else {
      throw StoreError.validation("idempotency key checksum mismatch for \(toolName)")
    }
    if storedPayload == responsePayload { return }
    guard storedPayload == claimPayload else {
      throw StoreError.invariant(
        "idempotency response finalization did not own the durable claim")
    }
    try db.execute(
      sql: """
        UPDATE mcp_idempotency SET response_payload = ?5
        WHERE tool_name = ?1 AND key = ?2
          AND request_checksum = ?3 AND response_payload = ?4
        """,
      arguments: [toolName, key, requestChecksum, claimPayload, responsePayload])
    guard db.changesCount == 1 else {
      throw StoreError.invariant("idempotency durable claim changed during finalization")
    }
  }

  private static func insert(
    _ db: Database,
    key: String,
    toolName: String,
    requestChecksum: String,
    responsePayload: String,
    now: Date,
    ttlHours: Int64
  ) throws {
    let later = now.addingTimeInterval(TimeInterval(ttlHours) * 3600)
    try db.execute(
      sql: """
        INSERT INTO mcp_idempotency
        (key, tool_name, request_checksum, response_payload, created_at, expires_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        """,
      arguments: [
        key, toolName, requestChecksum, responsePayload,
        SyncTimestampFormat.formatSyncTimestamp(now),
        SyncTimestampFormat.formatSyncTimestamp(later),
      ])
  }

  /// Delete all rows whose `expires_at <= now`. Returns the rows removed.
  static func sweepExpiredAt(_ db: Database, now: Date) throws -> Int {
    try db.execute(
      sql: "DELETE FROM mcp_idempotency WHERE expires_at <= ?1",
      arguments: [SyncTimestampFormat.formatSyncTimestamp(now)])
    return db.changesCount
  }

  /// Window during which a back-to-back boot-sweep short-circuits, in ms.
  static let sweepSkipWindowMs: Int64 = 5 * 60 * 1000

  /// Process-local timestamp (Unix ms) of the most recent successful sweep.
  /// Guards against several MCP children booting in close succession each
  /// taking the writer lock for a DELETE that has nothing to reap.
  private static let lastSweepAtMillis = SweepClaim()

  /// Delete all expired rows using the canonical wall clock. Returns `0`
  /// immediately if a sweep ran within ``sweepSkipWindowMs``. Exactly one
  /// caller wins the skip-slot claim; concurrent losers short-circuit.
  public static func sweepExpired(_ db: Database) throws -> Int {
    let now = Date()
    let nowMillis = Int64(now.timeIntervalSince1970 * 1000)
    guard lastSweepAtMillis.tryClaim(nowMillis: nowMillis, windowMs: sweepSkipWindowMs) else {
      return 0
    }
    return try sweepExpiredAt(db, now: now)
  }

  // MARK: - Test hooks

  /// Reset the process-local sweep-skip clock. Test-only.
  static func resetSweepClock() {
    lastSweepAtMillis.store(0)
  }

  /// Force the sweep-skip clock to `millis`. Test-only.
  static func setSweepClock(_ millis: Int64) {
    lastSweepAtMillis.store(millis)
  }

}

/// Thread-safe holder for the process-local sweep-skip timestamp using a
/// compare-and-swap skip claim: at most one caller per skip window wins the
/// right to run the writer-locking DELETE.
private final class SweepClaim: Sendable {
  private let value = Mutex<Int64>(0)

  func store(_ newValue: Int64) {
    value.withLock { $0 = newValue }
  }

  /// Claim the sweep slot. Returns `true` (caller should sweep) only when no
  /// sweep ran within `windowMs`; on success the clock is advanced to
  /// `nowMillis` atomically so a concurrent caller loses the claim.
  func tryClaim(nowMillis: Int64, windowMs: Int64) -> Bool {
    value.withLock { last in
      if last != 0 && nowMillis - last < windowMs {
        return false
      }
      last = nowMillis
      return true
    }
  }
}
