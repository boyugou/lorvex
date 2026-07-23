import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Drain + enqueue half of the pending inbox — re-applies deferred envelopes
/// through ``Apply/applyEnvelope(_:registry:envelope:)`` once their FK parent
/// arrives, quarantines envelopes that fail repeatedly, and remaps composite-edge
/// / payload identities through late-arriving permanent entity aliases.
///
/// The store-layer CRUD half lives in `LorvexStore.PendingInbox`; this file adds
/// the parts that need `SyncEnvelope` + the apply pipeline.
public enum PendingInboxDrain {
  /// Soft cap on entries visited per drain pass. A massive backlog (a device
  /// back online after a long outage) is bounded so the SQLite writer is
  /// released within bounded latency and never starves concurrent writes; the
  /// next sync tick re-drives the drain.
  static let maxDrainEntriesPerPass = 500

  /// Minimum wall-clock gap between `attempt_count` bumps for a still-deferred
  /// entry (a SQLite datetime modifier). The drain fires once per inbound chunk,
  /// so a single large pull runs it dozens of times in seconds; gating the bump
  /// on elapsed time keeps a legitimately-waiting entry from burning its whole
  /// 50-attempt budget mid-sync (an FK parent can arrive thousands of records —
  /// many chunks — later in the same pull). The horizon GC is the ultimate
  /// backstop, so a generous interval is safe.
  static let attemptBumpMinInterval = "-300 seconds"

  /// Distinct entity kinds successfully applied during a drain pass, plus
  /// per-disposition counters.
  public struct DrainSummary: Sendable, Equatable {
    public var replayed: UInt64 = 0
    public var discarded: UInt64 = 0
    public var remapped: UInt64 = 0
    public var stalledLogged: UInt64 = 0
    /// Entries that failed with a non-deferral error and were left for a future
    /// drain — they do not abort the pass.
    public var errors: UInt64 = 0
    /// Entries the apply pipeline returned ``ApplyResult/skipped(reason:winnerVersion:)`` for.
    public var skipped: UInt64 = 0
    /// Held audit upserts rejected by the authoritative retention frontier.
    /// Consuming one removes canonical full content and persists physical-delete
    /// work, so the driver must invalidate readers even though no row was replayed.
    public var retentionRejected: UInt64 = 0
    /// Distinct entity kinds replayed during this pass (dedup at insertion time).
    public var replayedEntityTypes: [EntityKind] = []
    /// Task ids a replayed non-inbox list-delete re-homed to inbox (via the
    /// `trg_lists_before_delete` trigger, which bumps no version and enqueues no
    /// outbox row). The driver mints a fresh HLC + outbox upsert for each so the
    /// move converges across peers (SA1) — the same propagation the direct
    /// applyInbound loop performs. Captured BEFORE each apply (while the tasks
    /// still carry the doomed list_id) and surfaced only for applies that landed.
    public var listDeleteRehomedTaskIds: [String] = []
    /// Entities a replayed upsert diverged for through rolling-schema or
    /// absence-preserving semantics. The driver mints a fresh HLC + outbox upsert
    /// of each merged snapshot so peers that only saw the inbound envelope
    /// converge — the same re-emit the direct applyInbound loop performs inline.
    public var absenceReemitTargets: [AbsenceReemitTarget] = []
    /// Typed convergence writes surfaced while replaying a deferred envelope.
    /// The host must fulfill every obligation in the same outer transaction;
    /// otherwise removing the pending row would acknowledge a remote mutation
    /// while leaving the shared record permanently inconsistent.
    public var repairObligations: [ApplyRepairObligation] = []
    /// Post-authoritative user intents that could not be re-authored while the
    /// occupying record was opaque. The host fulfills them with its transaction
    /// HLC after the now-understood remote envelope is consumed.
    public var futureLocalIntentReplays: [FutureRecordHold.LocalIntentReplay] = []

    public init() {}
  }

  // MARK: - drain

  /// Re-attempt all entries in the pending inbox using typed dependency rules.
  ///
  /// Processing rules:
  /// - successful apply / skip => remove entry
  /// - missing dependency ordinarily tombstoned => discard + conflict log
  /// - missing dependency tombstoned with redirect => rewrite envelope and retry
  /// - still deferred/error => keep entry, update attempt metadata
  /// - entries stalled for >1 hour => log `fk_stalled` once for visibility
  ///
  /// MUST run inside an outer transaction (the apply pipeline asserts it). GRDB's
  /// `write` block always provides one.
  @discardableResult
  public static func drainPendingInbox(
    _ db: Database, registry: EntityApplierRegistry
  ) throws -> DrainSummary {
    var summary = DrainSummary()
    let entryIDs = try PendingInbox.pendingEntryIDsForDrain(db, limit: maxDrainEntriesPerPass)
    var coalescedTargetIDs = Set<Int64>()

    for entryID in entryIDs {
      if coalescedTargetIDs.remove(entryID) != nil {
        continue
      }
      guard let entry = try PendingInbox.pendingEntry(db, id: entryID) else {
        continue
      }

      var envelope: SyncEnvelope
      do {
        envelope = try parseEnvelope(entry)
      } catch {
        // A HELD future record (parked by the future-record lane) is NOT poison:
        // it fails to parse only because this build lacks the EntityKind case or
        // the future operation yet. Refresh its timestamp WITHOUT bumping
        // attempt_count and leave it parked — quarantining it would permanently
        // lose correct data the device will understand after it upgrades. It sheds
        // only via horizon GC.
        if Self.isHeldFutureRecord(entry) {
          do {
            try PendingInbox.recordAttemptTimestamp(db, id: entry.id)
          } catch {
            ErrorLog.appendBestEffort(
              db, source: "sync.pending_inbox",
              message:
                "pending_inbox entry \(entry.id) unknown-type hold timestamp refresh failed: \(error)",
              details: nil, level: "error")
          }
          continue
        }
        // Poison-pill: an envelope that fails to deserialize must not abort the
        // drain. Log to error_logs, bump attempt_count to the cap (so a future
        // enqueue / drain promotes it to EXHAUSTED), and continue.
        ErrorLog.appendBestEffort(
          db, source: "sync.pending_inbox.unparseable_envelope",
          message:
            "pending_inbox entry \(entry.id) carries an envelope that cannot be "
            + "deserialized; quarantining as poison: \(error)",
          details: nil, level: "error")
        if entry.attemptCount >= PendingInbox.maxAttempts {
          do {
            try quarantineUnparseableEntry(db, id: entry.id)
            summary.discarded += 1
          } catch {
            ErrorLog.appendBestEffort(
              db, source: "sync.pending_inbox",
              message:
                "pending_inbox entry \(entry.id) unparseable-quarantine failed: \(error)",
              details: nil, level: "error")
          }
        } else {
          do {
            try PendingInbox.bumpAttemptCountToCap(
              db, id: entry.id, target: PendingInbox.maxAttempts)
          } catch {
            ErrorLog.appendBestEffort(
              db, source: "sync.pending_inbox",
              message:
                "pending_inbox entry \(entry.id) attempt-cap bump failed: \(error)",
              details: nil, level: "error")
          }
        }
        summary.errors += 1
        continue
      }

      // Durable redirect handling first — a late alias can rescue an
      // exhausted entry via remapping before the cap check discards it.
      if let missingType = entry.missingEntityType, let missingID = entry.missingEntityID {
        if let redirect = try EntityRedirect.get(
          db, sourceType: missingType, sourceId: missingID)
        {
          if let remapped = try remapMissingDependency(
            envelope: envelope, missingEntityType: missingType, missingEntityID: missingID,
            aliasSourceType: missingType, aliasTargetID: redirect.targetId)
          {
            envelope = remapped
            summary.remapped += 1
          } else {
            try logFkUnresolvedDiscard(db, envelope: envelope, winnerVersion: redirect.version)
            try PendingInbox.removePending(db, id: entry.id)
            summary.discarded += 1
            continue
          }
        }
        if try Tombstone.getTombstone(
          db, entityType: missingType, entityId: missingID) != nil
        {
          // An ordinary tombstone on the missing dependency is NOT a blind
          // discard: the apply pipeline is the authority on whether it satisfies
          // the FK. A `.task` whose `list_id` points at an ordinarily deleted list
          // tombstone re-homes to inbox (``ApplyFk/checkFkDependencies`` /
          // ``ApplyTask/resolveListId`` treat it as satisfied), so discarding here
          // would silently lose the task on whichever peer parked it first — an
          // arrival-order divergence. Fall through to the apply; a dependency that
          // genuinely cannot resolve (an edge whose parent is permanently gone)
          // re-defers and is discarded in the `.deferred` arm below.
        }
      }

      // A replayed non-inbox list-delete re-homes its tasks to inbox via the
      // `trg_lists_before_delete` trigger with no version bump or outbox row.
      // Capture those task ids BEFORE the apply overwrites their list_id so the
      // driver can re-propagate the move (SA1). Empty for every other envelope
      // shape, so this is a cheap guard on the common path.
      let rehomeCandidates = try ListDeleteRehome.captureRehomeCandidates(db, envelope: envelope)

      let result: ApplyResult
      do {
        result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
      } catch let applyError as ApplyError {
        try handleApplyError(
          db, entry: entry, envelope: envelope, error: applyError, summary: &summary)
        continue
      }

      switch result {
      case .applied, .remapped:
        try clearQuarantineThroughResolvedEnvelope(
          db, entityType: envelope.entityType.asString,
          entityID: envelope.entityId, version: envelope.version.description)
        try PendingInbox.removePending(db, id: entry.id)
        if let replay = try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: envelope, outcome: result)
        {
          summary.futureLocalIntentReplays.append(replay)
        }
        summary.replayed += 1
        for kind in try SyncMutationImpact.affectedEntityTypes(for: envelope)
          .sorted(by: { $0.asString < $1.asString })
          where !summary.replayedEntityTypes.contains(kind)
        {
          summary.replayedEntityTypes.append(kind)
        }
        summary.listDeleteRehomedTaskIds.append(contentsOf: rehomeCandidates)
        // An `.applied` upsert (envelope.entityId is the landed row) whose merged
        // row diverged from the envelope (absence-preserved children or a list_id
        // fallback rehome) needs a merged-snapshot re-emit. Detection is
        // fail-closed: this pending row was just removed, so swallowing a probe
        // failure would lose the only durable convergence obligation. Throwing
        // rolls the outer transaction back, including the removal.
        if case .applied = result {
          if let target = try AbsencePreserveReemit.convergenceReemitTarget(
            db, envelope: envelope)
          {
            summary.absenceReemitTargets.append(target)
          }
        }
        // A `.remapped` habit upsert changed the merge WINNER (`toEntityId`) via a
        // redirect the loser-only peer never learned — re-emit the winner's snapshot
        // so it converges (the archive-interleaving non-confluence). Non-habit /
        // non-upsert remaps return nil.
        if case .remapped(_, let toEntityId) = result,
          let target = try AbsencePreserveReemit.remappedMergeWinnerReemitTarget(
            db, envelope: envelope, toEntityId: toEntityId)
        {
          summary.absenceReemitTargets.append(target)
        }
      case .upsertRejectedByRetention:
        try clearQuarantineThroughResolvedEnvelope(
          db, entityType: envelope.entityType.asString,
          entityID: envelope.entityId, version: envelope.version.description)
        try PendingInbox.removePending(db, id: entry.id)
        if let replay = try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: envelope, outcome: result)
        {
          summary.futureLocalIntentReplays.append(replay)
        }
        // The applier already persisted account-scoped physical-delete work in
        // this transaction; consuming the pending full-content copy is now safe.
        summary.skipped += 1
        summary.retentionRejected += 1
      case .repairRequired(let obligation):
        try clearQuarantineThroughResolvedEnvelope(
          db, entityType: envelope.entityType.asString,
          entityID: envelope.entityId, version: envelope.version.description)
        try PendingInbox.removePending(db, id: entry.id)
        if let replay = try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: envelope, outcome: result)
        {
          summary.futureLocalIntentReplays.append(replay)
        }
        summary.skipped += 1
        summary.repairObligations.append(obligation)
      case .skipped:
        try clearQuarantineThroughResolvedEnvelope(
          db, entityType: envelope.entityType.asString,
          entityID: envelope.entityId, version: envelope.version.description)
        // Apply owns shadow cleanup for the terminal tombstone/LWW-loss paths,
        // using the actual winning version. Do not reap here: `.skipped` also
        // includes an exact semantic replay, and an equal-version shadow can be
        // the only preserved copy of fields this runtime does not understand.
        try PendingInbox.removePending(db, id: entry.id)
        if let replay = try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: envelope, outcome: result)
        {
          summary.futureLocalIntentReplays.append(replay)
        }
        summary.skipped += 1
      case .deferred(let reason):
        let (missingType, missingID) = missingFromReason(reason)
        // A deferral whose missing dependency is ordinarily tombstoned can
        // never resolve — the parent is permanently gone. Discard (conflict-
        // logged) rather than re-parking it to burn the retry budget toward
        // quarantine. A `.task` pointing at an ordinary list tombstone never
        // reaches here: the apply re-homes it to inbox instead of deferring.
        if let missingType, let missingID,
          let tombstone = try Tombstone.getTombstone(
            db, entityType: missingType, entityId: missingID)
        {
          try logFkUnresolvedDiscard(db, envelope: envelope, winnerVersion: tombstone.version)
          try PendingInbox.removePending(db, id: entry.id)
          summary.discarded += 1
          continue
        }
        let preservesFutureRecord = Self.isFutureRecordHoldReason(entry.reason)
        let activePendingID = try PendingInbox.updatePendingEntry(
          db, id: entry.id, envelopeJSON: serializeEnvelope(envelope),
          reason: preservesFutureRecord ? entry.reason : reason.message,
          missingEntityType: missingType, missingEntityID: missingID,
          envelopeEntityType: envelope.entityType.asString, envelopeEntityID: envelope.entityId,
          envelopeVersion: envelope.version.description)
        if activePendingID != entry.id {
          coalescedTargetIDs.insert(activePendingID)
        }
        if preservesFutureRecord || isBudgetExemptHold(reason) {
          try PendingInbox.recordAttemptTimestamp(db, id: activePendingID)
          continue
        }

        // Time-gate the attempt bump so a multi-chunk pull cannot burn the retry
        // budget of an entry whose FK parent is still arriving (see
        // ``attemptBumpMinInterval``). The apply is re-attempted every chunk
        // regardless; only the budget counter is rate-limited.
        try PendingInbox.recordReattemptTimeGated(
          db, id: activePendingID, minInterval: attemptBumpMinInterval)

        // Cap on the on-disk post-bump value, not a pre-bump snapshot + 1. A
        // missing row means another writer already discarded it — skip the cap.
        let postCount = try PendingInbox.readAttemptCount(db, id: activePendingID) ?? Int64.min
        if postCount >= PendingInbox.maxAttempts {
          try logExhaustedConflict(db, envelope: envelope)
          try recordQuarantine(
            db, entityType: envelope.entityType.asString, entityID: envelope.entityId,
            version: envelope.version.description)
          try PendingInbox.removePending(db, id: activePendingID)
          summary.discarded += 1
        } else if try shouldLogStalled(db, entry: entry, envelope: envelope) {
          try logFkStalled(db, envelope: envelope)
          summary.stalledLogged += 1
        }
      }
    }

    return summary
  }

  /// Apply-pipeline `Err(_)` handling. Transient busy/locked errors re-record
  /// `last_attempted_at` without bumping `attempt_count`; all other errors bump
  /// the attempt + (deduped) log to error_logs, and discard at the cap.
  private static func handleApplyError(
    _ db: Database, entry: PendingInbox.Entry, envelope: SyncEnvelope, error: ApplyError,
    summary: inout DrainSummary
  ) throws {
    if isTransientBusyOrLocked(error) {
      do {
        try PendingInbox.recordReattemptBusy(db, id: entry.id)
      } catch {
        ErrorLog.appendBestEffort(
          db, source: "sync.pending_inbox",
          message:
            "pending_inbox entry \(entry.id) busy-reattempt bookkeeping failed: \(error)",
          details: nil, level: "error")
      }
      summary.errors += 1
      return
    }

    // A permanent apply error on an entry whose declared missing dependency is
    // ordinarily tombstoned: the parent is permanently gone, so the entry
    // can never apply. Discard it (fk_unresolved) rather than bumping it toward
    // quarantine. A `.task` re-homes to inbox on an ordinary list tombstone and
    // never reaches this error path.
    if let missingType = entry.missingEntityType, let missingID = entry.missingEntityID,
      let tombstone = try Tombstone.getTombstone(db, entityType: missingType, entityId: missingID)
    {
      try logFkUnresolvedDiscard(db, envelope: envelope, winnerVersion: tombstone.version)
      try PendingInbox.removePending(db, id: entry.id)
      summary.discarded += 1
      return
    }

    let msg =
      "pending_inbox entry \(entry.id) (entity \(envelope.entityType.asString):\(envelope.entityId) "
      + "version \(envelope.version.description)): \(syncErrorMessageForApplyFailure(entry.id, envelope, error))"
    let priorError: String?
    do {
      priorError = try PendingInbox.recordReattemptWithError(db, id: entry.id, newError: msg)
    } catch {
      ErrorLog.appendBestEffort(
        db, source: "sync.pending_inbox",
        message: "pending_inbox entry \(entry.id) reattempt bookkeeping failed: \(error)",
        details: nil, level: "error")
      ErrorLog.appendBestEffort(
        db, source: "sync.pending_inbox", message: msg, details: nil, level: "error")
      summary.errors += 1
      return
    }
    if priorError != msg {
      ErrorLog.appendBestEffort(
        db, source: "sync.pending_inbox", message: msg, details: nil, level: "error")
    }
    summary.errors += 1

    let postCount = try PendingInbox.readAttemptCount(db, id: entry.id) ?? Int64.min
    if postCount >= PendingInbox.maxAttempts {
      do {
        try logExhaustedConflict(db, envelope: envelope)
      } catch {
        ErrorLog.appendBestEffort(
          db, source: "sync.pending_inbox",
          message:
            "pending_inbox entry \(entry.id) exhausted-conflict logging failed: \(error)",
          details: nil, level: "error")
        return
      }
      do {
        try recordQuarantine(
          db, entityType: envelope.entityType.asString, entityID: envelope.entityId,
          version: envelope.version.description)
      } catch {
        ErrorLog.appendBestEffort(
          db, source: "sync.pending_inbox",
          message: "pending_inbox entry \(entry.id) exhausted-quarantine failed: \(error)",
          details: nil, level: "error")
        return
      }
      do {
        try PendingInbox.removePending(db, id: entry.id)
      } catch {
        ErrorLog.appendBestEffort(
          db, source: "sync.pending_inbox",
          message: "pending_inbox entry \(entry.id) exhausted-remove failed: \(error)",
          details: nil, level: "error")
        return
      }
      summary.discarded += 1
    }
  }

  /// Classify an `ApplyError` as a recoverable SQLite lock-contention error
  /// (`SQLITE_BUSY` / `SQLITE_LOCKED`). All other error classes are permanent
  /// failures.
  static func isTransientBusyOrLocked(_ error: ApplyError) -> Bool {
    if case .dbBusyOrLocked = error { return true }
    return false
  }

  // MARK: - enqueue

  /// Add an unresolved envelope to the pending inbox: short-circuits
  /// known-poison identities, validates the
  /// payload against the canonicalization depth/size caps, UPSERTs on the
  /// `(entity_type, entity_id, version)` identity triple (a duplicate enqueue
  /// bumps `attempt_count` rather than creating a fresh row), and promotes to a
  /// permanent EXHAUSTED conflict + quarantine once the cap is crossed.
  ///
  /// - Parameter countsTowardRetryBudget: whether a duplicate enqueue of the
  ///   same identity bumps `attempt_count`. Callers pass `false` for a
  ///   schema-too-new hold, which parks the envelope waiting on a local schema
  ///   upgrade and must not burn the retry budget. The caller declares this
  ///   explicitly rather than the callee re-deriving it from the `reason` text.
  public static func enqueuePending(
    _ db: Database, envelope: SyncEnvelope, reason: String,
    missingEntityType: String?, missingEntityID: String?,
    countsTowardRetryBudget: Bool = true
  ) throws {
    if try isQuarantined(
      db, entityType: envelope.entityType.asString, entityID: envelope.entityId,
      version: envelope.version.description)
    {
      return
    }

    // Defense-in-depth: validate the payload respects the canonicalization
    // depth/size caps before storing. Reject malformed/over-deep payloads here.
    guard let payloadValue = JSONValue.parse(envelope.payload) else {
      throw EnqueueError.malformedPayload("pending inbox envelope payload is not valid JSON")
    }
    do {
      _ = try SyncCanonicalize.canonicalizeJSON(payloadValue)
    } catch let canonError as SyncCanonicalize.SyncCanonError {
      throw EnqueueError.canonicalization(canonError)
    }

    let envelopeJSON = try serializeEnvelope(envelope)
    let entityType = envelope.entityType.asString
    let version = envelope.version.description
    let duplicateAttemptIncrement: Int64 = countsTowardRetryBudget ? 1 : 0

    try db.execute(
      sql: """
        INSERT INTO sync_pending_inbox
            (envelope, reason, missing_entity_type, missing_entity_id,
             envelope_entity_type, envelope_entity_id, envelope_version,
             first_attempted_at, last_attempted_at, attempt_count)
         VALUES (?, ?, ?, ?, ?, ?, ?,
                 strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                 strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                 1)
         ON CONFLICT(envelope_entity_type, envelope_entity_id, envelope_version)
         DO UPDATE SET
             envelope            = excluded.envelope,
             reason              = excluded.reason,
             missing_entity_type = COALESCE(excluded.missing_entity_type, missing_entity_type),
             missing_entity_id   = COALESCE(excluded.missing_entity_id, missing_entity_id),
             last_attempted_at   = excluded.last_attempted_at,
             attempt_count       = attempt_count + ?
        """,
      arguments: [
        envelopeJSON, reason, missingEntityType, missingEntityID,
        entityType, envelope.entityId, version, duplicateAttemptIncrement,
      ])

    let postCount =
      try Int64.fetchOne(
        db,
        sql: """
          SELECT attempt_count FROM sync_pending_inbox
          WHERE envelope_entity_type = ? AND envelope_entity_id = ? AND envelope_version = ?
          """,
        arguments: [entityType, envelope.entityId, version]) ?? 0

    if Self.isFutureRecordHoldReason(reason) {
      try FutureRecordHold.fenceExistingLocalIntent(
        db, entityType: entityType, entityId: envelope.entityId, heldVersion: version)
    }

    if countsTowardRetryBudget && postCount >= PendingInbox.maxAttempts {
      try logExhaustedConflict(db, envelope: envelope)
      try db.execute(
        sql: """
          DELETE FROM sync_pending_inbox
          WHERE envelope_entity_type = ? AND envelope_entity_id = ? AND envelope_version = ?
          """,
        arguments: [entityType, envelope.entityId, version])
      ErrorLog.appendBestEffort(
        db, source: "sync.pending_inbox.enqueue_exhausted",
        message:
          "pending_inbox enqueue exhausted retry budget (\(PendingInbox.maxAttempts)) for "
          + "\(entityType):\(envelope.entityId) version=\(version); envelope quarantined as poison",
        details: nil, level: "error")
      try recordQuarantine(
        db, entityType: entityType, entityID: envelope.entityId, version: version)
    }
  }

  /// Convenience wrapper: enqueue a deferred envelope using a typed `DeferralReason`.
  public static func enqueueDeferred(
    _ db: Database, envelope: SyncEnvelope, reason: DeferralReason
  ) throws {
    let (missingType, missingID) = missingFromReason(reason)
    try enqueuePending(
      db, envelope: envelope, reason: reason.message,
      missingEntityType: missingType, missingEntityID: missingID,
      countsTowardRetryBudget: !isBudgetExemptHold(reason))
  }

  // MARK: - remap

  /// Rewrite a deferred envelope when its missing dependency has a durable
  /// same-type alias pointing at a surviving merge winner. Returns the remapped
  /// envelope, or `nil` when a non-composite entity's payload carried no
  /// matching identity field.
  ///
  /// The remapped payload string is re-serialized via
  /// `SyncCanonicalize.canonicalizeJSON` (sorted keys); the payload parses to the
  /// same JSON value and the apply pipeline re-canonicalizes it, so identity
  /// columns and apply outcome are unaffected.
  static func remapMissingDependency(
    envelope: SyncEnvelope, missingEntityType: String, missingEntityID: String,
    aliasSourceType: String, aliasTargetID: String
  ) throws -> SyncEnvelope? {
    if aliasSourceType != missingEntityType {
      return nil
    }

    var remapped = envelope
    let isCompositeEdge = CompositeEdge.isCompositeEdgeEntityType(envelope.entityType.asString)
    if isCompositeEdge {
      // Both a split failure (malformed id) and a no-op rewrite drop the entry.
      guard
        case .success(let maybeID) = CompositeEdge.remapCompositeEdgeId(
          envelope.entityId, oldPart: missingEntityID, newPart: aliasTargetID),
        let entityID = maybeID
      else {
        return nil
      }
      remapped.entityId = entityID
    }

    guard var payloadValue = JSONValue.parse(envelope.payload) else {
      throw EnqueueError.malformedPayload("pending inbox envelope payload is not valid JSON")
    }
    let payloadChanged = ApplyRedirect.remapPayloadIdentityFields(
      entityType: envelope.entityType.asString, payload: &payloadValue,
      originalId: missingEntityID, targetId: aliasTargetID)

    // Composite edges: the entity_id rewrite above suffices even when older
    // peers omitted the typed payload fields. Non-composite entities with no
    // payload change carry no actionable redirect — drop.
    if !isCompositeEdge && !payloadChanged {
      return nil
    }

    remapped.payload = try SyncCanonicalize.canonicalizeJSON(payloadValue)
    return remapped
  }

  // MARK: - helpers

  private static func missingFromReason(_ reason: DeferralReason) -> (String?, String?) {
    switch reason {
    case .missingDependency(let entityType, let entityId):
      return (entityType.asString, entityId)
    case .aggregateInvariantBlocked(let entityType, let entityId, _):
      return (entityType.asString, entityId)
    case .schemaTooNew, .operationallyUnusableHlc, .auditRetentionFrontierRefresh:
      return (nil, nil)
    }
  }

  /// Whether a deferral is a by-design HOLD that must NOT count toward the
  /// per-row retry budget (timestamp-only refresh, no `attempt_count` bump):
  ///
  /// * `schemaTooNew` — waits on a local schema upgrade.
  /// * `aggregateInvariantBlocked` — a peer envelope a receiving device must
  ///   refuse until an aggregate invariant relaxes (e.g. a `delete(inbox)` a
  ///   task-holding peer can never satisfy while tasks reference it, or a
  ///   last-list delete). This is a correct standing refusal, not a failing
  ///   retry, so it must not burn the 50-attempt cap and raise a false
  ///   `pending_inbox_exhausted` / `reseed_required`. It is retained past the
  ///   retention horizon (the parked row is the only local copy of the record)
  ///   and drains the moment the invariant relaxes.
  ///
  /// A `missingDependency` deferral is NOT exempt — a genuinely missing FK parent
  /// that never arrives should exhaust and quarantine.
  private static func isBudgetExemptHold(_ reason: DeferralReason) -> Bool {
    switch reason {
    case .schemaTooNew, .operationallyUnusableHlc,
      .auditRetentionFrontierRefresh, .aggregateInvariantBlocked:
      return true
    case .missingDependency:
      return false
    }
  }

  /// SQL boolean expression over the `sync_pending_inbox.reason` column selecting
  /// the by-design budget-exempt HOLD rows — the row analog of
  /// ``isBudgetExemptHold(_:)``: the future-record lane (``entityTypeTooNewReason``)
  /// plus the two typed deferrals it recognizes (``DeferralReason/schemaTooNew``
  /// and ``DeferralReason/aggregateInvariantBlocked``, matched by their stable
  /// message markers).
  ///
  /// The retention sweep keys two decisions off this predicate:
  ///
  /// * It counts these OUT of the `reseed_required` signal: a correct standing
  ///   refusal or a not-yet-understood future record is not an orphan a full
  ///   reseed could resolve — re-pulling the same record only re-creates the
  ///   same HOLD and loops the reseed prompt.
  /// * It EXEMPTS them from the horizon reap: the change token has already
  ///   advanced past the parked record, so the pending row is the only local
  ///   copy; reaping it would silently lose newer-peer data. Superseded parked
  ///   versions of the same entity coalesce instead
  ///   (``SyncRetention/coalesceSupersededHoldsPastHorizon(_:horizonDays:)``).
  ///
  /// Genuine orphans (missing-dependency / `fk_unresolved`) are not
  /// budget-exempt: they still raise the signal and are still reaped. Kept in
  /// lockstep with the reason strings written by ``holdUnknownTypeRecord`` and
  /// ``DeferralReason/message``.
  static let budgetExemptHoldReasonSQL = budgetExemptHoldReasonSQL(column: "reason")

  /// ``budgetExemptHoldReasonSQL`` with the `reason` column reference spelled as
  /// `column`, for queries that alias `sync_pending_inbox` (e.g. the horizon
  /// coalesce's self-join needs `older.reason` / `newer.reason`).
  static func budgetExemptHoldReasonSQL(column: String) -> String {
    """
    \(column) = '\(entityTypeTooNewReason)'
    OR \(column) LIKE '\(DeferralReason.schemaTooNewReasonMarker)%'
    OR \(column) LIKE '\(DeferralReason.operationallyUnusableHlcReasonMarker)%'
    OR \(column) LIKE '\(DeferralReason.auditRetentionFrontierReasonMarker)%'
    OR \(column) LIKE '%\(DeferralReason.aggregateInvariantBlockedReasonMarker)'
    """
  }

  /// Deserialize a pending row's stored envelope JSON back into a `SyncEnvelope`.
  static func parseEnvelope(_ entry: PendingInbox.Entry) throws -> SyncEnvelope {
    guard let data = entry.envelopeJSON.data(using: .utf8) else {
      throw EnqueueError.malformedPayload("pending inbox envelope JSON is not valid UTF-8")
    }
    return try JSONDecoder().decode(SyncEnvelope.self, from: data)
  }

  static func serializeEnvelope(_ envelope: SyncEnvelope) throws -> String {
    let data = try JSONEncoder().encode(envelope)
    return String(decoding: data, as: UTF8.self)
  }
}
