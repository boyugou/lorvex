import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension Outbox {

  /// Existing-row snapshot read ahead of the coalesce decision.
  private struct ExistingOutboxRow {
    var version: String
    var operation: String
    var payload: String
    var registerIntent: EntityRegisterIntent
    var disposition: Disposition?
    var futureRecordVersion: String?
  }

  /// Coalesced enqueue.
  ///
  /// If an unsynced entry for the same `(entity_type, entity_id)` already
  /// exists, replace it with the new envelope; otherwise insert a new entry.
  /// When the incoming envelope is stale relative to the queued one (LWW gate
  /// via typed `Hlc` compare), the existing row is preserved and the call is a
  /// no-op — except for an equal-version ordinary retry-wait row, which the
  /// full-resync backfill may replace to re-arm it immediately. An older
  /// envelope never replaces a newer queued row, regardless of retry state.
  ///
  /// Returns the new outbox id when a fresh row was inserted, and `nil` when the
  /// incoming envelope was stale and the existing row was preserved.
  ///
  /// Requires an outer transaction: the per-attempt SAVEPOINT contract assumes
  /// the connection is not in autocommit mode.
  @discardableResult
  public static func enqueueCoalesced(
    _ db: Database, _ envelope: SyncEnvelope,
    registerIntent: EntityRegisterIntent = .none
  ) throws -> Int64? {
    if case .failure(let err) = envelope.validate() {
      throw OutboxError.sql(
        "sync_outbox coalesced enqueue rejected malformed envelope: \(err.message)")
    }
    try requireOperationalWireVersion(envelope)
    do {
      try SyncPayloadContractRegistry.validate(envelope)
    } catch SyncPayloadContractError.violations(let violations) {
      throw OutboxError.invalidPayloadContract(violations.joined(separator: "; "))
    } catch let error as SyncPayloadContractError {
      throw OutboxError.payloadContractUnavailable(error.description)
    }
    let validatedRegisterIntent: EntityRegisterIntent
    do {
      validatedRegisterIntent = try registerIntent.validated(for: envelope)
    } catch {
      throw OutboxError.sql(
        "invalid entity register intent metadata for "
          + "\(envelope.entityType.asString)/\(envelope.entityId)")
    }

    // Bounded retry on the UNIQUE-partial-index race between concurrent
    // writers. Each attempt runs inside its own SAVEPOINT so a colliding INSERT
    // rolls back the body's DELETE, letting the next attempt's SELECT observe
    // the racing row's metadata.
    let maxConflictRetries: UInt32 = 3
    var attempt: UInt32 = 0
    while true {
      do {
        return try StoreTransactions.withSavepoint(db, "enqueue_coalesce_attempt") { db in
          try enqueueCoalescedBody(
            db, envelope, registerIntent: validatedRegisterIntent)
        }
      } catch let err as DatabaseError where err.isUniqueConstraintViolation {
        // The savepoint already rolled back. Retry; the next SELECT sees the
        // racing row.
        attempt += 1
        if attempt > maxConflictRetries {
          throw OutboxError.contentionExhausted(
            entityType: envelope.entityType, entityId: envelope.entityId, attempts: attempt)
        }
      }
    }
  }

  // MARK: - Single-attempt body

  private static func enqueueCoalescedBody(
    _ db: Database, _ envelope: SyncEnvelope,
    registerIntent: EntityRegisterIntent
  ) throws -> Int64? {
    let operationStr = envelope.operation.asString

    let existing = try Row.fetchOne(
      db,
      sql: """
        SELECT version, operation, payload, register_intent,
               disposition, future_record_version
        FROM sync_outbox
        WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
        LIMIT 1
        """,
      arguments: [envelope.entityType.asString, envelope.entityId]
    ).map {
      let operationRaw: String = $0["operation"]
      let operation = SyncOperation(rawValue: operationRaw)
      let payload: String = $0["payload"]
      let rawIntent: Int64 = $0["register_intent"]
      guard let operation else {
        throw OutboxError.sql("sync_outbox contains an invalid operation")
      }
      let storedIntent: EntityRegisterIntent
      do {
        storedIntent = try EntityRegisterIntent.validatedStored(
          rawValue: rawIntent, entityType: envelope.entityType,
          operation: operation, payload: payload)
      } catch {
        throw OutboxError.sql(
          "sync_outbox contains invalid entity register intent metadata for "
            + "\(envelope.entityType.asString)/\(envelope.entityId)")
      }
      return ExistingOutboxRow(
        version: $0["version"], operation: operationRaw,
        payload: payload,
        registerIntent: storedIntent,
        disposition: ($0["disposition"] as String?).flatMap(Disposition.init),
        futureRecordVersion: $0["future_record_version"])
    }

    if let existing, existing.disposition == .futureRecordHold {
      throw OutboxError.futureRecordRequiresNewerApp(
        entityType: envelope.entityType, entityId: envelope.entityId,
        heldVersion: existing.futureRecordVersion ?? existing.version)
    }

    // Stale-snapshot guard: never let an older-HLC enqueue overwrite a queued
    // newer edit. Typed HLC compare; a tainted existing version makes the
    // canonical incoming the unambiguous winner.
    //
    // A queued ordinary retry-wait row is the exception: the SY1
    // full-resync backfill (recovery of last resort) re-emits it at its stored —
    // hence equal — version, and the plain no-op path would otherwise leave it
    // waiting for the scheduled retry. So an equal-version retry-wait row falls
    // through to the replacement path below and resets its retry state.
    // An OLDER incoming version remains stale even for retry wait: reviving it
    // would replace a newer queued edit with obsolete content.
    // An authoritative-adoption fence is NOT recoverable this way; only a newer
    // HLC (a genuine post-adoption edit) may replace it.
    if let existingRow = existing,
      let existingHlc = try? Hlc.parseCanonical(existingRow.version)
    {
      if envelope.version < existingHlc
        || (envelope.version == existingHlc
          && existingRow.disposition != .retryWait)
      {
        return nil
      }
    }

    if let existingRow = existing {
      try recordCoalescedDeleteDropped(db, envelope, existing: existingRow)
    }

    let effectiveRegisterIntent: EntityRegisterIntent
    if let existing,
      existing.operation == SyncNaming.opUpsert,
      envelope.operation == .upsert,
      existing.disposition != .authoritativeAdoption
    {
      let retained = existing.registerIntent.retainingUnchangedRegisters(
        existingPayload: existing.payload, replacementPayload: envelope.payload)
      do {
        effectiveRegisterIntent = try retained.union(registerIntent)
      } catch {
        throw OutboxError.sql(
          "sync_outbox register intent entity kind changed during coalescing for "
            + "\(envelope.entityType.asString)/\(envelope.entityId)")
      }
    } else {
      effectiveRegisterIntent = registerIntent
    }

    try db.execute(
      sql: """
        DELETE FROM sync_outbox
        WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
        """,
      arguments: [envelope.entityType.asString, envelope.entityId])

    let now = SyncTimestampFormat.syncTimestampNow()
    try db.execute(
      sql: """
        INSERT INTO sync_outbox
            (entity_type, entity_id, operation, version,
             payload_schema_version, payload, register_intent,
             device_id, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        envelope.entityType.asString,
        envelope.entityId,
        operationStr,
        envelope.version.description,
        envelope.payloadSchemaVersion,
        envelope.payload,
        effectiveRegisterIntent.rawValue,
        envelope.deviceId,
        now,
      ])
    return db.lastInsertedRowID
  }

  // MARK: - Dropped-Delete audit

  /// Audit-log the dropped Delete envelope when an Upsert is about to coalesce
  /// over a queued Delete (`Upsert(T1) → Delete(T2) → Upsert(T3)` collapses to
  /// `Upsert(T3)`). Records a **device-local** `ai_changelog` row with operation
  /// `sync.outbox.coalesced_delete_dropped` so this device retains a forensic
  /// record that an intermediate outbound Delete was superseded before it left
  /// the outbox.
  ///
  /// The row is written directly via ``ChangelogWrite/writeChangelogRow(_:_:)``
  /// and is intentionally NOT enqueued to the sync outbox: unlike the app-layer
  /// changelog emit path, this records a decision about *this* device's outbound
  /// queue. Peers only ever receive the superseding `Upsert(T3)` (the Delete
  /// never reached the zone), so there is no lost Delete for them to reconstruct
  /// — and the summary is worded local-only to say so. Only fires on
  /// Delete-existing + Upsert-incoming. Best-effort: a changelog write failure
  /// is swallowed; the coalesce itself is the authoritative mutation.
  private static func recordCoalescedDeleteDropped(
    _ db: Database, _ envelope: SyncEnvelope, existing: ExistingOutboxRow
  ) throws {
    guard existing.operation == SyncNaming.opDelete, envelope.operation == .upsert else {
      return
    }
    // This writes NEW local audit content (a `sync.outbox.coalesced_delete_dropped`
    // row), so honor the "never store" changelog policy: under `.off` write
    // nothing. Existing rows are purged by the retention sweep regardless.
    guard ChangelogRetentionPolicy.read(db) != .off else { return }
    let summary =
      "local outbox coalesce dropped a queued Delete before it was pushed: "
      + "entity_type=\(envelope.entityType.asString), entity_id=\(envelope.entityId), "
      + "dropped_delete_version=\"\(existing.version)\", "
      + "superseding_upsert_version=\(envelope.version.description); this device-local audit "
      + "records that the intermediate Delete never left the outbox — the superseding Upsert is "
      + "the state peers receive"
    guard let deviceId = try? SyncCheckpoints.getOrCreateDeviceId(db) else {
      return
    }
    let id = EntityID.newEntityIDString()
    let timestamp = SyncTimestampFormat.syncTimestampNow()
    let sanitized = ChangelogWrite.sanitizeChangelogSummary(summary)
    let row = ChangelogWrite.ChangelogRow(
      id: id,
      timestamp: timestamp,
      operation: SyncNaming.localAuditCoalescedDeleteDropped,
      entityType: envelope.entityType.asString,
      entityId: envelope.entityId,
      entityIds: [],
      summary: sanitized,
      initiatedBy: "sync",
      mcpTool: nil,
      sourceDeviceId: deviceId,
      beforeJson: nil,
      afterJson: nil)
    try? ChangelogWrite.writeChangelogRow(db, row)
  }
}
