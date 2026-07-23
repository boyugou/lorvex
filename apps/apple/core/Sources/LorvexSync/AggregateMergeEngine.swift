import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Outcome of a UNIQUE-collision insert routed through
/// ``AggregateMergeEngine/insertByMergingCollision``: whether the incoming row is
/// the live survivor (so the caller runs its post-upsert tail) and whether the
/// merge already ran (so the post-upsert tail does not double-fire). Shared by
/// every entity that resolves an insert-time UNIQUE collision by merging.
struct CollisionMergeOutcome {
  var incomingSurvived: Bool
  var mergeRan: Bool
}

/// Why an aggregate collapse is running. Natural-key discovery authors a new
/// identity union; applying an already-durable permanent alias only materializes
/// that existing union against a still-live local source row.
enum AggregateMergeMode {
  case naturalKey
  case permanentAlias
}

/// The shared aggregate-merge scaffold for every `lookup_key` / natural-key
/// dedup merge (`tag`, `habit`, `memory`, `habit_reminder_policy`).
///
/// **Identity and content are decided separately.** `min(id)` always wins
/// canonical IDENTITY: the surviving row keeps the lexicographically smallest
/// participant id, every loser re-points its synced children to it, is deleted
/// with an ordinary death barrier, and is permanently aliased to the winner. A
/// natural-key merge authors that alias; permanent-alias materialization reuses
/// the alias that already exists. The max-HLC participant's CONTENT survives: the content reference
/// `P*` is the participant whose `version` HLC strictly dominates under
/// ``canonicalPreferringDominates(incoming:existing:)`` (canonical beats tainted),
/// ties resolving to the lower id. When `P*` is not the min-id winner its content
/// is copied onto the winner via ``carryContent`` before any loser is deleted.
/// Surviving content is therefore a pure, deterministic function of the
/// participant set.
///
/// Natural-key discovery mints a merge HLC strictly dominating every canonical
/// parent participant and stamps the winner to it. Permanent-alias
/// materialization keeps `P*`'s content HLC, matching the alias-first path where
/// the source payload is remapped directly onto the target. Descendant re-point
/// hooks preserve each child's own LWW semantics; content-bearing edges retain
/// the winning child participant's authored clock rather than inheriting a
/// parent identity clock. Folding child HLCs into the parent would make its
/// version depend on cross-entity arrival order. A
/// conflict-log row records every CONTENT-loser (each participant except `P*`) at
/// its own version: when `P* == winnerId` the content-losers are exactly the
/// identity-losers; when `P*` is a higher-HLC loser the surviving
/// min-id row itself becomes a content-loser and its discarded fields are logged.
/// The control flow lives here ONCE. Each entity supplies only its per-entity
/// hooks (``prepareDivergence`` for the conflict-log field comparison against
/// `P*`, ``carryContent`` for the max-HLC content copy, and
/// ``repointAndDeleteLoser`` for the child re-point SQL) plus its identity
/// metadata.
///
/// The three convergence behaviors that MUST stay uniform across every entity are
/// centralized here so no per-entity copy can drift:
///   * a tainted participant version is SKIPPED (non-fatal) when computing the
///     merge `maxHlc`, so a corrupt local version can never make the batch fatal;
///   * a loser whose version does not parse falls back to the raw version string
///     as its `loser_device_id` (``loserDeviceSuffix(_:)``);
///   * the post-upsert entry point skips re-firing on a known redirect-loser via
///     a non-fatal `try?` guard.
///
/// **Natural-key merge versions are deterministic and emitted.** The merge
/// HLC is minted as `(maxHlc.physicalMs, maxHlc.counter + 1, maxHlc.deviceSuffix)`
/// — the smallest canonical successor of the dominating participant's version.
/// The same transaction emits three independent current-state records: the
/// winner upsert, one permanent `entity_redirect` upsert per loser, and one
/// ordinary loser delete. Peers can therefore converge without independently
/// rediscovering the original natural-key collision; generation/full-resync
/// reconstruction republishes all three durable states.
/// Applying an existing permanent alias emits only the canonical winner and any
/// missing corrective delete; a source that already has a durable alias never
/// gains a second one (a displaced live terminal without a direct alias gains
/// its first, at the joined identity version), and the winner never rises above
/// its selected content provenance.
///
/// **`created_at` is a min-register, not content and not identity-pinned.** The
/// winner's `created_at` folds to the minimum across the participant set, and
/// every apply-side path folds the same lattice per observed payload
/// (``ApplyLww/foldCreatedAtFloor(_:table:pkValue:incomingCreatedAt:)``) — even
/// on LWW-rejected envelopes. The fold needs only envelope-local information,
/// so a peer that received the alias before ever materializing the target row
/// still converges to the same floor as a collapse peer.
///
/// One convergent (not divergent) residual remains: a concurrent peer edit whose
/// own HLC lands in the exact `(maxHlc.physicalMs, maxHlc.counter + 1)` slot ties
/// the merge stamp and resolves on the suffix — but that suffix is now identical
/// on every peer, so the tie breaks the same way everywhere. Pinning the stamp to
/// a true global-max content version would need a persisted content-provenance
/// column (a schema change); the deterministic-suffix stamp is the accepted
/// alternative for natural-key discovery. This holds uniformly for all four
/// merge families (tag, memory, habit, habit reminder policy).
struct AggregateMergeEngine {
  /// Compute a content-loser's divergent-fields JSON (or `nil` when it matches the
  /// surviving content) for the conflict log. Throws when a snapshot row is
  /// unexpectedly missing. The built-in hooks are stateless — each loser is
  /// compared against a reference captured up front (`P*`) — so the log never
  /// depends on arrival order.
  typealias LoserDivergence = (_ loserId: String) throws -> String?

  /// Canonical entity type name (``EntityName``) — used for both the loser
  /// tombstone and the conflict-log `entity_type`.
  let entityName: String
  /// Aggregate table the winner/loser rows live in.
  let table: String
  /// Conflict-log `resolution_type` (``ResolutionName``).
  let resolutionType: String
  /// Savepoint name wrapping one merge run.
  let savepointName: String
  /// Human label for the mint context (`"<label> merge"`) and the collision
  /// no-winner error (`"<label> collision merge for <id> produced no winner"`).
  let mergeLabel: String
  /// When `false` (tag) a content-loser matching `P*` writes NO
  /// conflict-log row; when `true` the row is written even with a `nil` payload.
  let alwaysLogConflict: Bool
  /// Whether the aggregate table carries a `created_at` min-register
  /// (`tags` / `habits` / `habit_reminder_policies`; `memories` has no
  /// `created_at` column). When `true` the engine stamps the winner's
  /// `created_at` to the minimum across the whole participant set while every
  /// participant row is still live — the same lattice the apply-side folds use
  /// (``ApplyLww/foldCreatedAtFloor(_:table:pkValue:incomingCreatedAt:)``), so a
  /// collapse peer and a peer that only ever folded remapped envelopes converge
  /// byte-identically.
  let foldsCreatedAtFloor: Bool
  /// Copy the content columns of the content reference `P*` (`sourceId`) onto the
  /// min-id winner (`winnerId`). Called BEFORE any loser is deleted, and only when
  /// `P* != winnerId`. Carries the
  /// entity's divergence-snapshot columns plus `updated_at` for mtime coherence.
  /// Natural-key mode excludes its staged collision key; permanent-alias mode
  /// may carry a renamed key or parent FK after first vacating the source's
  /// uniqueness slot. Identity `id` and content `version` never move here, and
  /// `created_at` is never carried — the engine owns it as the participant-set
  /// min-register (`foldsCreatedAtFloor`). Runs on the live `sourceId` row.
  let carryContent:
    (
      _ db: Database, _ winnerId: String, _ sourceId: String,
      _ mode: AggregateMergeMode
    ) throws -> Void
  /// Read the content-reference (`P*`) + every content-loser snapshot once,
  /// returning a per-loser divergence hook that compares each content-loser
  /// against `P*`. The snapshots are captured here — before ``carryContent`` — so
  /// a content-loser that is itself the min-id winner still logs its pre-carry
  /// fields.
  let prepareDivergence:
    (_ db: Database, _ referenceId: String, _ participantIds: [String]) throws
      -> LoserDivergence
  /// Re-point the loser's synced children onto the winner and delete the loser
  /// row. Nested child identity collisions run their own aggregate merger and
  /// therefore emit their own durable redirect records.
  let repointAndDeleteLoser:
    (
      _ db: Database, _ loserId: String, _ winnerId: String, _ mergeVersion: String,
      _ applyTs: String
    ) throws -> Void

  // MARK: - Entry points

  /// Post-upsert convergence tail: collapse every row that shares the just-
  /// upserted row's natural key. `whereClause` is the `WHERE` body of a
  /// `SELECT id, version FROM <table> WHERE <whereClause> ORDER BY id ASC`.
  func mergeDuplicate(
    _ db: Database, justUpsertedId: String, whereClause: String, whereArgs: StatementArguments,
    triggeringVersion: String, applyTs: String
  ) throws {
    // Non-fatal redirect-loser skip guard: when the just-upserted id is itself a
    // known redirect-loser the cluster has already agreed on the winner, so re-
    // firing would spam the conflict log + tombstone on every replay.
    if (try? EntityRedirect.get(
      db, sourceType: entityName, sourceId: justUpsertedId)) != nil
    {
      return
    }

    let rows: [(String, String)]
    do {
      rows = try Row.fetchAll(
        db, sql: "SELECT id, version FROM \(table) WHERE \(whereClause) ORDER BY id ASC",
        arguments: whereArgs
      ).map { ($0[0], $0[1]) }
    } catch { throw ApplyError.lift(error) }

    _ = try mergeKnownDuplicate(
      db, rows: rows, triggeringVersion: triggeringVersion, applyTs: applyTs)
  }

  /// Merge a caller-provided duplicate set (used by the insert-collision path
  /// where the incoming row is staged outside the offending index). Returns the
  /// surviving `min(id)` winner, or `nil` when there is nothing to merge.
  /// `beforeWinnerEnqueue` runs after every identity loser has been removed and
  /// the winner version has been stamped, but before the canonical winner payload
  /// is snapshotted and enqueued. Collision callers use it to restore a natural
  /// key that was temporarily cleared while staging the incoming participant.
  @discardableResult
  func mergeKnownDuplicate(
    _ db: Database, rows unsortedRows: [(String, String)], triggeringVersion: String,
    applyTs: String,
    mode: AggregateMergeMode = .naturalKey,
    beforeWinnerEnqueue: ((_ db: Database, _ winnerId: String) throws -> Void)? = nil,
    evolutionIntroductions: [SyncPayloadFieldIntroduction] =
      SyncPayloadEvolution.fieldIntroductions,
    collisionEvolutionAdapters: [PayloadEvolutionCollisionAdapter] =
      PayloadEvolutionCollisionAdapterRegistry.registered
  ) throws -> String? {
    if unsortedRows.count <= 1 { return nil }
    let rows = unsortedRows.sorted { $0.0 < $1.0 }
    let ids = rows.map { $0.0 }
    let versions = rows.map { $0.1 }

    try StoreTransactions.withSavepoint(db, savepointName) { db in
      try runInner(
        db, ids: ids, versions: versions, triggeringVersion: triggeringVersion, applyTs: applyTs,
        mode: mode, beforeWinnerEnqueue: beforeWinnerEnqueue,
        evolutionIntroductions: evolutionIntroductions,
        collisionEvolutionAdapters: collisionEvolutionAdapters)
    }
    return ids[0]
  }

  /// Resolve a UNIQUE collision raised by an insert: stage the incoming row
  /// beside the existing claimant (`stageIncoming`), collapse the duplicates, and
  /// restore the winner's real key when the incoming row survived. `existingRows`
  /// is the pre-fetched claimant set; an empty set means the violated constraint
  /// was NOT the merge's key, so the original error is surfaced unchanged.
  func insertByMergingCollision(
    _ db: Database, entityId: String, version: String, applyTs: String,
    existingRows: [(String, String)], originalError: DatabaseError, collisionSavepoint: String,
    stageIncoming: (Database) throws -> Void, restoreWinner: @escaping (Database) throws -> Void
  ) throws -> CollisionMergeOutcome {
    if existingRows.isEmpty {
      throw ApplyError.lift(originalError)
    }

    var incomingSurvived = false
    try StoreTransactions.withSavepoint(db, collisionSavepoint) { db in
      do {
        try stageIncoming(db)
      } catch { throw ApplyError.lift(error) }

      guard
        let winnerId = try mergeKnownDuplicate(
          db, rows: existingRows + [(entityId, version)], triggeringVersion: version,
          applyTs: applyTs,
          beforeWinnerEnqueue: { db, winnerId in
            if winnerId == entityId { try restoreWinner(db) }
          })
      else {
        throw ApplyError.store("\(mergeLabel) collision merge for \(entityId) produced no winner")
      }
      incomingSurvived = winnerId == entityId
    }
    return CollisionMergeOutcome(incomingSurvived: incomingSurvived, mergeRan: true)
  }

  // MARK: - Generic inner loop

  private func runInner(
    _ db: Database, ids: [String], versions: [String], triggeringVersion: String, applyTs: String,
    mode: AggregateMergeMode,
    beforeWinnerEnqueue: ((_ db: Database, _ winnerId: String) throws -> Void)?,
    evolutionIntroductions: [SyncPayloadFieldIntroduction],
    collisionEvolutionAdapters: [PayloadEvolutionCollisionAdapter]
  ) throws {
    let winnerId = ids[0]

    guard let entityType = EntityKind.parse(entityName) else {
      throw ApplyError.unknownEntityType(entityName)
    }

    // A payload shadow contains fields this runtime cannot interpret. No
    // current or future field adapter can make an already-shipped older binary
    // decide whether an independently-authored duplicate's field absence means
    // preserve or clear. Hold every cross-id collision while any participant is
    // opaque; after upgrade, promotion materializes the fields and removes the
    // shadow before the ordinary typed adapter/merge path runs.
    for id in ids {
      do {
        if try PayloadShadow.getShadow(db, entityType: entityName, entityID: id) != nil {
          throw ApplyError.deferForwardCompat(
            .aggregateInvariantBlocked(
              entityType: entityType, entityId: winnerId,
              invariant: "opaque future payload fields require a schema-aware cross-id merge"))
        }
      } catch let error as ApplyError {
        throw error
      } catch { throw ApplyError.lift(error) }
    }

    let evolutionAdapters = try PayloadEvolutionCollisionAdapterRegistry.adaptersOrDefer(
      entityType: entityType, entityID: winnerId, introductions: evolutionIntroductions,
      adapters: collisionEvolutionAdapters)

    // Content reference P*. Identity is always min(id); the known content follows the
    // max-HLC participant (canonical-preferring, min-id tiebreak). `ids`/`versions` are id-ascending
    // parallel arrays, so the LEFT fold keeps the lower id on an equal-HLC tie.
    var pStar = ids[0]
    var bestVersion = versions[0]
    for i in 1..<ids.count
    where canonicalPreferringDominates(
      incoming: versions[i], existing: bestVersion)
    {
      pStar = ids[i]
      bestVersion = versions[i]
    }

    if !evolutionAdapters.isEmpty {
      let context = PayloadEvolutionCollisionContext(
        entityType: entityType, winnerID: winnerId, contentReferenceID: pStar,
        participants: Array(zip(ids, versions)).map { (id: $0.0, version: $0.1) })
      for adapter in evolutionAdapters {
        do {
          try adapter.preserveFields(db, context)
        } catch let error as ApplyError {
          throw error
        } catch { throw ApplyError.lift(error) }
      }
    }

    // Conflict-log participants are every id except the content reference P*.
    // Their divergence is compared against P* after evolution adapters have
    // restored any fields that survive the collision, but before carry mutates
    // the canonical winner row.
    let contentLoserIds = ids.filter { $0 != pStar }
    let divergenceFor = try prepareDivergence(db, pStar, contentLoserIds)

    let triggeringHlc: Hlc
    do {
      triggeringHlc = try Hlc.parseCanonical(triggeringVersion)
    } catch { throw ApplyError.invalidVersion("\(error)") }

    let mergeVersion: String
    switch mode {
    case .naturalKey:
      // Natural-key discovery authors a new identity union. The parent stamp is
      // a pure function of parent participants; a tainted participant is skipped
      // so corrupt local state cannot wedge duplicate cleanup.
      var maxHlc = triggeringHlc
      for version in versions {
        if let h = try? Hlc.parseCanonical(version), h > maxHlc { maxHlc = h }
      }
      let mergeHlc = try Self.mintMergeHlcAfter(
        maxHlc, mergeSuffix: maxHlc.deviceSuffix, context: "\(mergeLabel) merge")
      mergeVersion = mergeHlc.description
      SyncHlcObserver.observeLocalEvent(mergeHlc)
    case .permanentAlias:
      // This identity union already exists durably. Do not mint a second alias
      // clock only because this peer happened to retain the source row until the
      // alias arrived; an alias-first peer never authors that extra event.
      mergeVersion = triggeringHlc.description
    }

    let now = applyTs

    // Carry the max-HLC content onto the min-id winner BEFORE any loser is
    // deleted — P* may itself be an identity-loser about to be removed (and its
    // children, e.g. habit_weekdays, cascade away with it). Evolution adapters
    // run first so their reconstructed fields are part of this same carry.
    if pStar != winnerId {
      try carryContent(db, winnerId, pStar, mode)
    }

    // created_at min-register fold across the participant set, while every
    // participant row is still live. See `foldsCreatedAtFloor`.
    if foldsCreatedAtFloor {
      let placeholders = Sql.sqlInPlaceholders(ids.count, 0)
      do {
        try db.execute(
          sql: """
            UPDATE \(table)
               SET created_at = (SELECT min(created_at) FROM \(table)
                                  WHERE id IN (\(placeholders)))
             WHERE id = ?
            """,
          arguments: StatementArguments(ids + [winnerId]))
      } catch { throw ApplyError.lift(error) }
    }

    // Conflict log: one row per content-loser (each id except P*), recording that
    // participant's own discarded fields against P*, at its own version. When
    // P* == winnerId these are exactly the identity-losers → unchanged from the
    // pre-content-split behavior.
    for (id, version) in zip(ids, versions) where id != pStar {
      let loserDeviceId = Self.loserDeviceSuffix(version)
      let loserPayload = try divergenceFor(id)
      if loserPayload != nil || alwaysLogConflict {
        try ConflictLog.logConflict(
          db,
          ConflictLog.Entry(
            entityType: entityName, entityId: winnerId, winnerVersion: mergeVersion,
            loserVersion: version, loserDeviceId: loserDeviceId, loserPayload: loserPayload,
            resolvedAt: now, resolutionType: resolutionType))
      }
    }

    // Identity losers: every id except the min-id winner re-points its children
    // and is deleted. Natural-key discovery authors the independent alias;
    // permanent-alias materialization reuses the alias that led here.
    for loserId in ids where loserId != winnerId {
      try repointAndDeleteLoser(db, loserId, winnerId, mergeVersion, now)

      let deviceId = try SyncCheckpoints.getOrCreateDeviceId(db)
      let redirect: EntityRedirect.Record
      switch mode {
      case .naturalKey:
        redirect = try EntityRedirect.upsertAndEnqueue(
          db, sourceType: entityType, sourceId: loserId, targetId: winnerId,
          version: mergeVersion, createdAt: now, deviceId: deviceId)
      case .permanentAlias:
        if let existing = try EntityRedirect.get(
          db, sourceType: entityName, sourceId: loserId)
        {
          let chase = try ApplyRedirect.chaseRedirectChain(
            db, initialEntityType: entityName, initialEntityId: loserId)
          guard chase.finalId == winnerId else {
            throw ApplyError.store(
              "permanent alias merge target changed during aggregate collapse")
          }
          redirect = existing
        } else {
          // A competing-alias union can expose a displaced live terminal that
          // does not yet have a direct alias. Materialize the joined identity
          // version supplied by the outer redirect operation, without minting a
          // second aggregate-merge successor.
          redirect = try EntityRedirect.upsertAndEnqueue(
            db, sourceType: entityType, sourceId: loserId, targetId: winnerId,
            version: mergeVersion, createdAt: now, deviceId: deviceId)
        }
        try Tombstone.createTombstone(
          db, entityType: entityName, entityId: loserId,
          version: redirect.version, deletedAt: now)
      }

      // Replace any queued or already-shared stale loser upsert with an ordinary
      // domain delete. Peers receive the independent alias upsert before deletes
      // in the apply partition, so this death barrier cannot destroy the winner.
      try OutboxEnqueue.enqueueAliasSourceDelete(
        db, entityType: entityName, entityId: loserId,
        version: redirect.version, deviceId: deviceId)
    }

    // Natural-key discovery authors a new canonical root snapshot. An existing
    // permanent alias preserves P*'s content HLC, matching the alias-first path
    // where the source envelope is remapped directly onto the target.
    let winnerVersion: String
    switch mode {
    case .naturalKey:
      winnerVersion = mergeVersion
    case .permanentAlias:
      // `bestVersion` is canonical whenever any participant is; an all-tainted
      // participant set falls back to the already-validated alias version so
      // local corruption cannot wedge inbound alias application — mirroring the
      // natural-key taint resilience above.
      winnerVersion = (try? Hlc.parseCanonical(bestVersion)) != nil ? bestVersion : mergeVersion
    }
    try ApplyLww.stampMergeWinnerVersion(
      db, table: table, pkColumn: "id", pkValue: winnerId, mergeVersion: winnerVersion)

    // Insert-collision callers temporarily clear their natural key so the
    // incoming row can coexist with the current claimant. When that incoming row
    // wins canonical identity, restore the key after every loser is gone but
    // before reading the winner snapshot; otherwise opposite arrival orders emit
    // different wire payloads even though their live rows converge.
    if let beforeWinnerEnqueue {
      do {
        try beforeWinnerEnqueue(db, winnerId)
      } catch { throw ApplyError.lift(error) }
    }

    // The winner may now carry content copied from an identity-loser whose own
    // pending upsert was replaced by the delete above. Emit the canonical winner
    // explicitly so that carried content and re-pointed children are not merely
    // local, wire-silent state.
    let deviceId = try SyncCheckpoints.getOrCreateDeviceId(db)
    let winnerPayload = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: entityName, entityId: winnerId)
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: entityName, entityId: winnerId, payload: winnerPayload,
      context: OutboxWriteContext(version: winnerVersion, deviceId: deviceId))
  }

  // MARK: - Shared divergence scaffold

  /// Build a ``prepareDivergence`` hook for the common merge shape: read a
  /// `[String: S]` snapshot map for the content reference `P*` + every
  /// content-loser in ONE batched call, then compute each content-loser's
  /// divergent-fields JSON against `P*`.
  ///
  /// `label` names the entity in the two structural errors (`"<label> merge
  /// reference row missing"` when the `P*` snapshot is absent, `"<label> merge
  /// fields read missed loser row"` when a content-loser snapshot is absent);
  /// `read` batches the reference+loser snapshot read with the reference id first;
  /// `compare` returns a content-loser's divergent-fields JSON, or `nil` when the
  /// loser matches `P*`. Holds the read-guard-compare scaffold once so the
  /// per-entity dedup merges cannot drift apart.
  ///
  /// Merges that don't fit this shape keep their own hand-written hook: the memory
  /// merge records each content-loser's own whole payload rather than a field diff
  /// against `P*`.
  static func snapshotDivergence<S>(
    label: String,
    read: @escaping (Database, [String]) throws -> [String: S],
    compare: @escaping (S, S) -> String?
  ) -> (_ db: Database, _ referenceId: String, _ participantIds: [String]) throws -> LoserDivergence
  {
    { db, referenceId, participantIds in
      var snapshots = try read(db, [referenceId] + participantIds)
      guard let referenceFields = snapshots.removeValue(forKey: referenceId) else {
        throw ApplyError.store("\(label) merge reference row missing for id=\(referenceId)")
      }
      return { loserId in
        guard let loserFields = snapshots.removeValue(forKey: loserId) else {
          throw ApplyError.store(
            "\(label) merge fields read missed loser row: reference_id=\(referenceId) "
              + "loser_id=\(loserId)")
        }
        return compare(referenceFields, loserFields)
      }
    }
  }

  // MARK: - Shared apply-time HLC helpers

  /// The `loser_device_id` for a merge loser: the parsed HLC's device suffix, or
  /// the raw version string when it does not parse (a tainted local version is
  /// still recorded verbatim rather than dropped to an empty attribution).
  static func loserDeviceSuffix(_ version: String) -> String {
    if let h = try? Hlc.parseCanonical(version) { return h.deviceSuffix }
    return version
  }

  /// Mint the smallest canonical HLC that strictly dominates `maxHlc`. Returns an
  /// error when no successor is representable (participant already at the
  /// physical-ms + counter ceiling).
  static func mintMergeHlcAfter(_ maxHlc: Hlc, mergeSuffix: String, context: String) throws -> Hlc {
    let candidate: Hlc
    do {
      if maxHlc.counter < Hlc.maxCounter {
        candidate = try Hlc(
          physicalMs: maxHlc.physicalMs, counter: maxHlc.counter + 1, deviceSuffix: mergeSuffix)
      } else if maxHlc.physicalMs < Hlc.maxPhysicalMs {
        candidate = try Hlc(
          physicalMs: maxHlc.physicalMs + 1, counter: 0, deviceSuffix: mergeSuffix)
      } else {
        throw ApplyError.invalidVersion(
          "\(context): no canonical HLC successor exists after \(maxHlc.description)")
      }
    } catch let e as ApplyError {
      throw e
    } catch {
      throw ApplyError.invalidVersion(
        "\(context): minted merge_version with invalid merge device suffix: \(error)")
    }
    guard Hlc.isOperationallyAcceptableWire(candidate) else {
      throw ApplyError.invalidVersion(
        "\(context): no operational wire HLC successor exists after \(maxHlc.description)")
    }
    return candidate
  }
}
