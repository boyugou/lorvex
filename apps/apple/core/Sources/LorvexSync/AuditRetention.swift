import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Local half of account-scoped audit retention.
///
/// Retention never emits a sync delete envelope or tombstone. Instead it first
/// advances a monotonic `(epoch, minimum-retained timestamp, id)` frontier,
/// atomically removes dominated local/full-content outbox copies, and enqueues a
/// durable account-scoped CloudKit physical delete whenever cloud presence was
/// possible. The transport publishes/joins the frontier and drains that queue.
public enum AuditRetention {
  /// Apply one active account's policy immediately and enforce its absolute
  /// row cap. Transport uses this before minting an outbound authorization so
  /// a newly adopted days/off policy cannot race an older retained-set view.
  public static func enforcePolicyForAccount(
    _ db: Database, accountIdentifier: String,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws {
    guard
      let state = try AuditRetentionFrontier.state(
        db, accountIdentifier: accountIdentifier)
    else { throw AuditRetentionStateError.malformedAccountState(accountIdentifier) }
    guard state.isPolicyReady else {
      throw AuditRetentionStateError.policyNotReady(accountIdentifier)
    }
    try applyPolicy(
      db, accountIdentifier: accountIdentifier, frontier: state.frontier,
      policy: state.policy, now: now)
    try enforceCanonicalCap(
      db, accountIdentifier: accountIdentifier, now: now)
  }

  /// Apply every persisted scope's policy and bounded-entry safeguard.
  /// Returns the total number of `ai_changelog` rows removed across the
  /// canonical synced stream and the separately-budgeted device-local stream.
  @discardableResult
  public static func gcChangelog(_ db: Database) throws -> UInt64 {
    let before = try UInt64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
    let now = SyncTimestampFormat.syncTimestampNow()

    if let unbound = try AuditRetentionFrontier.unboundScopeState(db),
      unbound.isPolicyReady
    {
      try applyPolicy(
        db, accountIdentifier: nil, frontier: unbound.frontier,
        policy: unbound.policy, now: now)
      try enforceCanonicalCap(db, accountIdentifier: nil, now: now)
    }

    for state in try AuditRetentionFrontier.allAccountStates(db)
    where state.isPolicyReady {
      try applyPolicy(
        db, accountIdentifier: state.accountIdentifier,
        frontier: state.frontier, policy: state.policy, now: now)
      try enforceCanonicalCap(
        db, accountIdentifier: state.accountIdentifier, now: now)
    }

    // Intentionally device-local forensic rows always remain account-NULL. They
    // obey the current user-facing policy locally, both before and after first
    // account binding, but never advance a remote frontier: these rows cannot
    // exist in CloudKit and therefore cannot be evidence for fleet retention.
    if let active = try AuditRetentionFrontier.activeAccountIdentifier(db),
      let state = try AuditRetentionFrontier.state(db, accountIdentifier: active),
      state.isPolicyReady
    {
      try applyDeviceLocalPolicy(db, policy: state.policy, now: now)
    } else if let unbound = try AuditRetentionFrontier.unboundScopeState(db),
      unbound.isPolicyReady
    {
      try applyDeviceLocalPolicy(db, policy: unbound.policy, now: now)
    }
    try enforceDeviceLocalCap(db, now: now)

    try enforceActivePendingHoldCap(db, now: now)
    let after = try UInt64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
    return before >= after ? before - after : 0
  }

  private static func applyDeviceLocalPolicy(
    _ db: Database, policy: ChangelogRetentionPolicy, now: String
  ) throws {
    let ids: [String]
    switch policy {
    case .off:
      ids = try deviceLocalRows(db).map { $0["id"] as String }
    case .days(let days):
      let cutoff = try daysCutoffISO(db, days: days)
      ids = try String.fetchAll(
        db,
        sql: """
          SELECT id FROM ai_changelog
          WHERE retention_account_identifier IS NULL
            AND operation = ? AND timestamp < ?
          ORDER BY timestamp ASC, id ASC
          """,
        arguments: [SyncNaming.localAuditCoalescedDeleteDropped, cutoff])
    case .maximum:
      return
    }
    for id in ids {
      _ = try AuditRetentionFrontier.pruneLocalAuditIdentity(
        db, entityId: id, accountIdentifier: nil,
        reason: .localRetention, now: now)
    }
  }

  private static func enforceDeviceLocalCap(_ db: Database, now: String) throws {
    let rows = try deviceLocalRows(db)
    let cap = Int(SyncNaming.auditMaxEntriesSafeguard)
    guard rows.count > cap else { return }
    for row in rows.prefix(rows.count - cap) {
      _ = try AuditRetentionFrontier.pruneLocalAuditIdentity(
        db, entityId: row["id"], accountIdentifier: nil,
        reason: .localRetention, now: now)
    }
  }

  private static func deviceLocalRows(_ db: Database) throws -> [Row] {
    try Row.fetchAll(
      db,
      sql: """
        SELECT id, timestamp FROM ai_changelog
        WHERE retention_account_identifier IS NULL AND operation = ?
        ORDER BY timestamp ASC, id ASC
        """,
      arguments: [SyncNaming.localAuditCoalescedDeleteDropped])
  }

  private static func applyPolicy(
    _ db: Database, accountIdentifier: String?,
    frontier: AuditRetentionFrontierValue,
    policy: ChangelogRetentionPolicy, now: String
  ) throws {
    switch policy {
    case .off:
      let ids = try canonicalIds(db, accountIdentifier: accountIdentifier)
      for id in ids {
        _ = try AuditRetentionFrontier.pruneLocalAuditIdentity(
          db, entityId: id, accountIdentifier: accountIdentifier,
          reason: .localRetention, now: now)
      }
    case .days(let days):
      // A fleet frontier is irreversible and authorizes physical CloudKit
      // deletion, so an account-scoped rolling horizon must never trust this
      // device's wall clock. A bad RTC could otherwise publish a cutoff years
      // in the future and erase the whole fleet. No server receipt means no
      // time-based fleet pruning yet; delayed deletion is the safe failure.
      let cutoff: String
      if let accountIdentifier {
        guard
          let trusted = try trustedDaysCutoffISO(
            db, accountIdentifier: accountIdentifier, days: days)
        else { return }
        cutoff = trusted
      } else {
        cutoff = try daysCutoffISO(db, days: days)
      }
      if let accountIdentifier {
        _ = try AuditRetentionFrontier.advanceMinimumRetainedKey(
          db, accountIdentifier: accountIdentifier,
          minimumRetainedTimestamp: cutoff, now: now)
      } else {
        try AuditRetentionFrontier.advanceUnboundMinimumRetainedKey(
          db, minimumRetainedTimestamp: cutoff, now: now)
      }
    case .maximum:
      // The separate entry-count safeguard below remains authoritative.
      _ = frontier
    }
  }

  /// Keep at most `auditMaxEntriesSafeguard` canonical rows per account scope.
  /// The first retained row becomes the scope's exclusive lower bound, giving
  /// equal timestamps a deterministic id tie-break and preventing an offline
  /// peer from uploading any of the removed prefix after reconnect.
  private static func enforceCanonicalCap(
    _ db: Database, accountIdentifier: String?, now: String
  ) throws {
    let cap = Int(SyncNaming.auditMaxEntriesSafeguard)
    let rows: [Row]
    if let accountIdentifier {
      rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, timestamp FROM ai_changelog
          WHERE retention_account_identifier = ?
          ORDER BY timestamp ASC, id ASC
          """,
        arguments: [accountIdentifier])
    } else {
      rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, timestamp FROM ai_changelog
          WHERE retention_account_identifier IS NULL
            AND operation != ?
          ORDER BY timestamp ASC, id ASC
          """,
        arguments: [SyncNaming.localAuditCoalescedDeleteDropped])
    }
    guard rows.count > cap else { return }
    let firstRetained = rows[rows.count - cap]
    let timestamp: String = firstRetained["timestamp"]
    let entityId: String = firstRetained["id"]
    if let accountIdentifier {
      _ = try AuditRetentionFrontier.advanceMinimumRetainedKey(
        db, accountIdentifier: accountIdentifier,
        minimumRetainedTimestamp: timestamp,
        minimumRetainedEntityId: entityId, now: now)
    } else {
      try AuditRetentionFrontier.advanceUnboundMinimumRetainedKey(
        db, minimumRetainedTimestamp: timestamp,
        minimumRetainedEntityId: entityId, now: now)
    }
  }

  /// Budget future-generation audit HOLDs together with canonical rows for the
  /// active account. A pending-only row is known CloudKit content, so evicting
  /// it always creates durable physical-delete work before removing the sole
  /// local full-content copy.
  private static func enforceActivePendingHoldCap(
    _ db: Database, now: String
  ) throws {
    guard let account = try AuditRetentionFrontier.activeAccountIdentifier(db) else { return }
    let canonicalCount =
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM ai_changelog
          WHERE retention_account_identifier = ?
          """,
        arguments: [account]) ?? 0
    let budget = max(0, Int(SyncNaming.auditMaxEntriesSafeguard) - canonicalCount)
    let pending = try Row.fetchAll(
      db,
      sql: """
        SELECT id, envelope, envelope_entity_id, first_attempted_at
        FROM sync_pending_inbox
        WHERE envelope_entity_type = ?
        ORDER BY first_attempted_at ASC, envelope_entity_id ASC, id ASC
        """,
      arguments: [EntityName.aiChangelog])
    guard pending.count > budget else { return }
    for row in pending.prefix(pending.count - budget) {
      let storedId: String = row["envelope_entity_id"]
      let envelopeJSON: String = row["envelope"]
      guard let data = envelopeJSON.data(using: .utf8),
        let envelope = try? JSONDecoder().decode(SyncEnvelope.self, from: data),
        envelope.entityType == .aiChangelog, envelope.entityId == storedId,
        envelope.operation == .upsert,
        case .object(let object)? = JSONValue.parse(envelope.payload),
        let epoch = try? ApplyJSON.requiredInt64(
          object, "retention_epoch", entity: EntityName.aiChangelog),
        epoch >= 0
      else {
        // Malformed HOLDs are not silently discarded: leave them for the normal
        // pending poison path and surface a durable diagnostic.
        ErrorLog.appendBestEffort(
          db, source: "sync.retention.audit_pending_invalid",
          message: "audit retention could not decode held record \(storedId)",
          details: nil, level: "error")
        continue
      }
      try AuditRetentionFrontier.rejectInboundAuditAndQueuePurge(
        db, entityId: storedId, retentionEpoch: epoch,
        reason: .localRetention, now: now)
    }
  }

  private static func canonicalIds(
    _ db: Database, accountIdentifier: String?
  ) throws -> [String] {
    if let accountIdentifier {
      return try String.fetchAll(
        db,
        sql: """
          SELECT id FROM ai_changelog
          WHERE retention_account_identifier = ? ORDER BY id ASC
          """,
        arguments: [accountIdentifier])
    }
    return try String.fetchAll(
      db,
      sql: """
        SELECT id FROM ai_changelog
        WHERE retention_account_identifier IS NULL
          AND operation != ?
        ORDER BY id ASC
        """,
      arguments: [SyncNaming.localAuditCoalescedDeleteDropped])
  }

  /// Canonical UTC cutoff for a rolling `days(N)` policy. Strictly earlier
  /// timestamps are retired; rows exactly at the cutoff remain because the
  /// frontier uses an empty id as the first key at that timestamp.
  public static func daysCutoffISO(_ db: Database, days: UInt32) throws -> String {
    guard
      let raw = try String.fetchOne(
        db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)",
        arguments: ["-\(days) days"]),
      SyncTimestamp.parse(raw)?.asString == raw
    else { throw AuditRetentionStateError.invalidFrontier }
    return raw
  }

  /// Canonical rolling cutoff derived only from a CloudKit-assigned server
  /// timestamp observed for this exact active account. Returns `nil` until a
  /// receipt exists (or when an extreme day count underflows SQLite's supported
  /// calendar), conservatively delaying retention instead of trusting local RTC.
  public static func trustedDaysCutoffISO(
    _ db: Database, accountIdentifier: String, days: UInt32
  ) throws -> String? {
    guard
      let serverTime = try String.fetchOne(
        db,
        sql: """
          SELECT trusted_server_time FROM sync_cloudkit_account_binding
          WHERE singleton = 1 AND account_identifier = ?
          """,
        arguments: [accountIdentifier])
    else { return nil }
    guard SyncTimestamp.parse(serverTime)?.asString == serverTime else {
      throw AuditRetentionStateError.invalidFrontier
    }
    guard
      let cutoff = try String.fetchOne(
        db,
        sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', ?, ?)",
        arguments: [serverTime, "-\(days) days"])
    else { return nil }
    guard SyncTimestamp.parse(cutoff)?.asString == cutoff else {
      throw AuditRetentionStateError.invalidFrontier
    }
    return cutoff
  }
}
