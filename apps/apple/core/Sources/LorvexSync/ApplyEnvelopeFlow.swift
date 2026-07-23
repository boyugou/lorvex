import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-stage flow helpers for ``Apply/applyEnvelope(_:registry:envelope:)`` —
/// the tombstone gate, the LWW + FK gate, payload-shadow preparation, the
/// delete-flow tombstone-vs-defer decision, and the redirect-flow orchestrator.

// MARK: - Payload shadow preparation

enum ApplyPayloadShadow {
  /// Prepare the forward-compat payload shadow immediately before dispatching
  /// an admitted upsert. This must run before the applier: a natural-key merge
  /// can delete/redirect the incoming identity and enqueue the surviving row
  /// inside dispatch, so post-dispatch shadow storage strands future fields on
  /// the dead loser. The enclosing per-envelope savepoint rolls this mutation
  /// back if dispatch throws or defers.
  static func prepareForUpsertDispatch(
    _ db: Database, acceptance: EnvelopeAcceptance, envelope: SyncEnvelope
  ) throws {
    do {
      switch acceptance {
      case .rejectInvalid, .deferToPendingInbox:
        break
      case .parseForwardCompat:
        try PayloadShadow.upsertShadow(
          db, entityType: envelope.entityType.asString, entityID: envelope.entityId,
          baseVersion: envelope.version.description,
          payloadSchemaVersion: Int(envelope.payloadSchemaVersion),
          rawPayloadJSON: envelope.payload, sourceDeviceID: envelope.deviceId)
      case .parseFully:
        try PayloadShadow.prepareForKnownSchemaUpsert(
          db, entityType: envelope.entityType.asString, entityID: envelope.entityId,
          incomingPayloadSchemaVersion: Int(envelope.payloadSchemaVersion),
          incomingVersion: envelope.version.description)
      }
    } catch { throw ApplyError.lift(error) }
  }
}

// MARK: - Tombstone gate (non-redirect)

enum ApplyTombstoneGate {
  /// Gate an envelope against an existing ordinary tombstone. Returns a
  /// terminal ``ApplyResult`` for the skip / advance-frontier paths, or `nil`
  /// when the upsert beat the tombstone and apply should continue.
  static func gateExistingTombstone(
    _ db: Database, envelope: SyncEnvelope, ts: Tombstone.Record, applyTs: String
  ) throws -> ApplyResult? {
    let tombstoneVersion: Hlc
    do {
      tombstoneVersion = try Hlc.parseCanonical(ts.version)
    } catch { throw ApplyError.invalidVersion("\(error)") }
    let envelopeVersion = envelope.version

    if envelope.operation == .upsert {
      if envelopeVersion > tombstoneVersion {
        // Concurrent-update-wins-over-concurrent-delete: the upsert is strictly
        // newer. Log the resolution, remove the tombstone, then fall through.
        do {
          try ConflictLog.logConflict(
            db,
            ConflictLog.Entry(
              entityType: envelope.entityType.asString, entityId: envelope.entityId,
              winnerVersion: envelope.version.description, loserVersion: ts.version,
              loserDeviceId: envelope.deviceId, loserPayload: nil, resolvedAt: applyTs,
              resolutionType: ResolutionName.upsertWinsOverDelete))
          _ = try Tombstone.removeTombstone(
            db, entityType: envelope.entityType.asString, entityId: envelope.entityId)
        } catch { throw ApplyError.lift(error) }
        return nil
      } else {
        // Delete is newer or concurrent-equal: discard the upsert.
        let requiresAuditRetentionCleanup = envelope.entityType == .aiChangelog
        do {
          try ConflictLog.logConflict(
            db,
            ConflictLog.Entry(
              entityType: envelope.entityType.asString, entityId: envelope.entityId,
              winnerVersion: ts.version, loserVersion: envelope.version.description,
              loserDeviceId: envelope.deviceId,
              // A rejected audit payload is exactly the private history the
              // reset tombstone and physical-purge queue exist to remove. Copying it into the
              // conflict log would silently retain that content under another
              // table even for the `.off` policy.
              loserPayload: requiresAuditRetentionCleanup ? nil : envelope.payload,
              resolvedAt: applyTs, resolutionType: ResolutionName.tombstoneWins))
        } catch { throw ApplyError.lift(error) }
        try ApplyConflict.reapShadowForSkipped(
          db, entityType: envelope.entityType.asString, entityId: envelope.entityId,
          supersedingVersion: ts.version)
        if requiresAuditRetentionCleanup {
          guard case .object(let object)? = JSONValue.parse(envelope.payload) else {
            throw ApplyError.invalidPayload("malformed ai_changelog payload JSON")
          }
          let epoch = try ApplyJSON.requiredInt64(
            object, "retention_epoch", entity: EntityName.aiChangelog)
          guard epoch >= 0 else {
            throw ApplyError.invalidPayload(
              "ai_changelog payload: retention_epoch must be nonnegative")
          }
          try AuditRetentionFrontier.rejectInboundAuditAndQueuePurge(
            db, entityId: envelope.entityId, retentionEpoch: epoch,
            reason: .resetTombstone)
          return .upsertRejectedByRetention
        }
        return .skipped(
          reason: "entity \(envelope.entityType.asString):\(envelope.entityId) is tombstoned "
            + "with version \(ts.version) >= envelope version \(envelope.version)",
          winnerVersion: tombstoneVersion)
      }
    }
    // Delete operation.
    if envelopeVersion > tombstoneVersion {
      // The row is already gone, but a later delete advances the delete
      // frontier. Write the tombstone at the newer HLC.
      do {
        try Tombstone.createTombstone(
          db, entityType: envelope.entityType.asString, entityId: envelope.entityId,
          version: envelope.version.description, deletedAt: applyTs)
      } catch { throw ApplyError.lift(error) }
      return .applied
    }
    // Older/equal replays remain idempotent no-ops. Reap any obsolete shadow.
    try ApplyConflict.reapShadowForSkipped(
      db, entityType: envelope.entityType.asString, entityId: envelope.entityId,
      supersedingVersion: ts.version)
    return .skipped(
      reason: "entity \(envelope.entityType.asString):\(envelope.entityId) is already "
        + "tombstoned at version \(ts.version) >= delete envelope version \(envelope.version)",
      winnerVersion: tombstoneVersion)
  }
}

// MARK: - LWW + FK gate

enum ApplyLwwGate {
  /// The synced timezone is an upsert-only global authority. Intercept its
  /// Delete before the equal-HLC and tombstone gates so no peer can leave a
  /// durable shared tombstone that makes devices derive different logical days.
  static func requiredTimezoneDeleteRepair(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> ApplyResult? {
    guard envelope.entityType == .preference,
      envelope.entityId == PreferenceKeys.prefTimezone,
      envelope.operation == .delete
    else { return nil }

    let object = try ApplyJSON.parseObject(envelope.payload)
    let fallbackValue: JSONValue
    if let wireValue = object["value"] {
      let candidate: JSONValue
      if case .string(let rawStoredValue) = wireValue,
        let decodedStoredValue = JSONValue.parse(rawStoredValue)
      {
        candidate = decodedStoredValue
      } else {
        candidate = wireValue
      }
      switch PreferenceValueContract.normalize(
        key: PreferenceKeys.prefTimezone, value: candidate)
      {
      case .success(let normalized): fallbackValue = normalized
      case .failure:
        fallbackValue = .string("UTC")
      }
    } else {
      fallbackValue = .string("UTC")
    }
    let fallbackUpdatedAt: String
    if case .string(let updatedAt)? = object["updated_at"] {
      fallbackUpdatedAt = updatedAt
    } else {
      fallbackUpdatedAt = applyTs
    }
    return .repairRequired(
      .reassertRequiredTimezone(
        fallbackValue: fallbackValue, fallbackUpdatedAt: fallbackUpdatedAt,
        remoteDeleteVersion: envelope.version))
  }

  /// A calendar-series cutover is an upsert-only remove-wins register. Invalid
  /// peer Deletes must be intercepted before the generic equal-HLC, tombstone,
  /// and whole-row LWW gates: those gates can otherwise turn a repairable
  /// shared-record deletion into a skip or an ordinary GC-able tombstone.
  static func requiredCutoverDeleteRepair(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> ApplyResult? {
    guard envelope.entityType == .calendarSeriesCutover,
      envelope.operation == .delete
    else { return nil }
    guard try CalendarSeriesCutoverRepo.fetch(db, id: envelope.entityId) != nil else {
      throw ApplyError.invalidPayload(
        "calendar_series_cutover Delete is invalid and no local boundary exists to reassert")
    }
    return .repairRequired(
      .reassertCalendarSeriesCutover(
        entityId: envelope.entityId, remoteDeleteVersion: envelope.version))
  }

  /// Resolve the otherwise non-convergent equal-HLC case before either the
  /// tombstone or live-row LWW gate turns it into a permanent local-wins skip.
  /// Exact semantic replay is a no-op. Different semantic mutations are joined
  /// deterministically and surfaced as a repair obligation so the host can
  /// re-author the winner at a strict successor in the consuming transaction.
  static func gateEqualVersionMutation(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> ApplyResult? {
    // Cutovers are an upsert-only remove-wins semilattice, not a whole-row LWW
    // register. Both equal-state joins and invalid Deletes must reach their
    // applier; the generic byte winner could otherwise select `active` or mint
    // an ordinary tombstone over the permanent fence.
    if envelope.entityType == .calendarSeriesCutover { return nil }
    guard let local = try localMutationAtSameVersion(db, envelope: envelope) else {
      return nil
    }
    do {
      if try SyncMutationSemantics.isExactSemanticReplay(local, envelope) {
        // Audit rows are immutable-by-id rather than LWW-versioned. Let their
        // applier run even for an exact replay so account-scoped retention can
        // record cloud presence or reject-and-purge the row. Every ordinary
        // versioned kind can terminate here as a pure replay.
        if envelope.entityType == .aiChangelog { return nil }
        return .skipped(
          reason: "exact semantic replay at version \(envelope.version) for "
            + "\(envelope.entityType.asString):\(envelope.entityId)",
          winnerVersion: envelope.version)
      }
      // A base calendar event is the product of two independently-versioned
      // registers. A different payload at the same row HLC must reach its
      // grouped join instead of the whole-row equal-HLC repair path, which could
      // select one snapshot and roll back the other register.
      if try ApplyCalendarEvent.isBaseMergePair(db, envelope: envelope) {
        return nil
      }
      if try ApplyTask.isGroupedMergePair(db, envelope: envelope) {
        return nil
      }
      let contender = try SyncMutationSemantics.deterministicWinner(local, envelope)
      if contender.operation == .upsert,
        try SyncMutationSemantics.isExactSemanticReplay(contender, envelope),
        let (dependencyType, dependencyId) = try ApplyFk.checkFkDependencies(
          db, entityType: contender.entityType.asString, entityId: contender.entityId,
          payload: contender.payload)
      {
        return .deferred(
          reason: .missingDependency(entityType: dependencyType, entityId: dependencyId))
      }
      return .repairRequired(
        .resolveEqualVersionCollision(contender: contender, additionalFloor: nil))
    } catch let error as ApplyError {
      throw error
    } catch {
      throw ApplyError.invalidPayload(
        "equal-version semantic comparison failed for "
          + "\(envelope.entityType.asString):\(envelope.entityId): \(error)")
    }
  }

  private static func localMutationAtSameVersion(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> SyncEnvelope? {
    if let tombstone = try Tombstone.getTombstone(
      db, entityType: envelope.entityType.asString, entityId: envelope.entityId),
      tombstone.version == envelope.version.description
    {
      return SyncEnvelope(
        entityType: envelope.entityType, entityId: envelope.entityId,
        operation: .delete, version: envelope.version,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{}", deviceId: "local-equal-hlc")
    }

    // The append-only audit table deliberately has no version column. Its
    // stable id is the mutation identity, so any different content under an
    // existing id is a collision even when a generation snapshot re-authored
    // the same immutable row under a different transport HLC. Project the
    // canonical stored row and compare both contenders at the inbound HLC; the
    // repair funnel will mint the one durable successor ordering key.
    if envelope.entityType == .aiChangelog, envelope.operation == .upsert,
      var object = try AuditRetentionFrontier.canonicalAuditPayloadObject(
        db, entityId: envelope.entityId)
    {
      object["version"] = .string(envelope.version.description)
      let canonical: String
      do {
        canonical = try SyncCanonicalize.canonicalizeJSON(.object(object))
      } catch {
        throw ApplyError.invalidPayload(
          "local audit collision payload canonicalization failed: \(error)")
      }
      return SyncEnvelope(
        entityType: envelope.entityType, entityId: envelope.entityId,
        operation: .upsert, version: envelope.version,
        payloadSchemaVersion: envelope.payloadSchemaVersion,
        payload: canonical, deviceId: "local-equal-hlc")
    }

    guard
      let rawLocalVersion = try ApplyLww.getLocalVersion(
        db, entityType: envelope.entityType.asString, entityId: envelope.entityId),
      rawLocalVersion == envelope.version.description
    else { return nil }

    let payload: JSONValue
    do {
      payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: envelope.entityType.asString, entityId: envelope.entityId)
    } catch EnqueueError.entityNotFound {
      return nil
    } catch {
      throw ApplyError.lift(error)
    }
    let merged: (payload: JSONValue, mergedShadow: PayloadShadow.Row?)
    do {
      merged = try PayloadShadow.mergePayloadWithShadowReporting(
        db, entityType: envelope.entityType.asString, entityID: envelope.entityId,
        knownPayload: payload)
    } catch {
      throw ApplyError.lift(error)
    }
    let canonical: String
    do {
      canonical = try SyncCanonicalize.canonicalizeJSON(merged.payload)
    } catch {
      throw ApplyError.invalidPayload(
        "local equal-version payload canonicalization failed: \(error)")
    }
    let schemaVersion: UInt32
    if let mergedShadow = merged.mergedShadow {
      do {
        schemaVersion = max(
          LorvexVersion.payloadSchemaVersion,
          try PayloadShadow.requireWirePayloadSchemaVersion(
            mergedShadow, context: "equal-version collision payload shadow"))
      } catch { throw ApplyError.lift(error) }
    } else {
      schemaVersion = LorvexVersion.payloadSchemaVersion
    }
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: .upsert, version: envelope.version,
      payloadSchemaVersion: schemaVersion, payload: canonical,
      deviceId: "local-equal-hlc")
  }

  /// Local LWW and FK gates for non-redirect inbound envelopes. Runs LWW BEFORE
  /// FK preflight so a stale envelope is rejected before deferring on a missing
  /// dependency. Returns a terminal ``ApplyResult`` for the skip / defer paths,
  /// or `nil` when the envelope wins LWW and has all dependencies present.
  static func gateLwwAndFk(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> ApplyResult? {
    // A corrupted LOCAL version string must not poison apply for a well-formed
    // envelope: if parsing fails, treat the local row as absent and let the
    // envelope land on top (the next outbox push rewrites the bad value).
    var parsedLocal: Hlc? = nil
    if let localStr = try ApplyLww.getLocalVersion(
      db, entityType: envelope.entityType.asString, entityId: envelope.entityId)
    {
      parsedLocal = try? Hlc.parseCanonical(localStr)
    }

    if let localVersion = parsedLocal {
      let localVersionStr = localVersion.description
      if Merge.resolveLww(local: localVersion, remote: envelope.version) == .localWins {
        // Calendar base content and topology each have their own HLC. A stale
        // whole-row envelope may still carry either winning register and must
        // reach the custom applier. At an equal row HLC both groups also need
        // the deterministic byte join. Every other stale mutation keeps the
        // ordinary whole-row gate.
        let equalBasePair = try localVersion == envelope.version
          && ApplyCalendarEvent.isBaseMergePair(db, envelope: envelope)
        let staleRegisterWins = try ApplyCalendarEvent.staleBaseRegisterWins(
          db, envelope: envelope)
        let equalTaskPair = try localVersion == envelope.version
          && ApplyTask.isGroupedMergePair(db, envelope: envelope)
        let staleTaskRegisterWins = try ApplyTask.staleIncomingRegisterWins(
          db, envelope: envelope)
        let cutoverJoin = envelope.entityType == .calendarSeriesCutover
        if !equalBasePair && !staleRegisterWins && !equalTaskPair
          && !staleTaskRegisterWins && !cutoverJoin
        {
          let reason =
            "local version \(localVersionStr) >= remote version \(envelope.version) for "
            + "\(envelope.operation.asString) \(envelope.entityType.asString):\(envelope.entityId)"
          // A skipped stale upsert still lowers the merge-family creation floor
          // (min-register; see ApplyLww.foldSkippedUpsertCreatedAtFloor).
          try ApplyLww.foldSkippedUpsertCreatedAtFloor(db, envelope: envelope)
          return try ApplyConflict.recordLwwConflictAndSkip(
            db, entityType: envelope.entityType.asString, entityId: envelope.entityId,
            localVersion: localVersion, envelope: envelope, skipReason: reason, applyTs: applyTs)
        }
      }
      // remoteWins — fall through to apply.
    }

    // FK dependency preflight for upserts (after LWW so a stale envelope is
    // rejected before deferring on a missing dependency).
    if envelope.operation == .upsert {
      if let (depType, depId) = try ApplyFk.checkFkDependencies(
        db, entityType: envelope.entityType.asString, entityId: envelope.entityId,
        payload: envelope.payload)
      {
        return .deferred(reason: .missingDependency(entityType: depType, entityId: depId))
      }
    }
    return nil
  }
}

// MARK: - Delete flow finalization

enum ApplyDeleteFlow {
  /// After the per-entity applier runs, decide the terminal result. A delete
  /// writes a tombstone by default (even on an idempotent no-op) so future
  /// stale upserts are rejected; four outcomes suppress the tombstone:
  /// `lwwRejected` (record an LWW conflict + skip), `deleteSkippedByInvariant`
  /// (defer to the pending inbox), `requiredInboxDeleteRejected` (surface a
  /// repair obligation), and `deleteSkippedLocalOnly` (skip permanently).
  static func finalizeEntityOutcome(
    _ db: Database, envelope: SyncEnvelope, outcome: EntityApplyOutcome,
    applyTs: String
  ) throws -> ApplyResult {
    if envelope.operation == .upsert, outcome == .upsertRejectedByRetention {
      return .upsertRejectedByRetention
    }
    if case .repairRequired(let obligation) = outcome {
      return .repairRequired(obligation)
    }
    if envelope.operation == .delete {
      switch outcome {
      case .lwwRejected(let localVersionStr):
        let reason =
          "delete refused by in-handler LWW gate: local version \(localVersionStr) "
          + "strictly greater than envelope version \(envelope.version) for "
          + "\(envelope.entityType.asString):\(envelope.entityId)"
        // Parse the local version once; fall back to the envelope's own version
        // if the local string is corrupt so the conflict log still attributes
        // the skip correctly.
        let localVersion = (try? Hlc.parseCanonical(localVersionStr)) ?? envelope.version
        return try ApplyConflict.recordLwwConflictAndSkip(
          db, entityType: envelope.entityType.asString, entityId: envelope.entityId,
          localVersion: localVersion, envelope: envelope, skipReason: reason, applyTs: applyTs)
      case .deleteSkippedByInvariant(let invariant):
        return .deferred(
          reason: .aggregateInvariantBlocked(
            entityType: envelope.entityType, entityId: envelope.entityId, invariant: invariant))
      case .requiredInboxDeleteRejected:
        return .repairRequired(
          .reassertRequiredInbox(remoteDeleteVersion: envelope.version))
      case .requiredCutoverDeleteRejected:
        return .repairRequired(
          .reassertCalendarSeriesCutover(
            entityId: envelope.entityId, remoteDeleteVersion: envelope.version))
      case .deleteSkippedLocalOnly:
        return .skipped(
          reason: "delete for local-only entity \(envelope.entityType.asString):"
            + "\(envelope.entityId) filtered at the apply boundary — no tombstone minted",
          winnerVersion: nil)
      case .applied:
        do {
          try Tombstone.createTombstone(
            db, entityType: envelope.entityType.asString, entityId: envelope.entityId,
            version: envelope.version.description, deletedAt: applyTs)
        } catch { throw ApplyError.lift(error) }
      case .upsertRejectedByRetention:
        throw ApplyError.invalidOperation(
          entityType: envelope.entityType.asString, operation: envelope.operation.asString)
      case .repairRequired(let obligation):
        return .repairRequired(obligation)
      }
    }
    return .applied
  }
}

// MARK: - Redirect flow orchestrator

enum ApplyRedirectFlow {
  /// Orchestrate the redirected-tombstone apply path: chase the redirect chain,
  /// build a remapped envelope addressed at the chain terminus, then run three
  /// safety gates before dispatching.
  ///
  /// The gates run in a fixed order:
  ///
  /// 1. **Delete drop** (``dropRedirectedDelete(_:envelope:remapped:hops:ts:applyTs:)``)
  ///    — a Delete that landed on the redirect path was authored against the
  ///    merge LOSER's identity by a peer that had not observed the merge.
  ///    Propagating it to the winner would be unauthorized data destruction, so
  ///    the delete is dropped (with a conflict-log row) instead of applied. This
  ///    gate is hoisted BEFORE the per-hop payload identity rewrite + canonical
  ///    re-serialization because Delete envelopes are identity-only.
  /// 2. **Target-tombstone + LWW + FK gate**
  ///    (``gateRedirectedUpsert(_:envelope:remapped:acceptance:applyTs:)``) — for
  ///    an Upsert, the redirect target may itself carry a REAL delete tombstone
  ///    (resurrection guard), or a newer local version (LWW guard), or a missing
  ///    parent FK (defer). These run in tombstone → LWW → FK order, matching the
  ///    non-redirect branch.
  ///
  /// Only when both gates admit the envelope is it dispatched and its payload
  /// shadow prepared, yielding ``ApplyResult/remapped(fromEntityId:toEntityId:)``.
  static func applyRedirectedEnvelope(
    _ db: Database, registry: EntityApplierRegistry, envelope: SyncEnvelope,
    redirect: EntityRedirect.Record, acceptance: EnvelopeAcceptance, applyTs: String
  ) throws -> ApplyResult {
    let chase = try ApplyRedirect.chaseRedirectChain(
      db, initialEntityType: envelope.entityType.asString, initialEntityId: envelope.entityId)

    guard let finalKind = EntityKind.parse(chase.finalType) else {
      throw ApplyError.unknownEntityType(chase.finalType)
    }

    // Gate 1 (delete drop) is hoisted BEFORE the per-hop payload identity rewrite
    // + canonical re-serialization. Delete envelopes are identity-only, so a
    // remapped envelope carrying the original (un-rewritten) payload is all the
    // drop gate needs.
    let remappedForDrop = SyncEnvelope(
      entityType: finalKind, entityId: chase.finalId, operation: envelope.operation,
      version: envelope.version, payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: envelope.payload, deviceId: envelope.deviceId)
    if let result = try dropRedirectedDelete(
      db, envelope: envelope, remapped: remappedForDrop, hops: chase.hops,
      redirect: redirect, applyTs: applyTs)
    {
      return result
    }

    // Rewrite payload-FK identity fields + canonically re-serialize for the
    // upsert path.
    var remappedPayload: JSONValue
    if let parsed = JSONValue.parse(envelope.payload) {
      remappedPayload = parsed
    } else {
      throw ApplyError.invalidPayload("malformed sync payload JSON")
    }
    _ = ApplyRedirect.remapPayloadIdentityFields(
      entityType: chase.finalType, payload: &remappedPayload,
      originalId: envelope.entityId, targetId: chase.finalId)
    // The remapped payload keeps the alias source's `created_at` deliberately:
    // the aggregate tables treat `created_at` as a min-register, and the
    // apply-side fold (ApplyLww.foldCreatedAtFloor) lowers the target row's
    // floor from this payload whether it wins, loses, or creates the row.
    let remappedPayloadStr: String
    do {
      remappedPayloadStr = try SyncCanonicalize.canonicalizeJSON(remappedPayload)
    } catch { throw ApplyError.lift(error) }
    if remappedPayloadStr.utf8.count > PayloadShadow.maxRawPayloadJSONBytes {
      throw ApplyError.redirectPayloadTooLarge(
        entityType: envelope.entityType, entityId: chase.finalId,
        sizeBytes: remappedPayloadStr.utf8.count)
    }
    let remapped = SyncEnvelope(
      entityType: finalKind, entityId: chase.finalId, operation: envelope.operation,
      version: envelope.version, payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: remappedPayloadStr, deviceId: envelope.deviceId)

    // Gate 2: target-tombstone resurrection guard, target LWW, then FK preflight.
    if let result = try gateRedirectedUpsert(
      db, envelope: envelope, remapped: remapped, applyTs: applyTs)
    {
      return result
    }

    // Stash/reap before dispatch so an aggregate collision inside the applier
    // can move the admitted future fields with the content-winning identity.
    try ApplyPayloadShadow.prepareForUpsertDispatch(
      db, acceptance: acceptance, envelope: remapped)

    // Apply the remapped envelope (tombstone + LWW checks already done above).
    _ = try ApplyDispatch.dispatch(
      db, registry: registry, envelope: remapped, tieBreak: .rejectEqual, applyTs: applyTs)
    return .remapped(fromEntityId: envelope.entityId, toEntityId: remapped.entityId)
  }

  /// Gate 1 — drop a Delete envelope authored against a merge loser.
  ///
  /// A Delete that reached the redirect path came from a peer that had not yet
  /// observed the merge; routing it to the winner would destroy a different
  /// identity that may carry concurrent edits or children. Record a conflict-log
  /// row attributed to the original peer (`envelope.deviceId`, not the
  /// locally-attributed `remapped.deviceId`) and skip. Returns the terminal
  /// ``ApplyResult`` for the drop, or `nil` for non-Delete operations.
  private static func dropRedirectedDelete(
    _ db: Database, envelope: SyncEnvelope, remapped: SyncEnvelope,
    hops: [ApplyRedirect.RedirectHop], redirect: EntityRedirect.Record, applyTs: String
  ) throws -> ApplyResult? {
    guard envelope.operation == .delete else { return nil }

    // The permanent alias that claimed the loser identity is the first hop; its
    // version dominates anything authored against the pre-merge id. The hops are
    // non-empty here because the caller only reaches this path with a redirect
    // present, but keep the supplied redirect version as a fallback for safety.
    let aliasVersion = hops.first?.version ?? redirect.version

    do {
      try ConflictLog.logConflict(
        db,
        ConflictLog.Entry(
          entityType: envelope.entityType.asString, entityId: envelope.entityId,
          winnerVersion: aliasVersion, loserVersion: envelope.version.description,
          loserDeviceId: envelope.deviceId, loserPayload: nil, resolvedAt: applyTs,
          resolutionType: ResolutionName.redirectedDeleteDropped))
    } catch { throw ApplyError.lift(error) }

    // Dropping the delete is the correct outcome regardless; a corrupt merge HLC
    // only degrades the skip's arbitration provenance to `nil`. Log the
    // corruption so diagnostics surface the drift.
    let winnerVersion: Hlc?
    if let parsed = try? Hlc.parseCanonical(aliasVersion) {
      winnerVersion = parsed
    } else {
      ErrorLog.appendBestEffort(
        db, source: "sync.apply.redirect_corrupt_winner_hlc",
        message: "entity redirect HLC '\(aliasVersion)' for redirect-loser "
          + "\(envelope.entityType.asString):\(envelope.entityId) -> \(remapped.entityId) "
          + "is not a valid HLC",
        details: nil, level: "error")
      winnerVersion = nil
    }

    return .skipped(
      reason: "delete envelope for merge-loser \(envelope.entityType.asString):"
        + "\(envelope.entityId) dropped (target now \(remapped.entityId))",
      winnerVersion: winnerVersion)
  }

  /// Gate 2 — target-tombstone resurrection guard, target LWW guard, then FK
  /// preflight for the redirected upsert branch (in that order).
  ///
  /// Returns the terminal ``ApplyResult`` when any sub-gate rejects/defers, or
  /// `nil` for non-Upsert operations and when every sub-gate admits the envelope.
  private static func gateRedirectedUpsert(
    _ db: Database, envelope: SyncEnvelope, remapped: SyncEnvelope, applyTs: String
  ) throws -> ApplyResult? {
    guard remapped.operation == .upsert else { return nil }
    if let result = try checkTargetTombstone(
      db, envelope: envelope, remapped: remapped, applyTs: applyTs)
    {
      return result
    }
    if let result = try checkTargetLww(
      db, envelope: envelope, remapped: remapped, applyTs: applyTs)
    {
      return result
    }
    return try checkTargetFk(db, remapped: remapped)
  }

  /// Resurrection guard: the redirect TARGET may itself carry a delete
  /// tombstone (the entry-point tombstone check only ran against the ORIGINAL
  /// entity_id). Without this, the upsert lands on a tombstoned target and
  /// resurrects the row.
  private static func checkTargetTombstone(
    _ db: Database, envelope: SyncEnvelope, remapped: SyncEnvelope, applyTs: String
  ) throws -> ApplyResult? {
    let targetTs: Tombstone.Record?
    do {
      targetTs = try Tombstone.getTombstone(
        db, entityType: remapped.entityType.asString, entityId: remapped.entityId)
    } catch { throw ApplyError.lift(error) }
    guard let targetTs else { return nil }
    let targetTsVersion: Hlc
    do {
      targetTsVersion = try Hlc.parseCanonical(targetTs.version)
    } catch { throw ApplyError.invalidVersion("\(error)") }
    let envelopeVersion = remapped.version

    if envelopeVersion <= targetTsVersion {
      // Stale upsert lost to a real delete tombstone — surface in conflict_log,
      // reap any shadow the tombstone supersedes, and skip.
      do {
        try ConflictLog.logConflict(
          db,
          ConflictLog.Entry(
            entityType: remapped.entityType.asString, entityId: remapped.entityId,
            winnerVersion: targetTs.version, loserVersion: remapped.version.description,
            loserDeviceId: remapped.deviceId, loserPayload: remapped.payload, resolvedAt: applyTs,
            resolutionType: ResolutionName.tombstoneWins))
      } catch { throw ApplyError.lift(error) }
      try ApplyConflict.reapShadowForSkipped(
        db, entityType: remapped.entityType.asString, entityId: remapped.entityId,
        supersedingVersion: targetTs.version)
      return .skipped(
        reason: "redirect target \(remapped.entityType.asString):\(remapped.entityId) is "
          + "tombstoned with version \(targetTs.version) >= remapped envelope version "
          + "\(remapped.version)",
        winnerVersion: targetTsVersion)
    }

    // Envelope strictly newer than the delete tombstone —
    // concurrent-update-wins-over-concurrent-delete. Log the resolution before
    // removing the tombstone and falling through to apply.
    do {
      try ConflictLog.logConflict(
        db,
        ConflictLog.Entry(
          entityType: remapped.entityType.asString, entityId: remapped.entityId,
          winnerVersion: remapped.version.description, loserVersion: targetTs.version,
          loserDeviceId: envelope.deviceId, loserPayload: nil, resolvedAt: applyTs,
          resolutionType: ResolutionName.upsertWinsOverDelete))
      _ = try Tombstone.removeTombstone(
        db, entityType: remapped.entityType.asString, entityId: remapped.entityId)
    } catch { throw ApplyError.lift(error) }
    return nil
  }

  /// LWW guard against stale envelopes — the redirect target may already carry a
  /// newer local version from a later edit by the merge winner. A corrupt local
  /// version is treated as "no local version" (logged to error_log) so the
  /// envelope falls through to apply, mirroring the non-redirect branch.
  private static func checkTargetLww(
    _ db: Database, envelope: SyncEnvelope, remapped: SyncEnvelope, applyTs: String
  ) throws -> ApplyResult? {
    let localVersionStr: String?
    do {
      localVersionStr = try ApplyLww.getLocalVersion(
        db, entityType: remapped.entityType.asString, entityId: remapped.entityId)
    } catch { throw ApplyError.lift(error) }
    guard let localVersionStr else { return nil }

    let localVersion: Hlc
    if let parsed = try? Hlc.parseCanonical(localVersionStr) {
      localVersion = parsed
    } else {
      ErrorLog.appendBestEffort(
        db, source: "sync.apply.local_version_corruption",
        message: "local version '\(localVersionStr)' on \(remapped.entityType.asString):"
          + "\(remapped.entityId) (redirect target) is not a valid HLC",
        details: nil, level: "error")
      // Treat a corrupt local stamp as absent. The caller owns the single
      // prepare-and-dispatch path after this gate.
      return nil
    }

    guard Merge.resolveLww(local: localVersion, remote: remapped.version) == .localWins else {
      return nil
    }
    let reason =
      "redirect target \(remapped.entityType.asString):\(remapped.entityId) has newer local "
      + "version \(localVersionStr) than remapped envelope version \(remapped.version)"
    // A skipped stale remapped upsert still lowers the merge-family creation
    // floor (min-register): this payload may be the only witness of the alias
    // source's creation time that this peer ever receives.
    try ApplyLww.foldSkippedUpsertCreatedAtFloor(db, envelope: remapped)
    return try ApplyConflict.recordLwwConflictAndSkip(
      db, entityType: remapped.entityType.asString, entityId: remapped.entityId,
      localVersion: localVersion, envelope: remapped, skipReason: reason, applyTs: applyTs)
  }

  /// FK preflight for the remapped envelope — runs LAST so a stale-or-tombstoned
  /// envelope is rejected before it can park in the pending inbox waiting on a
  /// transient parent. Returns a ``ApplyResult/deferred(reason:)`` for a missing
  /// dependency, else `nil`.
  private static func checkTargetFk(
    _ db: Database, remapped: SyncEnvelope
  ) throws -> ApplyResult? {
    if let (depType, depId) = try ApplyFk.checkFkDependencies(
      db, entityType: remapped.entityType.asString, entityId: remapped.entityId,
      payload: remapped.payload)
    {
      return .deferred(reason: .missingDependency(entityType: depType, entityId: depId))
    }
    return nil
  }
}
