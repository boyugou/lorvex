import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Forward-compat payload-shadow promotion.
///
/// A peer on a newer payload schema can send fields this build's parser does not
/// understand; apply stores the unknown-key payload shadow and lands the
/// locally-known truncated row. Once the local build understands the shadowed
/// schema version, promotion reconstructs a full payload from the live row's
/// canonical known fields plus the shadow's preserved forward-compat keys, then
/// dispatches that payload as if the envelope had arrived under today's schema.
/// Without that reconstruction, a stripped shadow is not a valid upsert payload
/// and promotion fails forever. Run by startup maintenance.
public enum ApplyPromote {
  /// Promote every shadow whose schema version is now understood
  /// (`<= LorvexVersion.payloadSchemaVersion`) into the canonical tables, then
  /// clear the promoted shadow rows. Returns the number promoted.
  ///
  /// Each shadow promotes inside its own savepoint so one bad row only loses
  /// its own work: the surrounding transaction and every other promoted shadow
  /// stay committed, and the bad row stays in `sync_payload_shadow` for a
  /// future pass. A per-row failure is logged to `error_logs` and the loop
  /// continues.
  @discardableResult
  public static func promotePayloadShadows(
    _ db: Database, registry: EntityApplierRegistry
  ) throws -> Int {
    // One apply timestamp for the whole pass so every row's conflict-log /
    // tombstone writes correlate to the same moment of promotion.
    let applyTs = SyncTimestampFormat.syncTimestampNow()
    var promoted = 0
    for row in try PayloadShadow.listShadows(db) {
      // SQLite stores this as a signed INTEGER while SyncEnvelope carries a
      // UInt32. Validate the persisted boundary before either comparing it with
      // the local schema or converting it: legacy/corrupt zero, negative, or
      // wider-than-UInt32 rows must remain recoverable instead of trapping the
      // startup maintenance pass or being silently normalized.
      guard
        let payloadSchemaVersion = UInt32(exactly: row.payloadSchemaVersion),
        payloadSchemaVersion >= 1
      else {
        ErrorLog.appendBestEffort(
          db, source: "sync.apply.promote_shadow_invalid_schema_version",
          message:
            "payload shadow \(row.entityType.asString):\(row.entityID) has invalid "
            + "payload_schema_version \(row.payloadSchemaVersion); retaining it for recovery",
          details: nil, level: "error")
        continue
      }
      if payloadSchemaVersion > LorvexVersion.payloadSchemaVersion { continue }
      do {
        let didPromote = try StoreTransactions.withSavepoint(db, "promote_payload_shadow") {
          db in
          try promoteOneShadow(
            db, registry: registry, row: row,
            payloadSchemaVersion: payloadSchemaVersion, applyTs: applyTs)
        }
        if didPromote { promoted += 1 }
      } catch {
        ErrorLog.appendBestEffort(
          db, source: "sync.apply.promote_shadow_failed",
          message: "shadow promotion failed for \(row.entityType.asString):\(row.entityID) "
            + "version \(row.baseVersion): \(error)",
          details: nil, level: "error")
      }
    }
    return promoted
  }

  /// Promote a single shadow row. Returns `true` when the shadow landed in a
  /// canonical row; `false` when it was handled by a non-promote path
  /// (authoritative tombstone drop, version/provenance mismatch retained for
  /// repair, FK defer to the pending inbox). Errors propagate so the caller's
  /// savepoint rolls just this row back.
  ///
  /// The path follows `Apply.applyEnvelope` keyed on the redirect terminus:
  /// permanent-alias chase → tombstone-on-target check → equal-version
  /// provenance gate → FK preflight → dispatch.
  private static func promoteOneShadow(
    _ db: Database, registry: EntityApplierRegistry, row: PayloadShadow.Row,
    payloadSchemaVersion: UInt32, applyTs: String
  ) throws -> Bool {
    // Resolve a permanent alias at the shadow's original identity first. A
    // shadow authored before an aggregate merge must promote onto the merge
    // WINNER, not land as a phantom row at the loser id. A non-alias tombstone
    // is handled by the version-aware target gate below: an at/newer delete may
    // discard the shadow, while an older barrier is lifted only after a complete
    // equal-version live payload is available for dispatch.
    let promoteType: String
    let promoteId: String
    if try EntityRedirect.get(
      db, sourceType: row.entityType.asString, sourceId: row.entityID) != nil
    {
      let chase = try ApplyRedirect.chaseRedirectChain(
        db, initialEntityType: row.entityType.asString, initialEntityId: row.entityID)
      promoteType = chase.finalType
      promoteId = chase.finalId
    } else {
      promoteType = row.entityType.asString
      promoteId = row.entityID
    }

    // Storage holds canonical HLC strings; a parse failure here is corruption
    // that survived upsertShadow's checks (old data, a manual DB edit). The row is
    // the only preserved copy of fields this runtime previously did not know, so
    // corruption blocks promotion but never authorizes destructive cleanup.
    let baseHlc: Hlc
    do {
      baseHlc = try Hlc.parseCanonical(row.baseVersion)
    } catch {
      ErrorLog.appendBestEffort(
        db, source: "sync.apply.promote_shadow_corrupt_base_version",
        message:
          "payload shadow \(row.entityType.asString):\(row.entityID) has a corrupt "
          + "base_version '\(row.baseVersion)' that cannot be promoted; retaining for repair",
        details: nil, level: "error")
      return false
    }

    // Shadow rows with no recorded device_id derive a synthetic attribution
    // from the HLC's device suffix; the prefix keeps synthetic-vs-real visible
    // to diagnostics (real device ids are hyphenated UUIDs).
    let deviceId =
      row.sourceDeviceID.isEmpty
      ? "shadow-suffix:\(baseHlc.deviceSuffix)" : row.sourceDeviceID

    // (a) A REAL (non-redirect) tombstone at the promote target: the shadow
    // must not resurrect a deletion. At/below the tombstone version → drop the
    // shadow; strictly newer → concurrent-update-wins-over-concurrent-delete,
    // lift the tombstone and fall through, matching the redirect apply path.
    var targetTombstoneToLift = false
    if let targetTs = try Tombstone.getTombstone(
      db, entityType: promoteType, entityId: promoteId)
    {
      let targetTsVersion = try Hlc.parseCanonical(targetTs.version)
      if baseHlc <= targetTsVersion {
        // The shadow table is keyed at the ORIGINAL identity regardless of
        // where the chase landed.
        try PayloadShadow.removeShadow(
          db, entityType: row.entityType.asString, entityID: row.entityID)
        return false
      }
      // Do not lift the barrier yet. The shadow contains only unknown fields;
      // promotion still needs an equal-version live row to reconstruct the known
      // payload. A later mismatch/FK defer must retain BOTH the shadow and this
      // deletion barrier. Lift immediately before a dispatch that can commit.
      targetTombstoneToLift = true
    }

    // (b) Provenance gate against the live row at the promote target. Promotion
    // is sound only when the known row and shadow describe the SAME versioned
    // snapshot. HLC ordering alone cannot prove a legacy writer understood or
    // intentionally cleared future fields. Any mismatch/corruption is retained
    // and logged for repair; only exact equality reaches allow-equal dispatch.
    let localVersionStr = try ApplyLww.getLocalVersion(
      db, entityType: promoteType, entityId: promoteId)
    if let localVersionStr {
      if let localVersion = try? Hlc.parseCanonical(localVersionStr) {
        if localVersion != baseHlc {
          ErrorLog.appendBestEffort(
            db, source: "sync.apply.promote_shadow_version_mismatch",
            message:
              "payload shadow \(row.entityType.asString):\(row.entityID) cannot promote onto "
              + "\(promoteType):\(promoteId): live version \(localVersionStr) does not equal "
              + "shadow base_version \(row.baseVersion); retaining shadow for repair",
            details: nil, level: "error")
          return false
        }
      } else {
        ErrorLog.appendBestEffort(
          db, source: "sync.apply.local_version_corruption",
          message: "local version '\(localVersionStr)' on \(promoteType):\(promoteId) "
            + "is not a valid HLC; retaining payload shadow for repair",
          details: nil, level: "error")
        return false
      }
    } else {
      ErrorLog.appendBestEffort(
        db, source: "sync.apply.promote_shadow_unavailable_live_payload",
        message:
          "payload shadow \(row.entityType.asString):\(row.entityID) cannot promote onto "
          + "\(promoteType):\(promoteId): live row is missing; retaining shadow because full "
          + "known payload is unavailable",
        details: nil, level: "error")
      return false
    }

    guard let promoteKind = EntityKind.parse(promoteType) else {
      throw ApplyError.unknownEntityType(promoteType)
    }
    let promotedPayload = try reconstructedPromotePayload(
      db, row: row, promoteType: promoteType, promoteId: promoteId)
    let envelope = SyncEnvelope(
      entityType: promoteKind, entityId: promoteId, operation: .upsert,
      version: baseHlc, payloadSchemaVersion: payloadSchemaVersion,
      payload: promotedPayload, deviceId: deviceId)

    // (c) FK preflight last (after the provenance gate). A
    // missing parent parks the synthesized envelope in the pending inbox —
    // upsert-keyed, so repeat passes don't flood it — and leaves the shadow in
    // place; the FK-arrival drain replays the envelope and clears the shadow
    // once the parent lands.
    if let (depKind, depId) = try ApplyFk.checkFkDependencies(
      db, entityType: promoteType, entityId: promoteId, payload: envelope.payload)
    {
      try PendingInboxDrain.enqueueDeferred(
        db, envelope: envelope,
        reason: .missingDependency(entityType: depKind, entityId: depId))
      return false
    }

    if targetTombstoneToLift {
      _ = try Tombstone.removeTombstone(db, entityType: promoteType, entityId: promoteId)
    }

    // The exact live/base provenance proof above authorizes one explicit
    // equal-version projection repair. Grouped aggregates distinguish this
    // from ordinary allow-equal replay so a newly understood shadow field
    // cannot lose to the truncated live projection's byte ordering.
    _ = try ApplyDispatch.dispatch(
      db, registry: registry, envelope: envelope, tieBreak: .shadowPromotion, applyTs: applyTs)
    // Clear the shadow at the ORIGINAL identity (the table is keyed there even
    // when the promotion landed at a redirect target).
    try PayloadShadow.removeShadowIfSuperseded(
      db, entityType: row.entityType.asString, entityID: row.entityID,
      version: row.baseVersion)
    return true
  }

  private static func reconstructedPromotePayload(
    _ db: Database, row: PayloadShadow.Row, promoteType: String, promoteId: String
  ) throws -> String {
    let knownPayload = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: promoteType, entityId: promoteId)
    let merged = try PayloadShadow.mergePayloadForPromotion(
      db, entityType: promoteType, entityID: promoteId, knownPayload: knownPayload,
      shadow: row)
    do {
      return try SyncCanonicalize.canonicalizeJSON(merged)
    } catch { throw ApplyError.lift(error) }
  }
}
