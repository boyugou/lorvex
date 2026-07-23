import GRDB
import LorvexDomain
import LorvexStore

extension PendingInboxDrain {
  /// Promote an unparseable pending row to a permanent EXHAUSTED conflict and
  /// remove it. Synthesizes the conflict from the persisted identity columns so
  /// the diagnostic surface still records the poisoned identity even when the
  /// body is corrupt.
  static func quarantineUnparseableEntry(_ db: Database, id: Int64) throws {
    let row = try Row.fetchOne(
      db,
      sql: """
        SELECT envelope_entity_type, envelope_entity_id, envelope_version, envelope
        FROM sync_pending_inbox WHERE id = ?
        """,
      arguments: [id])
    guard let row else {
      // Row vanished between the drain SELECT and here — a concurrent writer won.
      return
    }
    let entityType: String = row["envelope_entity_type"]
    let entityID: String = row["envelope_entity_id"]
    let version: String = row["envelope_version"]
    let envelopeJSON: String = row["envelope"]
    try ConflictLog.logConflict(
      db,
      ConflictLog.Entry(
        entityType: entityType, entityId: entityID, winnerVersion: "", loserVersion: version,
        loserDeviceId: "", loserPayload: envelopeJSON,
        resolvedAt: SyncTimestampFormat.syncTimestampNow(),
        resolutionType: ResolutionName.pendingInboxExhausted))
    try recordQuarantine(
      db, entityType: entityType, entityID: entityID, version: version)
    try PendingInbox.removePending(db, id: id)
  }

  /// Whether the drain should write a one-time `fk_stalled` conflict-log row for
  /// a long-stalled (>1 hour) entry whose envelope hasn't already been logged.
  static func shouldLogStalled(
    _ db: Database, entry: PendingInbox.Entry, envelope: SyncEnvelope
  ) throws -> Bool {
    let olderThanOneHour =
      try Bool.fetchOne(
        db, sql: "SELECT ? < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 hour')",
        arguments: [entry.firstAttemptedAt]) ?? false
    if !olderThanOneHour {
      return false
    }
    let alreadyLogged =
      try Bool.fetchOne(
        db,
        sql: """
          SELECT EXISTS(
              SELECT 1 FROM sync_conflict_log
              WHERE resolution_type = ? AND entity_type = ? AND entity_id = ? AND loser_version = ?
          )
          """,
        arguments: [
          ResolutionName.fkStalled, envelope.entityType.asString, envelope.entityId,
          envelope.version.description,
        ]) ?? false
    return !alreadyLogged
  }

  static func logFkStalled(_ db: Database, envelope: SyncEnvelope) throws {
    try ConflictLog.logConflict(
      db,
      ConflictLog.Entry(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        winnerVersion: "", loserVersion: envelope.version.description,
        loserDeviceId: envelope.deviceId, loserPayload: envelope.payload,
        resolvedAt: SyncTimestampFormat.syncTimestampNow(),
        resolutionType: ResolutionName.fkStalled))
  }

  static func logFkUnresolvedDiscard(
    _ db: Database, envelope: SyncEnvelope, winnerVersion: String
  ) throws {
    try ConflictLog.logConflict(
      db,
      ConflictLog.Entry(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        winnerVersion: winnerVersion, loserVersion: envelope.version.description,
        loserDeviceId: envelope.deviceId, loserPayload: envelope.payload,
        resolvedAt: SyncTimestampFormat.syncTimestampNow(),
        resolutionType: ResolutionName.fkUnresolved))
  }

  static func logExhaustedConflict(_ db: Database, envelope: SyncEnvelope) throws {
    try ConflictLog.logConflict(
      db,
      ConflictLog.Entry(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        winnerVersion: "", loserVersion: envelope.version.description,
        loserDeviceId: envelope.deviceId, loserPayload: envelope.payload,
        resolvedAt: SyncTimestampFormat.syncTimestampNow(),
        resolutionType: ResolutionName.pendingInboxExhausted))
  }

  /// Build the error_logs message body for a permanent apply failure.
  static func syncErrorMessageForApplyFailure(
    _ entryID: Int64, _ envelope: SyncEnvelope, _ error: ApplyError
  ) -> String {
    let et = envelope.entityType.asString
    let eid = envelope.entityId
    switch error {
    case .transactionRequired:
      return
        "pending inbox entry \(entryID) (\(et)/\(eid)) attempted apply without an outer transaction"
    case .db(let msg), .dbBusyOrLocked(let msg), .dbConstraint(let msg):
      return msg
    case .invalidVersion(let msg):
      return "pending inbox entry \(entryID) (\(et)/\(eid)) has invalid version: \(msg)"
    case .unknownEntityType(let entityType):
      return "pending inbox entry \(entryID) (\(et)/\(eid)) has unknown entity type \(entityType)"
    case .invalidPayload(let msg):
      return "pending inbox entry \(entryID) (\(et)/\(eid)) has invalid payload: \(msg)"
    case .store(let msg):
      return msg
    case .entityRedirectCycle(let entityType, let entityId):
      return
        "pending inbox entry \(entryID) (\(et)/\(eid)) hit an entity redirect cycle resolving to "
        + "\(entityType) \(entityId)"
    case .entityRedirectChainTooDeep(let entityType, let entityId, let chainLength, let terminalId):
      return
        "pending inbox entry \(entryID) (\(et)/\(eid)) hit an entity redirect chain of \(chainLength)+ hops "
        + "resolving from \(entityType) \(entityId) (terminal id \(terminalId)) — refusing to apply"
    case .invalidOperation(let entityType, let operation):
      return
        "pending inbox entry \(entryID) (\(et)/\(eid)) carried an invalid operation '\(operation)' "
        + "for entity type '\(entityType)'"
    case .redirectPayloadTooLarge(let entityType, let entityId, let sizeBytes):
      return
        "pending inbox entry \(entryID) (\(et)/\(eid)) hit redirect-chase payload-size cap: "
        + "remapped to \(entityType.asString) \(entityId), canonical re-serialization is \(sizeBytes) bytes"
    case .dependencyCycleRejected(let taskId, let dependsOn):
      return
        "pending inbox entry \(entryID) (\(et)/\(eid)) dependency edge \(taskId)->\(dependsOn) "
        + "lost the cycle-break tiebreak and was dropped"
    case .deferForwardCompat(let reason):
      // Unreachable in practice: `Apply.applyEnvelope` converts this sentinel to
      // `.deferred` before it can surface as a drain apply failure. Rendered for
      // switch exhaustiveness only.
      return
        "pending inbox entry \(entryID) (\(et)/\(eid)) forward-compat retained: \(reason.message)"
    }
  }
}
