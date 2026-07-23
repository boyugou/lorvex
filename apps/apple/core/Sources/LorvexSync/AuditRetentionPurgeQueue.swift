import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension AuditRetentionFrontier {
  /// Earliest durable retry for physical-delete work in one exact active
  /// account/zone. Retired zones are deliberately excluded: their whole-zone
  /// cleanup owns those rows, and letting one overdue retired item drive the
  /// ready generation's timer would create an immediate no-progress loop.
  public static func earliestPurgeRetryAt(
    _ db: Database, accountIdentifier: String, zoneName: String
  ) throws -> Date? {
    try requireActiveAccount(db, requested: accountIdentifier)
    try validateZoneName(zoneName)
    guard
      let raw = try String.fetchOne(
        db,
        sql: """
          SELECT MIN(next_attempt_at)
          FROM audit_retention_purge_queue
          WHERE account_identifier = ? AND zone_name = ?
            AND next_attempt_at IS NOT NULL
          """,
        arguments: [accountIdentifier, zoneName])
    else { return nil }
    guard let parsed = SyncTimestamp.parse(raw), parsed.asString == raw else {
      throw AuditRetentionStateError.invalidTimestamp(raw)
    }
    return parsed.date
  }

  /// Classify an inbound audit upsert against the active account's generation
  /// and authorized policy. A future/unauthorized generation is a typed HOLD,
  /// never a best-effort parse or destructive policy decision.
  public static func classifyInboundAuditUpsert(
    _ db: Database, entityId: String, retentionEpoch: Int64, timestamp: String
  ) throws -> AuditRetentionInboundDisposition {
    try validateEpoch(retentionEpoch)
    let bindingAccount = try activeAccountIdentifier(db)
    guard let account = bindingAccount else {
      // An inbound CloudKit record cannot legitimately arrive before account
      // activation. Fail closed without inventing account-scoped purge work.
      return .holdForFrontierRefresh(requiredEpoch: retentionEpoch)
    }
    guard let state = try state(db, accountIdentifier: account) else {
      throw AuditRetentionStateError.malformedAccountState(account)
    }

    let canonicalTimestamp = SyncTimestamp.parse(timestamp)?.asString
    guard canonicalTimestamp == timestamp else {
      throw AuditRetentionStateError.invalidFrontier
    }
    if rowIsDominated(
      epoch: retentionEpoch, timestamp: timestamp, entityId: entityId,
      by: state.frontier)
    {
      return .rejectAndPurge(.belowFrontier)
    }
    if !state.isPolicyReady || retentionEpoch > state.frontierEpoch
      || retentionEpoch > state.policyAuthorizedEpoch
    {
      try requireRefresh(db, accountIdentifier: account, epoch: retentionEpoch)
      return .holdForFrontierRefresh(requiredEpoch: retentionEpoch)
    }

    switch state.policy {
    case .off:
      return .rejectAndPurge(.policyHorizon)
    case .days(let days):
      // Rejecting an inbound row advances an irreversible fleet frontier and
      // queues a physical CloudKit delete. Use only this account's trusted
      // server clock; with no receipt yet, accept now and let a later retention
      // sweep classify it once server time is known.
      guard
        let cutoff = try AuditRetention.trustedDaysCutoffISO(
          db, accountIdentifier: account, days: days)
      else { return .accept }
      if timestamp < cutoff {
        _ = try advanceMinimumRetainedKey(
          db, accountIdentifier: account,
          minimumRetainedTimestamp: cutoff)
        return .rejectAndPurge(.policyHorizon)
      }
    case .maximum:
      break
    }
    return .accept
  }

  /// Atomically reject a known remote audit record, retain account-scoped cloud
  /// evidence, enqueue physical deletion, and remove every local full-content
  /// copy. No sync tombstone or delete envelope is created.
  public static func rejectInboundAuditAndQueuePurge(
    _ db: Database, entityId: String, retentionEpoch: Int64,
    reason: AuditRetentionPurgeReason,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws {
    guard let account = try activeAccountIdentifier(db),
      let zoneName = try activeZoneName(db)
    else {
      throw AuditRetentionStateError.noActiveAccount
    }
    try validateEpoch(retentionEpoch)
    try recordCloudPresence(
      db, accountIdentifier: account, zoneName: zoneName, entityId: entityId,
      retentionEpoch: retentionEpoch, now: now)
    try enqueuePurge(
      db, accountIdentifier: account, zoneName: zoneName, entityId: entityId,
      retentionEpoch: retentionEpoch, reason: reason, now: now)
    try removeLocalAuditCopies(db, entityId: entityId)
  }

  /// Record that an accepted inbound audit row is known to exist in the active
  /// account's zone. Runs even on id-dedup so a second account's independent
  /// cloud-presence evidence is not lost.
  static func recordAcceptedInboundCloudPresence(
    _ db: Database, entityId: String, retentionEpoch: Int64,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws {
    guard let account = try activeAccountIdentifier(db),
      let zoneName = try activeZoneName(db)
    else {
      throw AuditRetentionStateError.noActiveAccount
    }
    try recordCloudPresence(
      db, accountIdentifier: account, zoneName: zoneName, entityId: entityId,
      retentionEpoch: retentionEpoch, now: now)
  }

  /// Durable mark-before-cloud boundary. The coordinator calls this after
  /// selecting an outbox row but before handing it to CloudKit. If the process
  /// crashes after this transaction and before/after the network attempt, a
  /// later local prune conservatively queues a physical delete.
  public static func markCloudPresencePossible(
    _ db: Database, outboxId: Int64,
    authorization: AuditRetentionOutboundAuthorization,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    let accountIdentifier = authorization.accountIdentifier
    let zoneName = authorization.zoneName
    let accountState = try validateOutboundAuthorization(
      db, authorization: authorization)
    guard
      let outbox = try Row.fetchOne(
        db,
        sql: """
          SELECT entity_type, entity_id, operation, version, payload, synced_at
          FROM sync_outbox WHERE id = ?
          """,
        arguments: [outboxId])
    else { return .noLongerPending }
    let entityType: String = outbox["entity_type"]
    let entityId: String = outbox["entity_id"]
    let operation: String = outbox["operation"]
    let envelopeVersion: String = outbox["version"]
    let syncedAt: String? = outbox["synced_at"]
    guard entityType == EntityName.aiChangelog,
      operation == SyncNaming.opUpsert, syncedAt == nil
    else { throw AuditRetentionStateError.invalidOutboundAuditRow(outboxId) }

    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT retention_account_identifier, retention_epoch, timestamp
          FROM ai_changelog WHERE id = ?
          """,
        arguments: [entityId])
    else {
      // Prune-before-mark crash ordering: suppress the now-orphaned upload.
      try db.execute(sql: "DELETE FROM sync_outbox WHERE id = ?", arguments: [outboxId])
      return .noLongerPending
    }
    let rowAccount: String? = row["retention_account_identifier"]
    let rowEpoch: Int64 = row["retention_epoch"]
    let rowTimestamp: String = row["timestamp"]
    guard rowAccount == accountIdentifier else {
      throw AuditRetentionStateError.auditRowAccountMismatch(
        entityId: entityId, expected: accountIdentifier, actual: rowAccount)
    }
    if rowIsDominated(
      epoch: rowEpoch, timestamp: rowTimestamp, entityId: entityId,
      by: accountState.frontier)
    {
      _ = try pruneLocalAuditIdentity(
        db, entityId: entityId, accountIdentifier: accountIdentifier,
        reason: .belowFrontier, now: now)
      return .noLongerPending
    }
    guard rowEpoch == accountState.frontierEpoch,
      try payloadRetentionEpoch(outbox["payload"] as String) == rowEpoch,
      try auditPayloadMatchesCanonicalRow(
        db, entityId: entityId, payload: outbox["payload"] as String,
        envelopeVersion: envelopeVersion)
    else { throw AuditRetentionStateError.invalidOutboundAuditRow(outboxId) }

    try recordCloudPresence(
      db, accountIdentifier: accountIdentifier, zoneName: zoneName,
      entityId: entityId,
      retentionEpoch: rowEpoch, now: now)
    return .marked
  }

  /// Mark-before-cloud boundary for audit envelopes emitted by the read-only
  /// candidate-generation snapshot rather than `sync_outbox`.
  public static func markGenerationSnapshotCloudPresencePossible(
    _ db: Database, envelope: SyncEnvelope,
    authorization: AuditRetentionOutboundAuthorization,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    let accountState = try validateOutboundAuthorization(
      db, authorization: authorization)
    return try markGenerationSnapshotCloudPresencePossible(
      db, envelope: envelope,
      accountIdentifier: authorization.accountIdentifier,
      destinationZoneName: authorization.zoneName,
      accountState: accountState, now: now)
  }

  /// Batch mark-before-cloud for one immutable active-generation page. The
  /// authorization is validated once and every mark shares one SQLite
  /// transaction at the service boundary.
  public static func markGenerationSnapshotCloudPresencePossible(
    _ db: Database, envelopes: [SyncEnvelope],
    authorization: AuditRetentionOutboundAuthorization,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> [AuditRetentionCloudPresenceMarkResult] {
    let accountState = try validateOutboundAuthorization(
      db, authorization: authorization)
    return try envelopes.map {
      try markGenerationSnapshotCloudPresencePossible(
        db, envelope: $0,
        accountIdentifier: authorization.accountIdentifier,
        destinationZoneName: authorization.zoneName,
        accountState: accountState, now: now)
    }
  }

  /// Candidate-only mark-before-cloud. This records possible presence in the
  /// fresh candidate zone but cannot authorize the ordinary audit outbox.
  public static func markGenerationSnapshotCloudPresencePossible(
    _ db: Database, envelope: SyncEnvelope,
    candidateAuthorization: AuditRetentionCandidateAuthorization,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    let accountState = try validateCandidateAuthorization(
      db, authorization: candidateAuthorization)
    return try markGenerationSnapshotCloudPresencePossible(
      db, envelope: envelope,
      accountIdentifier: candidateAuthorization.accountIdentifier,
      destinationZoneName: candidateAuthorization.candidateZoneName,
      accountState: accountState, now: now)
  }

  /// Candidate-generation twin of the active batch boundary.
  public static func markGenerationSnapshotCloudPresencePossible(
    _ db: Database, envelopes: [SyncEnvelope],
    candidateAuthorization: AuditRetentionCandidateAuthorization,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> [AuditRetentionCloudPresenceMarkResult] {
    let accountState = try validateCandidateAuthorization(
      db, authorization: candidateAuthorization)
    return try envelopes.map {
      try markGenerationSnapshotCloudPresencePossible(
        db, envelope: $0,
        accountIdentifier: candidateAuthorization.accountIdentifier,
        destinationZoneName: candidateAuthorization.candidateZoneName,
        accountState: accountState, now: now)
    }
  }

  private static func markGenerationSnapshotCloudPresencePossible(
    _ db: Database, envelope: SyncEnvelope,
    accountIdentifier: String, destinationZoneName: String,
    accountState: AuditRetentionAccountState, now: String
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    guard envelope.entityType == .aiChangelog,
      envelope.operation == .upsert,
      envelope.payloadSchemaVersion == LorvexVersion.payloadSchemaVersion,
      case .success = envelope.validate()
    else { throw AuditRetentionStateError.invalidGenerationSnapshotRow(envelope.entityId) }
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT retention_account_identifier, retention_epoch, timestamp,
                 source_device_id
          FROM ai_changelog WHERE id = ?
          """,
        arguments: [envelope.entityId])
    else { return .noLongerPending }
    let rowAccount: String? = row["retention_account_identifier"]
    let rowEpoch: Int64 = row["retention_epoch"]
    let rowTimestamp: String = row["timestamp"]
    guard rowAccount == accountIdentifier else {
      throw AuditRetentionStateError.auditRowAccountMismatch(
        entityId: envelope.entityId, expected: accountIdentifier,
        actual: rowAccount)
    }
    if rowIsDominated(
      epoch: rowEpoch, timestamp: rowTimestamp, entityId: envelope.entityId,
      by: accountState.frontier)
    {
      _ = try pruneLocalAuditIdentity(
        db, entityId: envelope.entityId, accountIdentifier: accountIdentifier,
        reason: .belowFrontier, now: now)
      return .noLongerPending
    }
    let expectedVersion = try deterministicGenerationSnapshotVersion(
      entityId: envelope.entityId)
    let expectedDeviceId = try generationSnapshotDeviceId(
      sourceDeviceId: row["source_device_id"], entityId: envelope.entityId)
    guard rowEpoch == accountState.frontierEpoch,
      envelope.version == expectedVersion,
      envelope.deviceId == expectedDeviceId,
      try payloadRetentionEpoch(envelope.payload) == rowEpoch,
      try auditPayloadMatchesCanonicalRow(
        db, entityId: envelope.entityId, payload: envelope.payload,
        envelopeVersion: envelope.version.description)
    else {
      throw AuditRetentionStateError.invalidGenerationSnapshotRow(envelope.entityId)
    }
    try recordCloudPresence(
      db, accountIdentifier: accountIdentifier,
      zoneName: destinationZoneName, entityId: envelope.entityId,
      retentionEpoch: rowEpoch, now: now)
    return .marked
  }

  /// Due physical-delete work for one exact account-zone generation.
  ///
  /// The zone predicate is part of the SQL query before `LIMIT`; selecting a
  /// cross-generation account page and filtering afterward can indefinitely
  /// starve a ready generation behind more than one page of retired-zone work.
  public static func pendingPurges(
    _ db: Database, accountIdentifier: String, zoneName: String, limit: Int = 200,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> [AuditRetentionPurgeItem] {
    try requireActiveAccount(db, requested: accountIdentifier)
    try validateZoneName(zoneName)
    guard limit > 0 else { return [] }
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT account_identifier, zone_name, entity_id, retention_epoch, reason,
               attempt_count, next_attempt_at, last_error, created_at
        FROM audit_retention_purge_queue
        WHERE account_identifier = ? AND zone_name = ?
          AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
        ORDER BY created_at ASC, entity_id ASC
        LIMIT ?
        """,
      arguments: [accountIdentifier, zoneName, now, min(limit, 1_000)])
    return try rows.map { row in
      let reasonRaw: String = row["reason"]
      guard let reason = AuditRetentionPurgeReason(rawValue: reasonRaw) else {
        throw AuditRetentionStateError.invalidPurgeReason(reasonRaw)
      }
      let epoch: Int64 = row["retention_epoch"]
      try validateEpoch(epoch)
      return AuditRetentionPurgeItem(
        accountIdentifier: row["account_identifier"], zoneName: row["zone_name"],
        entityId: row["entity_id"],
        retentionEpoch: epoch, reason: reason, attemptCount: row["attempt_count"],
        nextAttemptAt: row["next_attempt_at"], lastError: row["last_error"],
        createdAt: row["created_at"])
    }
  }

  /// Acknowledge CloudKit physical deletes. Evidence disappears only with the
  /// matching account's durable queue item; a late callback after A→B fails the
  /// active-account guard and leaves A work intact for its next activation.
  public static func acknowledgePurges(
    _ db: Database, accountIdentifier: String, zoneName: String,
    entityIds: [String]
  ) throws {
    try requireActiveAccount(db, requested: accountIdentifier)
    try validateZoneName(zoneName)
    for entityId in Set(entityIds) {
      try db.execute(
        sql: """
          DELETE FROM audit_retention_purge_queue
          WHERE account_identifier = ? AND zone_name = ? AND entity_id = ?
          """,
        arguments: [accountIdentifier, zoneName, entityId])
      if db.changesCount > 0 {
        try db.execute(
          sql: """
            DELETE FROM audit_changelog_cloud_presence
            WHERE account_identifier = ? AND zone_name = ? AND entity_id = ?
            """,
          arguments: [accountIdentifier, zoneName, entityId])
      }
    }
  }

  /// A whole-zone delete supersedes every per-record purge for that exact
  /// account/generation. Clear evidence only after CloudKit confirms deletion;
  /// doing it before the remote success would lose the durable privacy work.
  public static func acknowledgeZoneDeletion(
    _ db: Database, accountIdentifier: String, zoneName: String
  ) throws {
    // A CloudKit zone-delete completion can arrive after an account switch.
    // The successful callback still proves that exact old account/zone is gone,
    // so unlike a per-record callback it need not match the current binding.
    try validateAccountIdentifier(accountIdentifier)
    try validateZoneName(zoneName)
    try db.execute(
      sql: """
        DELETE FROM audit_retention_purge_queue
        WHERE account_identifier = ? AND zone_name = ?
        """,
      arguments: [accountIdentifier, zoneName])
    try db.execute(
      sql: """
        DELETE FROM audit_changelog_cloud_presence
        WHERE account_identifier = ? AND zone_name = ?
        """,
      arguments: [accountIdentifier, zoneName])
  }

  /// Retain failed work with bounded exponential backoff (30 seconds through
  /// six hours). The error is diagnostic only and capped before persistence.
  public static func recordPurgeFailure(
    _ db: Database, accountIdentifier: String, zoneName: String,
    entityId: String, error: String,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws {
    try requireActiveAccount(db, requested: accountIdentifier)
    try validateZoneName(zoneName)
    guard
      let attempt: Int = try Int.fetchOne(
        db,
        sql: """
          SELECT attempt_count FROM audit_retention_purge_queue
          WHERE account_identifier = ? AND zone_name = ? AND entity_id = ?
          """,
        arguments: [accountIdentifier, zoneName, entityId])
    else { return }
    let nextAttempt = attempt + 1
    let exponent = min(max(nextAttempt - 1, 0), 10)
    let delaySeconds = min(21_600, 30 * (1 << exponent))
    guard let base = SyncTimestamp.parse(now), base.asString == now else {
      throw AuditRetentionStateError.invalidTimestamp(now)
    }
    let retryAt = SyncTimestampFormat.formatSyncTimestamp(
      base.date.addingTimeInterval(TimeInterval(delaySeconds)))
    let cappedError = String(error.prefix(2_000))
    try db.execute(
      sql: """
        UPDATE audit_retention_purge_queue
        SET attempt_count = ?, next_attempt_at = ?, last_error = ?, updated_at = ?
        WHERE account_identifier = ? AND zone_name = ? AND entity_id = ?
        """,
      arguments: [
        nextAttempt, retryAt, cappedError, now, accountIdentifier, zoneName, entityId,
      ])
  }

  /// Remove one local identity and enqueue physical deletion only in its exact
  /// account scope when cloud presence was possible there. Used by
  /// policy/frontier GC; account-NULL forensic rows are never cloud-addressable.
  @discardableResult
  static func pruneLocalAuditIdentity(
    _ db: Database, entityId: String, accountIdentifier: String?,
    reason: AuditRetentionPurgeReason,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> Bool {
    let row = try Row.fetchOne(
      db,
      sql: """
        SELECT id, retention_account_identifier
        FROM ai_changelog WHERE id = ?
        """,
      arguments: [entityId])
    if let row {
      let owner: String? = row["retention_account_identifier"]
      guard owner == accountIdentifier else {
        throw AuditRetentionStateError.auditRowAccountMismatch(
          entityId: entityId, expected: accountIdentifier ?? "unbound", actual: owner)
      }
    }
    let mappings: [Row]
    if let accountIdentifier {
      mappings = try Row.fetchAll(
        db,
        sql: """
          SELECT account_identifier, zone_name, retention_epoch
          FROM audit_changelog_cloud_presence
          WHERE account_identifier = ? AND entity_id = ?
          """,
        arguments: [accountIdentifier, entityId])
    } else {
      // Account-NULL forensic rows are deliberately device-local and can have
      // no CloudKit presence in any account.
      mappings = []
    }
    for mapping in mappings {
      try enqueuePurge(
        db, accountIdentifier: mapping["account_identifier"],
        zoneName: mapping["zone_name"], entityId: entityId,
        retentionEpoch: mapping["retention_epoch"], reason: reason, now: now)
    }
    try removeLocalAuditCopies(db, entityId: entityId)
    return row != nil
  }

  /// Enforce a verified/local frontier across canonical rows and queued audit
  /// upserts before transport can observe them. The row delete, outbox removal,
  /// cloud-evidence preservation, and purge enqueue share the caller's
  /// transaction.
  static func pruneAuditRowsDominatedByFrontier(
    _ db: Database, accountIdentifier: String?,
    frontier: AuditRetentionFrontierValue,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws {
    try validateFrontier(frontier)
    let rows: [Row]
    if let accountIdentifier {
      rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, timestamp, retention_epoch
          FROM ai_changelog
          WHERE retention_account_identifier = ?
          ORDER BY timestamp ASC, id ASC
          """,
        arguments: [accountIdentifier])
    } else {
      rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, timestamp, retention_epoch
          FROM ai_changelog
          WHERE retention_account_identifier IS NULL
            AND operation != ?
          ORDER BY timestamp ASC, id ASC
          """,
        arguments: [SyncNaming.localAuditCoalescedDeleteDropped])
    }
    for row in rows {
      let entityId: String = row["id"]
      if rowIsDominated(
        epoch: row["retention_epoch"], timestamp: row["timestamp"],
        entityId: entityId, by: frontier)
      {
        _ = try pruneLocalAuditIdentity(
          db, entityId: entityId, accountIdentifier: accountIdentifier,
          reason: .belowFrontier, now: now)
      }
    }

    // A canonical-row delete and its outbox removal normally commit together.
    // Still inspect orphaned audit upserts fail-closed so manual corruption or
    // an interrupted older build cannot bypass the pre-push frontier.
    let orphaned = try Row.fetchAll(
      db,
      sql: """
        SELECT id, entity_id, payload FROM sync_outbox
        WHERE entity_type = ? AND operation = ? AND synced_at IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM ai_changelog WHERE ai_changelog.id = sync_outbox.entity_id
          )
        ORDER BY id ASC
        """,
      arguments: [EntityName.aiChangelog, SyncNaming.opUpsert])
    for row in orphaned {
      let payload: String = row["payload"]
      let epoch = try payloadRetentionEpoch(payload)
      guard let timestamp = payloadTimestamp(payload) else {
        throw AuditRetentionStateError.invalidOutboundAuditRow(row["id"])
      }
      let entityId: String = row["entity_id"]
      if rowIsDominated(
        epoch: epoch, timestamp: timestamp, entityId: entityId, by: frontier)
      {
        _ = try pruneLocalAuditIdentity(
          db, entityId: entityId, accountIdentifier: accountIdentifier,
          reason: .orphanedCloudPresence, now: now)
      }
    }
  }

  static func rowIsDominated(
    epoch: Int64, timestamp: String, entityId: String,
    by frontier: AuditRetentionFrontierValue
  ) -> Bool {
    if epoch != frontier.epoch { return epoch < frontier.epoch }
    if frontier.minimumRetainedTimestamp.isEmpty { return false }
    if timestamp != frontier.minimumRetainedTimestamp {
      return timestamp < frontier.minimumRetainedTimestamp
    }
    return entityId < frontier.minimumRetainedEntityId
  }

  // MARK: - Private SQL helpers

  private static func payloadRetentionEpoch(_ payload: String) throws -> Int64 {
    guard case .object(let object)? = JSONValue.parse(payload),
      let value = object["retention_epoch"]
    else { throw AuditRetentionStateError.invalidEpoch(-1) }
    switch value {
    case .int(let epoch) where epoch >= 0:
      return epoch
    case .uint(let epoch) where epoch <= UInt64(Int64.max):
      return Int64(epoch)
    default:
      throw AuditRetentionStateError.invalidEpoch(-1)
    }
  }

  private static func payloadTimestamp(_ payload: String) -> String? {
    guard case .object(let object)? = JSONValue.parse(payload),
      case .string(let raw)? = object["timestamp"],
      SyncTimestamp.parse(raw)?.asString == raw
    else { return nil }
    return raw
  }

  /// Fail closed if a pending audit envelope has drifted from its append-only
  /// canonical row. Checking only the retention epoch is insufficient: a stale
  /// or corrupt outbox payload could carry an older timestamp/content while the
  /// newer canonical timestamp passes the frontier check above.
  static func auditPayloadMatchesCanonicalRow(
    _ db: Database, entityId: String, payload: String,
    envelopeVersion: String
  ) throws -> Bool {
    guard case .object(var actual)? = JSONValue.parse(payload),
      case .string(let payloadVersion)? = actual.removeValue(forKey: "version"),
      payloadVersion == envelopeVersion,
      let parsedVersion = try? Hlc.parseCanonical(envelopeVersion),
      parsedVersion.description == envelopeVersion,
      let expected = try canonicalAuditPayloadObject(db, entityId: entityId)
    else { return false }
    let actualEntityIds: [String]
    switch actual["entity_ids"] {
    case .none, .some(.null):
      actualEntityIds = []
    case .some(.string(let raw)):
      actualEntityIds = try ChangelogWrite.parseEntityIdsJson(raw)
    default:
      return false
    }
    let expectedEntityIds: [String]
    switch expected["entity_ids"] {
    case .none, .some(.null):
      expectedEntityIds = []
    case .some(.string(let raw)):
      expectedEntityIds = try ChangelogWrite.parseEntityIdsJson(raw)
    default:
      return false
    }
    guard actualEntityIds.count == expectedEntityIds.count,
      actualEntityIds.sorted() == expectedEntityIds
    else { return false }

    if expectedEntityIds.isEmpty {
      actual["entity_ids"] = .null
    } else {
      actual["entity_ids"] = .string(
        try SyncCanonicalize.canonicalizeJSON(
          .array(expectedEntityIds.map(JSONValue.string))))
    }
    // Ordering inside the stringified entity-id registry is semantically
    // irrelevant. Normalize it before comparing every other wire-owned field.
    return actual == expected
  }

  private static func recordCloudPresence(
    _ db: Database, accountIdentifier: String, zoneName: String, entityId: String,
    retentionEpoch: Int64, now: String
  ) throws {
    try validateAccountIdentifier(accountIdentifier)
    try validateZoneName(zoneName)
    try validateEpoch(retentionEpoch)
    try db.execute(
      sql: """
        INSERT INTO audit_changelog_cloud_presence (
          account_identifier, zone_name, entity_id, retention_epoch, marked_at
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(account_identifier, zone_name, entity_id) DO UPDATE SET
          retention_epoch = MAX(retention_epoch, excluded.retention_epoch),
          marked_at = excluded.marked_at
        """,
      arguments: [accountIdentifier, zoneName, entityId, retentionEpoch, now])
  }

  private static func enqueuePurge(
    _ db: Database, accountIdentifier: String, zoneName: String, entityId: String,
    retentionEpoch: Int64, reason: AuditRetentionPurgeReason, now: String
  ) throws {
    try validateAccountIdentifier(accountIdentifier)
    try validateZoneName(zoneName)
    try validateEpoch(retentionEpoch)
    try db.execute(
      sql: """
        INSERT INTO audit_retention_purge_queue (
          account_identifier, zone_name, entity_id, retention_epoch, reason,
          attempt_count, next_attempt_at, last_error, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, 0, NULL, NULL, ?, ?)
        ON CONFLICT(account_identifier, zone_name, entity_id) DO UPDATE SET
          retention_epoch = MAX(retention_epoch, excluded.retention_epoch),
          reason = excluded.reason,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at
        """,
      arguments: [
        accountIdentifier, zoneName, entityId, retentionEpoch, reason.rawValue, now, now,
      ])
  }

  private static func removeLocalAuditCopies(_ db: Database, entityId: String) throws {
    try db.execute(sql: "DELETE FROM ai_changelog WHERE id = ?", arguments: [entityId])
    try db.execute(
      sql: "DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
      arguments: [EntityName.aiChangelog, entityId])
    try db.execute(
      sql: """
        DELETE FROM sync_pending_inbox
        WHERE envelope_entity_type = ? AND envelope_entity_id = ?
        """,
      arguments: [EntityName.aiChangelog, entityId])
    // The obsolete marked-delete model must not leave a local death ledger that
    // would reject a legitimate same-id audit record in a later generation.
    try db.execute(
      sql: "DELETE FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
      arguments: [EntityName.aiChangelog, entityId])
  }
}
