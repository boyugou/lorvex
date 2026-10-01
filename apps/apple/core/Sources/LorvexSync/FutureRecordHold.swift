import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Fail-closed ownership of a CloudKit identity occupied by data this build
/// cannot yet interpret.
///
/// The remote envelope remains durable in the pending inbox. Any already-queued
/// local intent is kept byte-for-byte in `sync_outbox`, but fenced from
/// transport until a later build fully understands a terminal envelope at the
/// held version or above; the two are then resolved by last-writer-wins.
public enum FutureRecordHold {
  static let fenceError =
    "local intent fenced: the CloudKit identity contains a future-authored record"

  /// Classify a canonical external HLC against the static successor-headroom
  /// boundary. This deliberately does not consult wall time: ordinary bad-RTC
  /// or far-future peers remain accepted and editable via the detached HLC lane.
  public static func clockDeferralReason(for version: Hlc) -> DeferralReason? {
    guard !Hlc.hasOperationalWireSuccessor(after: version) else { return nil }
    return .operationallyUnusableHlc(
      remoteVersion: version,
      maximumOperationalPhysicalMs: Hlc.maxOperationalWirePhysicalMs)
  }

  /// Cheap common-path probe for outbound defense-in-depth. Correct insertion
  /// paths fence the unique outbox row immediately, so an active row needs the
  /// more expensive identity lookup only while future provenance exists in the
  /// pending inbox. This avoids an N+1 query on every ordinary outbox flush.
  static func hasPotentialBlockingProvenance(_ db: Database) throws -> Bool {
    try Int.fetchOne(
      db,
      sql: """
        SELECT EXISTS(
          SELECT 1 FROM sync_pending_inbox
          WHERE \(PendingInboxDrain.futureRecordReasonSQL(column: "reason"))
        )
        """) == 1
  }

  /// Maximum future-authored HLC currently known for this identity: durable
  /// inbox provenance and the outbox fence's stored floor.
  static func blockingVersion(
    _ db: Database, entityType: String, entityId: String
  ) throws -> Hlc? {
    var maximum: Hlc?
    func observe(_ raw: String) throws {
      let value = try Hlc.parseCanonical(raw)
      maximum = maximum.map { max($0, value) } ?? value
    }

    let pending = try String.fetchAll(
      db,
      sql: """
        SELECT envelope_version
        FROM sync_pending_inbox
        WHERE envelope_entity_type = ? AND envelope_entity_id = ?
          AND (\(PendingInboxDrain.futureRecordReasonSQL(column: "reason")))
        """,
      arguments: [entityType, entityId])
    for raw in pending { try observe(raw) }

    if let fenced: String = try String.fetchOne(
      db,
      sql: """
        SELECT future_record_version
        FROM sync_outbox
        WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          AND disposition = ?
        LIMIT 1
        """,
      arguments: [
        entityType, entityId, Outbox.Disposition.futureRecordHold.rawValue,
      ])
    {
      try observe(fenced)
    }

    return maximum
  }

  static func requireWriteAllowed(
    _ db: Database, entityType: String, entityId: String
  ) throws {
    if let held = try blockingVersion(db, entityType: entityType, entityId: entityId) {
      throw EnqueueError.futureRecordRequiresNewerApp(
        entityType: entityType, entityId: entityId, heldVersion: held.description)
    }
  }

  /// Preserve but permanently remove the active transport eligibility of any
  /// local intent for this identity. Repeated future observations monotonically
  /// raise the stored remote floor.
  static func fenceExistingLocalIntent(
    _ db: Database, entityType: String, entityId: String, heldVersion: String
  ) throws {
    let held = try Hlc.parseCanonical(heldVersion)
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT id, future_record_version
          FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          LIMIT 1
          """,
        arguments: [entityType, entityId])
    else { return }
    let priorRaw: String? = row["future_record_version"]
    let floor = try priorRaw.map(Hlc.parseCanonical).map { max($0, held) } ?? held
    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET retry_count = ?, consecutive_error_count = 0,
            last_error = ?, disposition = ?, next_retry_at = NULL,
            future_record_version = ?
        WHERE id = ? AND synced_at IS NULL
          AND (disposition IS NULL OR disposition IN (?, ?))
        """,
      arguments: [
        Outbox.maxRetries, Outbox.truncateOutboxLastError(fenceError),
        Outbox.Disposition.futureRecordHold.rawValue, floor.description,
        row["id"] as Int64,
        Outbox.Disposition.retryWait.rawValue,
        Outbox.Disposition.futureRecordHold.rawValue,
      ])
  }

  /// A terminal, fully-understood envelope proves that same-version and older
  /// future provenance is no longer opaque. Higher holds remain untouched.
  static func removeUnderstoodProvenance(
    _ db: Database, envelope: SyncEnvelope
  ) throws {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, envelope_version
        FROM sync_pending_inbox
        WHERE envelope_entity_type = ? AND envelope_entity_id = ?
          AND (\(PendingInboxDrain.futureRecordReasonSQL(column: "reason")))
        """,
      arguments: [envelope.entityType.asString, envelope.entityId])
    for row in rows {
      let held = try Hlc.parseCanonical(row["envelope_version"] as String)
      if held <= envelope.version {
        try PendingInbox.removePending(db, id: row["id"])
      }
    }
  }

  /// Reconcile a preserved local intent after a terminal typed envelope catches
  /// up with its remote future floor, by last-writer-wins: when the local
  /// intent's canonical state beat the envelope, it is re-queued at its
  /// winning version; otherwise the fence is dropped, re-staging any grouped
  /// registers the join kept.
  public static func reconcileTerminalEnvelope(
    _ db: Database, envelope: SyncEnvelope, outcome: ApplyResult
  ) throws {
    try removeUnderstoodProvenance(db, envelope: envelope)
    guard
      let fence = try Row.fetchOne(
        db,
        sql: """
          SELECT id, entity_type, entity_id, operation, version,
                 payload_schema_version, payload, register_intent,
                 device_id, created_at, future_record_version
          FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            AND disposition = ?
          LIMIT 1
          """,
        arguments: [
          envelope.entityType.asString, envelope.entityId,
          Outbox.Disposition.futureRecordHold.rawValue,
        ])
    else { return }
    let heldFloor = try Hlc.parseCanonical(fence["future_record_version"] as String)
    guard envelope.version >= heldFloor else { return }

    let localWinner: Hlc?
    if case .skipped(_, let winner) = outcome, let winner, winner > envelope.version
    {
      localWinner = winner
    } else {
      localWinner = nil
    }
    try db.execute(sql: "DELETE FROM sync_outbox WHERE id = ?", arguments: [fence["id"] as Int64])
    if let localWinner {
      _ = try rebuildCurrentCanonicalIntent(
        db, fence: fence, minimumVersion: localWinner,
        requireSurvivingRegisterIntent: false)
    } else if fence["register_intent"] as Int64 != 0 {
      switch outcome {
      case .applied, .repairRequired:
        // Both outcomes have materialized the grouped join at the original
        // identity. A repair obligation changes related or derived state after
        // this call, so first re-stage every byte-identical user-authored
        // register; the repair enqueue then coalesces over it and keeps exactly
        // the groups that still survive its fresh-HLC rewrite.
        _ = try rebuildCurrentCanonicalIntent(
          db, fence: fence, minimumVersion: nil,
          requireSurvivingRegisterIntent: true)
      case .remapped:
        // A permanent alias made the fenced source identity terminal. Its
        // register provenance cannot be transferred to the target: the target
        // may have won an aggregate merge with different register bytes. The
        // caller separately emits the canonical target as convergence state.
        break
      case .skipped, .deferred:
        // A dominating local skip was handled by `localWinner` above. Exact or
        // older terminal skips do not prove that any fenced register survived,
        // and a deferral is never reconciled by the inbound callers.
        break
      }
    }
  }

  /// Rebuild one preserved intent from live canonical state (or its canonical
  /// tombstone). Returns false when neither exists at `minimumVersion` or
  /// above, in which case there is no local intent left to emit.
  @discardableResult
  private static func rebuildCurrentCanonicalIntent(
    _ db: Database, fence: Row, minimumVersion: Hlc?,
    requireSurvivingRegisterIntent: Bool = false
  ) throws -> Bool {
    let entityType: String = fence["entity_type"]
    let entityId: String = fence["entity_id"]
    let deviceId: String = fence["device_id"]
    if let liveRaw = try ApplyLww.getLocalVersion(
      db, entityType: entityType, entityId: entityId),
      let live = try? Hlc.parseCanonical(liveRaw),
      minimumVersion.map({ live >= $0 }) ?? true
    {
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: entityType, entityId: entityId)
      guard let kind = EntityKind.parse(entityType),
        let operation = SyncOperation(rawValue: fence["operation"] as String)
      else {
        throw FutureRecordHoldError.invalidPreservedIntent
      }
      let preservedIntent: EntityRegisterIntent
      do {
        preservedIntent = try EntityRegisterIntent.validatedStored(
          rawValue: fence["register_intent"] as Int64,
          entityType: kind, operation: operation, payload: fence["payload"])
      } catch {
        throw FutureRecordHoldError.invalidPreservedIntent
      }
      let currentPayload = try SyncCanonicalize.canonicalizeJSON(payload)
      let registerIntent = preservedIntent.retainingUnchangedRegisters(
        existingPayload: fence["payload"], replacementPayload: currentPayload)
      if requireSurvivingRegisterIntent, registerIntent.isEmpty {
        return false
      }
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: entityType, entityId: entityId, payload: payload,
        context: OutboxWriteContext(
          version: live.description, deviceId: deviceId,
          registerIntent: registerIntent))
      return true
    }
    if let tombstone = try Tombstone.getTombstone(
      db, entityType: entityType, entityId: entityId),
      let death = try? Hlc.parseCanonical(tombstone.version),
      minimumVersion.map({ death >= $0 }) ?? true
    {
      try OutboxEnqueue.enqueuePayloadDelete(
        db, entityType: entityType, entityId: entityId,
        payload: .object(["version": .string(death.description)]),
        context: OutboxWriteContext(version: death.description, deviceId: deviceId))
      return true
    }

    return false
  }
}

public enum FutureRecordHoldError: Error, Sendable, Equatable {
  case invalidPreservedIntent
}
