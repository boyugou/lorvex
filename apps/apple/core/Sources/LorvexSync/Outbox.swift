import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Sync outbox operations — enqueue, consume, coalesce, and manage sync events.
///
/// The `sync_outbox` table is the local staging area for changes that need to be
/// pushed to remote sync transports. Each entry carries a full ``SyncEnvelope``
/// plus outbox-specific metadata (`synced_at`, retry state).
///
/// Static methods take a GRDB `Database` (the caller's open connection / open
/// transaction); the HLC and timestamps are minted by the caller or via
/// `SyncTimestampFormat.syncTimestampNow()`. No method opens its own transaction or
/// writes audit rows, except the coalesce dropped-Delete audit.
/// Best-effort `error_logs` breadcrumbs are not written here; the row-state
/// mutations that accompany them (for example, parking a decode-poison row in
/// persisted retry wait) are preserved.
public enum Outbox {

  // MARK: - Constants

  /// Maximum number of immediate retries before an outbox entry enters persisted
  /// retry wait. Due rows are automatically re-armed with increasing backoff;
  /// they are not discarded by retention GC.
  public static let maxRetries: Int64 = 10

  /// Cap on the number of outbox rows materialized by a single
  /// ``getPending(_:)`` call so a large backlog cannot allocate an unbounded
  /// batch of (up to 256 KiB) payloads inside one transaction. The transport's
  /// cursor-based fixed-point drain reads the next slice.
  public static let maxPendingFetch: Int64 = 1000

  /// Cap on `sync_outbox.last_error`. Trim every stored error string at this
  /// byte budget so a pathological error chain cannot bloat a row.
  public static let outboxLastErrorMaxBytes = 4096

  /// Consecutive per-record failures with the same error required before the
  /// row fast-forwards to ``maxRetries``. Chunk-level and transient failures
  /// reset this streak because they are not evidence that the row is poisoned.
  public static let sameErrorEscalationThreshold: Int64 = 3

  /// One shared eligibility predicate for account-bound audit rows. Both the
  /// active FIFO scan and its deferred-retry wake query must use this exact
  /// clause: an audit row owned by a previously active iCloud account is durable
  /// but cannot be emitted into, or wake a tight retry loop for, the current
  /// account's zone.
  static let activeAccountAuditEligibilitySQL = """
    (
      outbox.entity_type <> ?
      OR EXISTS (
        SELECT 1
        FROM ai_changelog audit
        JOIN audit_retention_binding binding ON binding.singleton = 1
        WHERE audit.id = outbox.entity_id
          AND (
            (binding.ever_bound = 0
             AND audit.retention_account_identifier IS NULL)
            OR
            (binding.ever_bound = 1
             AND audit.retention_account_identifier =
                 binding.active_account_identifier)
          )
      )
    )
    """

  /// Truncate an error string to ``outboxLastErrorMaxBytes`` without splitting a
  /// UTF-8 code point.
  public static func truncateOutboxLastError(_ error: String) -> String {
    let bytes = Array(error.utf8)
    if bytes.count <= outboxLastErrorMaxBytes {
      return error
    }
    var end = outboxLastErrorMaxBytes
    while end > 0 && !isUTF8CharBoundary(bytes, end) {
      end -= 1
    }
    return String(decoding: bytes[0..<end], as: UTF8.self)
  }

  private static func isUTF8CharBoundary(_ bytes: [UInt8], _ index: Int) -> Bool {
    if index == 0 || index == bytes.count { return true }
    // A boundary is any byte that is not a UTF-8 continuation byte (0b10xxxxxx).
    return (bytes[index] & 0xC0) != 0x80
  }

  // MARK: - Types

  /// A row from the `sync_outbox` table: wraps a ``SyncEnvelope`` with outbox
  /// metadata.
  public struct OutboxEntry: Sendable, Equatable {
    /// Outbox row ID (autoincrement).
    public var id: Int64
    /// The sync envelope for this entry.
    public var envelope: SyncEnvelope
    /// RFC 3339 timestamp when this entry was created.
    public var createdAt: String
    /// RFC 3339 timestamp when this entry was successfully pushed to remote.
    public var syncedAt: String?
    /// Number of push retries attempted.
    public var retryCount: Int64
    /// RFC 3339 timestamp of the last retry attempt.
    public var lastRetryAt: String?
  }

  /// One bounded raw FIFO scan. `entries` contains only decoded, currently
  /// transport-eligible rows; `lastScannedOutboxId` is the highest raw row the
  /// SQL page examined before decode/future-record fencing. Keeping both values
  /// prevents a full page of poisoned or newly fenced rows from masquerading as
  /// end-of-queue and starving healthy successors.
  public struct PendingPage: Sendable, Equatable {
    public var entries: [OutboxEntry]
    public var lastScannedOutboxId: Int64?

    public init(entries: [OutboxEntry], lastScannedOutboxId: Int64?) {
      self.entries = entries
      self.lastScannedOutboxId = lastScannedOutboxId
    }
  }

  /// Outcome of a ``recordRetry(_:outboxId:retriedAt:error:)`` call.
  ///
  /// Callers need to know when a row JUST crossed ``maxRetries`` so they can
  /// surface the delayed-recovery state and its next scheduled attempt.
  public struct RecordRetryOutcome: Sendable, Equatable {
    /// The new `retry_count` after increment.
    public var newRetryCount: Int64
    /// True iff this call brought `retry_count` up to ``maxRetries`` for the
    /// first time (the "just exhausted" signal).
    public var exhaustedNow: Bool
    /// Persisted due time when `exhaustedNow` moved the row into retry wait.
    public var nextRetryAt: String?

    public init(newRetryCount: Int64, exhaustedNow: Bool, nextRetryAt: String? = nil) {
      self.newRetryCount = newRetryCount
      self.exhaustedNow = exhaustedNow
      self.nextRetryAt = nextRetryAt
    }
  }

  /// Errors raised by the outbox enqueue surfaces.
  public enum OutboxError: Error, Equatable {
    /// The final canonical envelope deterministically violated its numbered
    /// payload manifest.
    case invalidPayloadContract(String)
    /// The bundled manifest set is absent or corrupt. This is a local
    /// infrastructure failure, not a peer/local-payload classification.
    case payloadContractUnavailable(String)
    /// The incoming envelope's `version` failed `Hlc.parse`. The outbox refuses
    /// the write so the caller can re-stamp with a canonical HLC.
    case taintedVersion(entityType: EntityKind, entityId: String, version: String)
    /// The envelope is syntactically canonical but exceeds the one operational
    /// wire ceiling shared by inbound, local generation, and outbound paths.
    case operationalHlcCeilingExceeded(
      entityType: EntityKind, entityId: String, version: String)
    /// A future-record fence owns the unique unsynced slot and cannot be
    /// replaced through generic coalescing.
    case futureRecordRequiresNewerApp(
      entityType: EntityKind, entityId: String, heldVersion: String)
    /// The coalesced-enqueue retry loop exhausted its retry budget against the
    /// `(entity_type, entity_id)` UNIQUE-partial-index race.
    case contentionExhausted(entityType: EntityKind, entityId: String, attempts: UInt32)
    /// A malformed envelope was rejected at the enqueue boundary, or a database
    /// error propagated.
    case sql(String)
  }

  // MARK: - Operation decode

  // `OutboxError.description` lives in an extension below the enum.

  /// Decode the `operation` TEXT column into a typed ``SyncOperation``.
  /// Surfaces an unknown value as a `DatabaseError(SQLITE_MISMATCH)` so a
  /// corrupt row can be parked without poisoning the batch.
  static func decodeSyncOperation(_ operationStr: String) throws -> SyncOperation {
    switch operationStr {
    case SyncNaming.opDelete: return .delete
    case SyncNaming.opUpsert: return .upsert
    default:
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "invalid sync_outbox operation '\(operationStr)'")
    }
  }

  // MARK: - Query

  /// Get all envelopes ready to emit.
  ///
  /// An entry is ready when `synced_at` and `disposition` are NULL and
  /// `retry_count < maxRetries`. Before reading, due ordinary failures are
  /// re-armed; authoritative-adoption fences are never eligible.
  /// Account-bound audit rows are additionally eligible only while their
  /// canonical `ai_changelog` row belongs to the active account. Pending audit
  /// work for an inactive account remains durable in this shared queue and is
  /// exposed again when that account resumes; it can never leak into another
  /// account's CloudKit zone.
  /// Results are ordered by `id ASC` (FIFO) and capped at ``maxPendingFetch``.
  /// `afterOutboxId` is an exclusive, monotonic cursor used by one transport
  /// drain: rows already attempted by that drain stay behind the cursor, so a
  /// transient/per-record failure cannot be retried in a tight loop, while rows
  /// coalesced or authored during the attempt receive a newer AUTOINCREMENT id
  /// and are eligible for the next page.
  ///
  /// Rows are decoded defensively: a single malformed row (unknown operation or
  /// version) enters the same delayed retry state as a rejected push, so a later
  /// repaired build can recover it without wedging healthy siblings.
  public static func getPending(
    _ db: Database, now: String = SyncTimestampFormat.syncTimestampNow(),
    afterOutboxId: Int64? = nil
  ) throws -> [OutboxEntry] {
    try getPendingPage(db, now: now, afterOutboxId: afterOutboxId).entries
  }

  /// Scan one bounded raw FIFO page and preserve its raw high-water mark even
  /// when every row is removed from the returned entries by defensive decode or
  /// future-record fencing. Transports must advance by
  /// ``PendingPage/lastScannedOutboxId`` rather than by the final decoded row.
  public static func getPendingPage(
    _ db: Database, now: String = SyncTimestampFormat.syncTimestampNow(),
    afterOutboxId: Int64? = nil
  ) throws -> PendingPage {
    try rearmRetryableFailuresDue(
      db, now: now, afterOutboxId: afterOutboxId)
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, entity_type, entity_id, operation, version,
               payload_schema_version, payload, device_id,
               created_at, synced_at, retry_count, last_retry_at
        FROM sync_outbox outbox
        WHERE outbox.synced_at IS NULL
          AND outbox.id > ?
          AND outbox.disposition IS NULL
          AND outbox.retry_count < ?
          AND \(activeAccountAuditEligibilitySQL)
        ORDER BY outbox.id ASC
        LIMIT ?
        """,
      arguments: [afterOutboxId ?? 0, maxRetries, EntityName.aiChangelog, maxPendingFetch])
    let lastScannedOutboxId = rows.last.map { row -> Int64 in row["id"] }

    var entries: [OutboxEntry] = []
    var poisoned: [(Int64, String)] = []
    let checkFutureProvenance = try FutureRecordHold.hasPotentialBlockingProvenance(db)
    for row in rows {
      let id: Int64 = row["id"]
      let entry: OutboxEntry
      do {
        entry = try decodeRow(row)
      } catch {
        poisoned.append((id, "outbox row decode failed: \(error)"))
        continue
      }
      if checkFutureProvenance,
        let held = try FutureRecordHold.blockingVersion(
        db, entityType: entry.envelope.entityType.asString,
        entityId: entry.envelope.entityId)
      {
        try FutureRecordHold.fenceExistingLocalIntent(
          db, entityType: entry.envelope.entityType.asString,
          entityId: entry.envelope.entityId, heldVersion: held.description)
        continue
      }
      entries.append(entry)
    }

    // Park corrupt rows with persisted backoff. A later app build that can decode
    // the row re-arms it automatically when due; repeated reads in this cycle do
    // not see it again.
    for (id, msg) in poisoned {
      try db.execute(
        sql: "UPDATE sync_outbox SET last_error = ?, last_retry_at = ? WHERE id = ?",
        arguments: [truncateOutboxLastError(msg), now, id])
      _ = try parkRetryableFailure(db, outboxId: id, failedAt: now)
    }
    return PendingPage(entries: entries, lastScannedOutboxId: lastScannedOutboxId)
  }

  private static func decodeRow(_ row: Row) throws -> OutboxEntry {
    let operationStr: String = row["operation"]
    let operation = try decodeSyncOperation(operationStr)
    let entityTypeRaw: String = row["entity_type"]
    guard let entityKind = EntityKind.parse(entityTypeRaw) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "unknown entity_type '\(entityTypeRaw)'")
    }
    let versionRaw: String = row["version"]
    let version: Hlc
    do {
      version = try Hlc.parseCanonical(versionRaw)
    } catch {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH, message: "unparseable version '\(versionRaw)'")
    }
    guard Hlc.isOperationallyAcceptableWire(version) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "outbox version exceeds operational wire ceiling '\(versionRaw)'")
    }
    let envelope = SyncEnvelope(
      entityType: entityKind,
      entityId: row["entity_id"],
      operation: operation,
      version: version,
      payloadSchemaVersion: row["payload_schema_version"],
      payload: row["payload"],
      deviceId: row["device_id"])
    return OutboxEntry(
      id: row["id"],
      envelope: envelope,
      createdAt: row["created_at"],
      syncedAt: row["synced_at"],
      retryCount: row["retry_count"],
      lastRetryAt: row["last_retry_at"])
  }

  /// Read one exact outbox capability by id. Used by asynchronous transport
  /// reconciliation so a late callback can never act on a newer coalesced row
  /// that happens to address the same entity identity.
  public static func entry(_ db: Database, id: Int64) throws -> OutboxEntry? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT id, entity_type, entity_id, operation, version,
                 payload_schema_version, payload, device_id,
                 created_at, synced_at, retry_count, last_retry_at
          FROM sync_outbox WHERE id = ?
          """,
        arguments: [id])
    else { return nil }
    return try decodeRow(row)
  }

  // MARK: - Mutation

  /// Bulk-mark a batch of outbox entries as synced in chunked UPDATEs. Only
  /// overwrites `synced_at` when still NULL (so a re-pushed envelope keeps its
  /// original timestamp) and guards on `synced_at IS NULL`; `retry_count` /
  /// `last_retry_at` are preserved, only `last_error` is cleared. A late push
  /// callback cannot mark an authoritative-adoption fence as synced.
  public static func markManySynced(_ db: Database, outboxIds: [Int64], syncedAt: String) throws {
    if outboxIds.isEmpty { return }
    let chunkSize = 500
    var index = 0
    while index < outboxIds.count {
      let chunk = Array(outboxIds[index..<min(index + chunkSize, outboxIds.count)])
      index += chunkSize
      let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
      var args: [DatabaseValueConvertible] = [syncedAt]
      args.append(contentsOf: chunk)
      try db.execute(
        sql: """
          UPDATE sync_outbox \
          SET synced_at = ?, last_error = NULL \
          WHERE synced_at IS NULL AND disposition IS NULL \
            AND id IN (\(placeholders))
          """,
        arguments: StatementArguments(args))
    }
  }

  static func requireOperationalWireVersion(_ envelope: SyncEnvelope) throws {
    guard Hlc.isOperationallyAcceptableWire(envelope.version) else {
      throw OutboxError.operationalHlcCeilingExceeded(
        entityType: envelope.entityType, entityId: envelope.entityId,
        version: envelope.version.description)
    }
  }

  // MARK: - GC

  /// Delete outbox entries past the retention window: synced rows older than
  /// the window, plus intentionally discarded authoritative-adoption fences.
  /// Ordinary retry-wait rows are never age-deleted; they remain recoverable
  /// after an app or CloudKit repair.
  /// Returns the total number of deleted rows.
  ///
  /// Issued as TWO separate DELETEs rather than one OR'd statement. The branches
  /// are disjoint (`synced_at IS NOT NULL` vs `synced_at IS NULL`), so the net
  /// deletion is identical, but a single `A OR B` DELETE cannot be multi-indexed
  /// when `B` ranges over the unindexed unsynced subset — SQLite would fall back
  /// to a full scan of `sync_outbox` every cycle, leaving `idx_sync_outbox_synced_at`
  /// inert. Splitting lets the synced-history DELETE use that partial index and
  /// the authoritative-discard DELETE use its narrow created-at partial index.
  @discardableResult
  public static func gcSynced(_ db: Database, retentionDays: UInt32) throws -> UInt64 {
    let retentionOffset = "-\(retentionDays) days"
    // Synced-history branch: served by the partial `idx_sync_outbox_synced_at`
    // (`WHERE synced_at IS NOT NULL`).
    try db.execute(
      sql: """
        DELETE FROM sync_outbox
        WHERE synced_at IS NOT NULL
          AND synced_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
        """,
      arguments: [retentionOffset])
    let deletedSynced = db.changesCount
    // Intentional-discard branch. Generic retry wait is deliberately excluded.
    try db.execute(
      sql: """
        DELETE FROM sync_outbox
        WHERE synced_at IS NULL
          AND disposition = ?
          AND created_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
        """,
      arguments: [Disposition.authoritativeAdoption.rawValue, retentionOffset])
    let deletedAuthoritativeFence = db.changesCount
    return UInt64(deletedSynced + deletedAuthoritativeFence)
  }

  /// Bound the never-pushed ACTIVE backlog: delete active unsynced rows beyond
  /// the newest `maxRows`, oldest first. Returns the number of rows deleted.
  ///
  /// ``gcSynced(_:retentionDays:)`` reaps only rows that were pushed
  /// (`synced_at IS NOT NULL`) or intentionally fenced by authoritative adoption.
  /// A row that is never pushed — the whole outbox on a sync-off install, where
  /// nothing drains it — stays `synced_at IS NULL, retry_count = 0` forever, so
  /// that GC never touches it and the queue grows one row per local mutation
  /// without bound. This is the backstop that caps it: keep the newest `maxRows`
  /// (a generous backlog a later sign-in still delivers in full) and shed only
  /// the oldest active queued changes past the cap. Persisted retry-wait rows
  /// and authoritative-adoption fences are excluded: their typed recovery and
  /// retention policies own their lifetime. Every `ai_changelog` row is also
  /// exempt: canonical audit retention bounds that stream, while shedding an
  /// inactive account's emit-once upsert here would make it unrecoverable when
  /// that account resumes.
  ///
  /// Age order is `id DESC`: `id` is `INTEGER PRIMARY KEY AUTOINCREMENT`, and the
  /// coalesce path DELETEs then re-INSERTs a superseded entity's row (minting a
  /// fresh, higher `id`), so a recently-touched entity ranks as new and a
  /// created-once-never-edited entity keeps its original low `id` — the same FIFO
  /// order ``getPending(_:)`` emits in. Scoped to the active-pending partial
  /// index (`idx_sync_outbox_pending`).
  ///
  /// NOT for the live sync path: a full-resync backfill
  /// (``enqueueAllLiveForFullResync(_:)``) legitimately enqueues every live
  /// entity at once and then drains it over many ``maxPendingFetch``-capped
  /// outbound pages, so applying a count cap there could delete a just-enqueued row
  /// before it is ever pushed. Only the sync-off maintenance sweep
  /// (``SyncRetention/runLocalMaintenanceGC(_:syncedAt:emit:includeActiveOutboxCap:)``),
  /// where nothing is
  /// draining, calls this.
  @discardableResult
  public static func gcUnsyncedBeyondCap(_ db: Database, maxRows: Int) throws -> UInt64 {
    let cap = max(0, maxRows)
    try db.execute(
      sql: """
        DELETE FROM sync_outbox
        WHERE synced_at IS NULL
          AND disposition IS NULL
          AND entity_type <> ?
          AND id NOT IN (
            SELECT id FROM sync_outbox
            WHERE synced_at IS NULL
              AND disposition IS NULL
              AND entity_type <> ?
            ORDER BY id DESC
            LIMIT ?
          )
        """,
      arguments: [
        EntityName.aiChangelog,
        EntityName.aiChangelog,
        cap,
      ])
    return UInt64(db.changesCount)
  }

  // MARK: - Retry

  /// Increment the retry count and update `last_retry_at` for a failed push.
  /// When `error` is non-nil it is stored (truncated) in `last_error`; if it
  /// matches the previous `last_error` for
  /// ``sameErrorEscalationThreshold`` consecutive per-record failures, the row
  /// fast-forwards to ``maxRetries``. Returns a ``RecordRetryOutcome`` so callers
  /// can detect the first crossing and its delayed retry due time.
  ///
  /// `escalateOnRepeatedError: false` disables the same-error fast-forward,
  /// resets the per-record consecutive streak, and still advances `retry_count`.
  /// Repeated-identical-error escalation is
  /// evidence of a poisoned ROW only when the error was reported for this
  /// specific record; a chunk-level (wholesale) push failure stamps the same
  /// error on every row in the chunk, so three such cycles would otherwise
  /// force the entire pending backlog into retry wait. A wholesale failure that
  /// genuinely persists still enters delayed retry wait once `retry_count`
  /// reaches ``maxRetries`` linearly.
  @discardableResult
  public static func recordRetry(
    _ db: Database, outboxId: Int64, retriedAt: String, error: String?,
    escalateOnRepeatedError: Bool = true
  ) throws -> RecordRetryOutcome {
    let previous = try Row.fetchOne(
      db,
      sql: """
        SELECT retry_count, last_error, consecutive_error_count FROM sync_outbox
        WHERE id = ? AND synced_at IS NULL AND disposition IS NULL
        """,
      arguments: [outboxId])
    guard let previous else {
      return RecordRetryOutcome(newRetryCount: 0, exhaustedNow: false)
    }
    let previousError: String? = previous["last_error"]
    let previousRetryCount: Int64 = previous["retry_count"]
    let previousConsecutiveErrorCount: Int64 = previous["consecutive_error_count"]

    let truncatedError = error.map(truncateOutboxLastError)
    let consecutiveErrorCount: Int64
    if escalateOnRepeatedError, let truncatedError {
      if previousError == truncatedError {
        consecutiveErrorCount =
          previousConsecutiveErrorCount == Int64.max
          ? Int64.max : previousConsecutiveErrorCount + 1
      } else {
        consecutiveErrorCount = 1
      }
    } else {
      consecutiveErrorCount = 0
    }

    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET retry_count = retry_count + 1,
            last_retry_at = ?,
            last_error = COALESCE(?, last_error),
            consecutive_error_count = ?
        WHERE id = ? AND synced_at IS NULL AND disposition IS NULL
          AND retry_count < ?
        """,
      arguments: [retriedAt, truncatedError, consecutiveErrorCount, outboxId, maxRetries])

    var newRetryCount =
      try Int64.fetchOne(
        db, sql: "SELECT retry_count FROM sync_outbox WHERE id = ?", arguments: [outboxId]) ?? 0

    if consecutiveErrorCount >= sameErrorEscalationThreshold,
      newRetryCount < maxRetries
    {
      try db.execute(
        sql: "UPDATE sync_outbox SET retry_count = ? WHERE id = ?",
        arguments: [maxRetries, outboxId])
      newRetryCount = maxRetries
    }

    let exhaustedNow = previousRetryCount < maxRetries && newRetryCount >= maxRetries
    let nextRetryAt =
      exhaustedNow
      ? try parkRetryableFailure(db, outboxId: outboxId, failedAt: retriedAt)
      : nil
    return RecordRetryOutcome(
      newRetryCount: newRetryCount, exhaustedNow: exhaustedNow, nextRetryAt: nextRetryAt)
  }

  /// Record a TRANSIENT push failure (network down, rate-limited, service/zone
  /// busy) without advancing the row toward delayed retry wait.
  ///
  /// Stamps `last_retry_at` and `last_error` (guarded on `synced_at IS NULL`) for
  /// diagnosability, but deliberately does NOT increment `retry_count` and does
  /// NOT run the same-error escalation heuristic. A transient transport outage
  /// affects every pending row identically, so incrementing `retry_count` (or
  /// letting three identical failures fast-forward to ``maxRetries``) would
  /// pause a healthy backlog in a handful of offline cycles. The row stays
  /// pending and ships once the transport recovers. Genuinely
  /// persistent per-row errors still escalate through
  /// ``recordRetry(_:outboxId:retriedAt:error:)``.
  public static func recordTransientFailure(
    _ db: Database, outboxId: Int64, retriedAt: String, error: String?
  ) throws {
    let truncatedError = error.map(truncateOutboxLastError)
    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET last_retry_at = ?,
            last_error = COALESCE(?, last_error),
            consecutive_error_count = 0
        WHERE id = ? AND synced_at IS NULL AND disposition IS NULL
        """,
      arguments: [retriedAt, truncatedError, outboxId])
  }

  /// Fence every eligible unsynced outbox row — active or already in ordinary
  /// retry wait — by assigning the typed authoritative-adoption disposition, pinning
  /// `retry_count` to ``maxRetries``, and stamping `last_error`. Used by over-window
  /// snapshot re-enrollment (S-5): a device adopting a peer-rebuilt zone as truth
  /// must not push its pre-adoption pending upserts — one for an entity peers have
  /// since deleted and reclaimed the tombstone for would resurrect it fleet-wide.
  /// `authoritativeSessionToken` durably binds each fence to the snapshot intent
  /// that created it. Finalize/cancel deletes only that session's rows rather
  /// than re-arming superseded writes. Already-synced rows are untouched; an
  /// authoritative row from a replaced session is transferred to the current
  /// owner defensively. A permanent future-record hold is deliberately excluded:
  /// the app cannot adopt or discard an intent whose remote identity it cannot
  /// yet interpret. Returns the number of rows newly fenced or transferred.
  @discardableResult
  public static func quarantineAllPending(
    _ db: Database, error: String, authoritativeSessionToken: String
  ) throws -> Int {
    guard !authoritativeSessionToken.isEmpty, authoritativeSessionToken.count <= 128 else {
      throw OutboxError.sql("authoritative snapshot session token is empty or over 128 characters")
    }
    try db.execute(
      sql: """
        UPDATE sync_outbox \
        SET retry_count = ?, last_error = ?, \
            disposition = ?, authoritative_session_token = ?, \
            next_retry_at = NULL \
        WHERE synced_at IS NULL \
          AND (disposition IS NULL OR disposition <> ?) \
          AND ( \
            entity_type <> ? \
            OR EXISTS ( \
              SELECT 1 \
              FROM ai_changelog audit \
              JOIN audit_retention_binding binding ON binding.singleton = 1 \
              WHERE audit.id = sync_outbox.entity_id \
                AND ( \
                  (binding.ever_bound = 0 \
                   AND audit.retention_account_identifier IS NULL) \
                  OR \
                  (binding.ever_bound = 1 \
                   AND audit.retention_account_identifier = \
                       binding.active_account_identifier) \
                ) \
            ) \
          ) \
          AND (disposition IS NULL OR disposition <> ? \
               OR authoritative_session_token <> ?)
        """,
      arguments: [
        maxRetries, truncateOutboxLastError(error),
        Disposition.authoritativeAdoption.rawValue,
        authoritativeSessionToken,
        Disposition.futureRecordHold.rawValue,
        EntityName.aiChangelog,
        Disposition.authoritativeAdoption.rawValue,
        authoritativeSessionToken,
      ])
    return db.changesCount
  }

  /// Permanently discard the stale outbound rows fenced by one completed or
  /// canceled remote-authoritative session. Deleting (rather than resetting)
  /// them is essential: re-arming would resurrect pre-adoption local state.
  /// A later local-authoritative rebuild re-enqueues the then-current DB rows
  /// through the normal full-resync path after this unique-slot release.
  @discardableResult
  public static func releaseAuthoritativeAdoptionFences(
    _ db: Database, authoritativeSessionToken: String
  ) throws -> Int {
    try db.execute(
      sql: """
        DELETE FROM sync_outbox
        WHERE synced_at IS NULL
          AND disposition = ?
          AND authoritative_session_token = ?
        """,
      arguments: [
        Disposition.authoritativeAdoption.rawValue, authoritativeSessionToken,
      ])
    return db.changesCount
  }

}

extension Outbox.OutboxError: CustomStringConvertible {
  /// Human-readable description of this outbox error.
  public var description: String {
    switch self {
    case .invalidPayloadContract(let detail):
      return "outbox rejected invalid sync payload contract: \(detail)"
    case .payloadContractUnavailable(let detail):
      return "outbox could not load sync payload contract: \(detail)"
    case .taintedVersion(let entityType, let entityId, let version):
      return
        "outbox refused tainted incoming version for \(entityType.asString)/\(entityId): "
        + "version=\"\(version)\" failed Hlc::parse — caller must re-stamp"
    case .operationalHlcCeilingExceeded(let entityType, let entityId, let version):
      return
        "outbox refused \(entityType.asString)/\(entityId): version \(version) exceeds "
        + "the operational sync wire ceiling"
    case .futureRecordRequiresNewerApp(let entityType, let entityId, let heldVersion):
      return
        "outbox refused \(entityType.asString)/\(entityId): a future-authored record at "
        + "\(heldVersion) owns the CloudKit identity"
    case .contentionExhausted(let entityType, let entityId, let attempts):
      return
        "outbox coalesce retry budget exhausted for \(entityType.asString)/\(entityId) "
        + "after \(attempts) attempts; the write was rolled back and must be retried"
    case .sql(let message):
      return "database error: \(message)"
    }
  }
}
