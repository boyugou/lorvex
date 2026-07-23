import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// `EnvelopeSyncServicing` conformance for the pure-Swift backend: bridges a
/// sync transport to the ported `LorvexSync` engine over the service's existing
/// `write` transaction funnel. Conflict resolution stays entirely in the engine
/// (`Apply.applyEnvelope`); this adapter only moves envelopes across the
/// `sync_outbox` / pending-inbox boundary.
extension SwiftLorvexCoreService: EnvelopeSyncServicing {
  /// One shared applier registry — the appliers are stateless value types, so a
  /// per-process instance is reused across every inbound batch.
  static let inboundRegistry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())
  static let remoteFetchFailureCheckpointKey =
    "cloudkit_per_record_fetch_failure_checkpoint"
  static let remoteFetchFailureCountKey =
    "cloudkit_per_record_fetch_failure_count"

  /// Startup maintenance: promote forward-compat payload shadows whose schema
  /// version this build now understands into the canonical tables. Runs once
  /// against a freshly-opened store, before any sync cycle, so fields truncated
  /// under an older parser are repaired as soon as the upgraded build launches.
  /// Best-effort at the row level (`ApplyPromote` isolates each shadow in a
  /// savepoint and logs failures); the store-open caller treats a thrown batch
  /// error as a logged warning, never an open failure. A successful canonical
  /// promotion advances the same cross-process invalidation witness as inbound
  /// apply, in the promotion transaction; otherwise another already-running
  /// surface can keep rendering the pre-upgrade projection indefinitely.
  static func promoteStartupPayloadShadows(_ store: LorvexStore) throws -> Int {
    let promoted = try store.writer.write { db in
      let promoted = try ApplyPromote.promotePayloadShadows(db, registry: inboundRegistry)
      if promoted > 0 {
        try LocalChangeSeq.bump(db)
        Overview.invalidateStreakCache(db)
      }
      return promoted
    }
    if promoted > 0 { DatabaseChangeSignal.broadcastIfEnabled() }
    return promoted
  }

  public func pendingOutbound() throws -> [PendingOutboundEnvelope] {
    try pendingOutbound(afterOutboxId: nil)
  }

  public func pendingOutbound(afterOutboxId: Int64?) throws -> [PendingOutboundEnvelope] {
    try pendingOutboundPage(
      afterOutboxId: afterOutboxId,
      now: SyncTimestampFormat.syncTimestampNow()).envelopes
  }

  public func pendingOutboundPage(
    afterOutboxId: Int64?, now: String
  ) throws -> PendingOutboundPage {
    // `Outbox.getPendingPage` may park an undecodable row inline, so this runs
    // in a write transaction even though the common no-poison path only reads.
    try write { db in
      let page = try Outbox.getPendingPage(
        db, now: now, afterOutboxId: afterOutboxId)
      return PendingOutboundPage(
        envelopes: page.entries.map {
          PendingOutboundEnvelope(outboxId: $0.id, envelope: $0.envelope)
        },
        lastScannedOutboxId: page.lastScannedOutboxId)
    }
  }

  public func nextDeferredCloudSyncRetryAt(
    forAccountIdentifier accountIdentifier: String,
    zoneName: String
  ) throws -> Date? {
    try read { db in
      let deadlines = [
        try Outbox.earliestRetryAt(db),
        try AuditRetentionFrontier.earliestPurgeRetryAt(
          db, accountIdentifier: accountIdentifier, zoneName: zoneName),
      ].compactMap { $0 }
      return deadlines.min()
    }
  }

  public func runLocalRetentionMaintenance(includeActiveOutboxCap: Bool) throws {
    let syncedAt = SyncTimestampFormat.syncTimestampNow()
    try withStorageCutoverRetry {
      let (deviceId, clock) = try writeState()
      Self.afterWriteStateBarrierForTesting?()
      try withStoreCutoverImmediateTransaction { db in
        try self.assertCommittingDatabaseIdentity(db, expected: deviceId)
        Self.afterIdentityAssertBarrierForTesting?()
        let transactionClock = try clock.makeTransactionHandle(db)
        try Self.$currentTransactionClock.withValue(transactionClock) {
          try SyncHlcObserver.withTransactionObserver({ value in
            transactionClock.reserveAfterDeterministicMerge(value)
          }) {
            let auditCountBefore =
              try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
            SyncRetention.runLocalMaintenanceGC(
              db, syncedAt: syncedAt,
              includeActiveOutboxCap: includeActiveOutboxCap)
            let auditCountAfter =
              try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
            if auditCountAfter < auditCountBefore {
              try LocalChangeSeq.bump(db)
              Overview.invalidateStreakCache(db)
            }
            try transactionClock.persistHighWaters(db)
          }
        }
      }
    }
  }

  @discardableResult
  public func enqueueFullResyncBackfill() throws -> FullResyncBackfillReport {
    try write { db in
      try Outbox.enqueueAllLiveForFullResync(db)
    }
  }

  public func enqueueFullResyncBackfill(
    tombstoneCompactionCutoff: String?
  ) throws -> FullResyncBackfillReport {
    try write { db in
      try Outbox.enqueueAllLiveForFullResync(
        db, tombstoneCompactionCutoff: tombstoneCompactionCutoff)
    }
  }

  public func compactCloudConfirmedTombstones(through cutoff: String) throws -> UInt64 {
    try write { db in try Tombstone.compactCloudConfirmed(db, through: cutoff) }
  }

  public func trustedTombstoneCompactionCutoff(
    forAccountIdentifier accountIdentifier: String
  ) throws -> String? {
    try read { db in
      try Tombstone.trustedCompactionCutoff(
        db, accountIdentifier: accountIdentifier,
        recoveryDays: SyncNaming.tombstoneMaxRetentionDays)
    }
  }

  public func trustedTerminalServerTimeCovers(
    cutoff: String, forAccountIdentifier accountIdentifier: String
  ) throws -> Bool {
    try read { db in
      try Tombstone.trustedTerminalServerTimeCovers(
        db, accountIdentifier: accountIdentifier, cutoff: cutoff)
    }
  }

  /// Whether the durable `reseed_required` checkpoint is set (see
  /// ``EnvelopeSyncServicing/isReseedRequired()``). Cleared by a complete
  /// full-resync backfill pass, never here.
  public func isReseedRequired() throws -> Bool {
    try read { db in
      try SyncCheckpoints.get(db, key: SyncCheckpoints.keyReseedRequired) == "true"
    }
  }

  /// The account-scoped enrolled zone epoch. Returns `nil` only when absent;
  /// malformed or negative stored state throws so recovery fails closed.
  public func enrolledZoneEpoch(forAccountIdentifier accountIdentifier: String) throws -> Int? {
    try read { db in
      guard
        let raw = try SyncCheckpoints.get(
          db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: accountIdentifier))
      else { return nil }
      guard let epoch = Int(raw), epoch >= 0 else {
        throw ZoneEpochCheckpointStateError.invalidEnrollment
      }
      return epoch
    }
  }

  /// Stable ordinary-upsert → ordinary-delete → permanent-alias partition of an
  /// inbound batch. Applying a
  /// winner upsert first lets the post-upsert aggregate merge tail see
  /// both the winner and the still-live loser sharing the natural key, derive the
  /// `loser → winner` alias locally before its ordinary loser delete. Explicit
  /// `entity_redirect` records run last so every live target or terminal target
  /// tombstone in the same page is established first. Relative order within each
  /// partition is preserved; HLC decides same-identity state.
  static func orderedForApply(_ envelopes: [SyncEnvelope]) -> [SyncEnvelope] {
    var upserts: [SyncEnvelope] = []
    var deletes: [SyncEnvelope] = []
    var redirects: [SyncEnvelope] = []
    for e in envelopes {
      if e.entityType == .entityRedirect {
        redirects.append(e)
      } else if e.operation == .delete {
        deletes.append(e)
      } else {
        upserts.append(e)
      }
    }
    return upserts + deletes + redirects
  }

  public func applyInbound(_ envelopes: [SyncEnvelope], undecodable: Int) throws
    -> InboundApplyReport
  {
    // Re-resolve identity AND the store handle on every attempt so a
    // cross-process factory reset landing between the two — detected inside the
    // transaction by the storage-cutover guard — is retried against the fresh
    // database rather than stamped with the erased one's identity.
    try withStorageCutoverRetry {
      try self.applyInboundAttempt(envelopes, undecodable: undecodable)
    }
  }

  func applyInboundAttempt(
    _ envelopes: [SyncEnvelope], undecodable: Int,
    traversalCommit: CloudTraversalCommitRequest? = nil,
    outboundReconciliation: OutboundReconciliationRequest? = nil,
    deferredUnknownTypeRecords: [RawEnvelopeFields] = [],
    cloudReceiptAccountIdentifier: String? = nil,
    cloudReceipts: [InboundCloudRecordReceipt] = [],
    inboundPageObservation: CloudInboundPageObservation? = nil
  ) throws
    -> InboundApplyReport
  {
    // The write block is @Sendable, so accumulate counts inside it and return a
    // value rather than mutating a captured var. An empty batch still drains:
    // a prior batch may have parked dependencies in the pending inbox that a
    // now-present entity can release.
    let (deviceId, clock) = try writeState()
    Self.afterWriteStateBarrierForTesting?()
    let syncedAt = SyncTimestampFormat.syncTimestampNow()
    let counts = try withStoreCutoverImmediateTransaction {
      db -> (Int, Int, Int, Int, Int, Int, Set<EntityKind>, Int, Set<Int64>) in
      // First statement in the transaction: abort before any peer state is
      // observed or minted if a cross-process factory reset redirected this
      // apply onto a fresh database.
      try self.assertCommittingDatabaseIdentity(db, expected: deviceId)
      if try Self.cloudTraversalPageWasAlreadyCommitted(db, request: traversalCommit) {
        return (0, 0, 0, 0, 0, 0, [], 0, [])
      }
      let deletedCloudRecordNames = Set(
        inboundPageObservation?.deletedRecordNames ?? [])
      let transactionClock = try clock.makeTransactionHandle(db)
      return try SyncHlcObserver.withTransactionObserver({ value in
        transactionClock.reserveAfterDeterministicMerge(value)
      }) {
        let hlc = HlcSession(handle: transactionClock)
        var applied = 0
        var skipped = 0
        var deferred = 0
        var remapped = 0
        var invalid = 0
        var retentionRejected = 0
        var repaired = 0
        var reconciledCollisionOutboxIds = Set<Int64>()
        var pendingRepairObligations: [PendingApplyRepair] = []
        var futureLocalIntentReplays: [FutureRecordHold.LocalIntentReplay] = []
        var resolvedCloudRecordNames = Set(
          inboundPageObservation?.resolvedRecordNames ?? [])
        var corruptCloudRecordNames = Set(
          inboundPageObservation?.corruptRecordNames ?? [])
        // The distinct entity kinds whose local rows actually changed — every
        // `.applied` / `.remapped` envelope's kind plus the drain's replayed kinds.
        // Drives the report's `appliedEntityTypes` so a store reloads only the
        // affected surfaces.
        var changedKinds: Set<EntityKind> = []
        var physicalDeletionChangedCanonicalState = false
        var physicalDeletionRequiresCompleteInventory = false
        if traversalCommit != nil {
          let physicalDeletion =
            try CloudInboundCompleteness.reconcilePhysicalDeletions(
              db, deletedRecordNames: deletedCloudRecordNames)
          changedKinds.formUnion(physicalDeletion.removedEntityTypes)
          physicalDeletionChangedCanonicalState =
            !physicalDeletion.removedEntityTypes.isEmpty
          physicalDeletionRequiresCompleteInventory =
            physicalDeletion.requiresCompleteInventory
          for reassertion in physicalDeletion.requiredReassertions.sorted(by: {
            if $0.entityType.rawValue != $1.entityType.rawValue {
              return $0.entityType.rawValue < $1.entityType.rawValue
            }
            return $0.entityId < $1.entityId
          }) {
            if reassertion.entityType == .entityRedirect {
              let outcome = try EntityRedirect.reassertCurrent(
                db, wireEntityId: reassertion.entityId, deviceId: deviceId)
              if outcome == .enqueued { repaired += 1 }
            } else {
              _ = try ConvergenceEmitter.enqueueCurrentCanonicalState(
                db, entityType: reassertion.entityType.asString,
                entityId: reassertion.entityId,
                mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
                deviceId: deviceId)
              repaired += 1
              changedKinds.insert(reassertion.entityType)
            }
          }
        }
        // Apply upserts before deletes (stable partition) so a within-batch
        // `upsert winner` + `delete loser` pair re-derives its redirect — see
        // ``orderedForApply(_:)``.
        for envelope in Self.orderedForApply(envelopes) {
          let cloudRecordName = traversalCommit.map { _ in
            SyncRecordName.opaque(
              entityType: envelope.entityType.asString, entityId: envelope.entityId)
          }
          // CloudKit physical deletion is terminal for this record slot. It is
          // reconciled before this envelope loop and the pending drain, and wins over a
          // pathological same-page decoded copy, matching reconcilePage's
          // deletion precedence without briefly materializing stale data.
          if let cloudRecordName, deletedCloudRecordNames.contains(cloudRecordName) {
            resolvedCloudRecordNames.insert(cloudRecordName)
            continue
          }
          // Validate at the wire boundary before the engine touches it; a crafted
          // oversized/empty envelope is dropped rather than aborting the batch.
          if case .failure(let validationError) = envelope.validate() {
            if let cloudRecordName { corruptCloudRecordNames.insert(cloudRecordName) }
            invalid += 1
            ErrorLog.appendBestEffort(
              db, source: "sync.apply.inbound_invalid",
              message:
                "dropping inbound envelope \(envelope.entityType.asString)/\(envelope.entityId) "
                + "version \(envelope.version.description): \(validationError.message)",
              details: nil, level: "error")
            continue
          }
          // A canonical HLC in the reserved wire-ceiling headroom has no safely
          // bounded local successor. Park and fence it before observing the clock
          // or touching canonical rows; ordinary far-future peer clocks below the
          // static boundary continue through the detached-edit design unchanged.
          if let reason = FutureRecordHold.clockDeferralReason(for: envelope.version) {
            try PendingInboxDrain.enqueueDeferred(db, envelope: envelope, reason: reason)
            if let cloudRecordName { resolvedCloudRecordNames.insert(cloudRecordName) }
            deferred += 1
            continue
          }
          // Advance the local clock past this remote version — for every valid
          // envelope, applied/skipped/deferred alike — so a later local edit of a
          // remote-touched row mints a dominating HLC rather than failing
          // versionSuperseded against a peer's future-relative clock.
          clock.observePeerEnvelope(envelope.version)
          // Capture list-delete rehome candidates before the trigger overwrites
          // `list_id`; if the delete lands, re-propagate those moves below.
          let rehomeCandidates: [String]
          let outcome: ApplyResult
          do {
            rehomeCandidates = try ListDeleteRehome.captureRehomeCandidates(
              db, envelope: envelope)
            outcome = try StoreTransactions.withSavepoint(db, "sync_apply_inbound_envelope") {
              db in
              try Apply.applyEnvelope(db, registry: Self.inboundRegistry, envelope: envelope)
            }
          } catch let applyError as ApplyError {
            if Self.shouldAbortInboundBatch(for: applyError) {
              throw applyError
            }
            if let cloudRecordName { corruptCloudRecordNames.insert(cloudRecordName) }
            invalid += 1
            ErrorLog.appendBestEffort(
              db, source: "sync.apply.inbound_invalid",
              message:
                "dropping inbound envelope \(envelope.entityType.asString)/\(envelope.entityId) "
                + "version \(envelope.version.description): \(applyError.message)",
              details: nil, level: "error")
            Self.logDependencyCycleRejectionIfNeeded(
              db, envelope: envelope, error: applyError, syncedAt: syncedAt)
            continue
          }
          if let cloudRecordName { resolvedCloudRecordNames.insert(cloudRecordName) }
          switch outcome {
          case .applied:
            try PendingInboxDrain.clearQuarantineThroughResolvedEnvelope(
              db, entityType: envelope.entityType.asString,
              entityID: envelope.entityId, version: envelope.version.description)
            if let replay = try FutureRecordHold.reconcileTerminalEnvelope(
              db, envelope: envelope, outcome: outcome)
            {
              futureLocalIntentReplays.append(replay)
            }
            applied += 1
            changedKinds.formUnion(
              try SyncMutationImpact.affectedEntityTypes(for: envelope))
            // The list-delete's trigger re-homed the captured tasks to inbox with
            // no version bump or outbox row; re-enqueue each so the move converges
            // across peers. Runs after the delete's savepoint released, in the
            // batch transaction, so it commits atomically with the apply.
            try Self.propagateListDeleteRehome(
              db, taskIds: rehomeCandidates, hlc: hlc, deviceId: deviceId)
            // If this upsert produced a merged row that diverges from the envelope
            // — an absence-preserved child collection (attendees / day-scoped
            // children) or a per-device list_id fallback rehome — re-emit a
            // fresh-HLC snapshot so peers that only saw the original envelope
            // converge.
            try Self.reemitIfMergedRowDiverged(
              db, envelope: envelope, hlc: hlc, deviceId: deviceId)
          case .upsertRejectedByRetention:
            try PendingInboxDrain.clearQuarantineThroughResolvedEnvelope(
              db, entityType: envelope.entityType.asString,
              entityID: envelope.entityId, version: envelope.version.description)
            if let replay = try FutureRecordHold.reconcileTerminalEnvelope(
              db, envelope: envelope, outcome: outcome)
            {
              futureLocalIntentReplays.append(replay)
            }
            // The applier already persisted account-scoped physical-delete work
            // and removed every local full-content copy in this transaction.
            retentionRejected += 1
            changedKinds.insert(envelope.entityType)
            skipped += 1
          case .repairRequired(let obligation):
            try PendingInboxDrain.clearQuarantineThroughResolvedEnvelope(
              db, entityType: envelope.entityType.asString,
              entityID: envelope.entityId, version: envelope.version.description)
            if let replay = try FutureRecordHold.reconcileTerminalEnvelope(
              db, envelope: envelope, outcome: outcome)
            {
              futureLocalIntentReplays.append(replay)
            }
            // The permanent inbox invariant is local, but merely ignoring a
            // peer's delete would leave that delete as the current CloudKit
            // record and poison every later authoritative snapshot. Replace it
            // with a dominating canonical upsert before this transaction can
            // commit and before the transport advances its checkpoint.
            // Fulfill after every ordinary apply/rehome/re-emit in this page. A
            // repair may need to dominate a far-future floor; entering its
            // detached lane here would timestamp unrelated later mutations at the
            // repair's clock.
            try Self.coalesceApplyRepair(
              obligation, kind: envelope.entityType,
              into: &pendingRepairObligations)
            skipped += 1
          case .skipped:
            try PendingInboxDrain.clearQuarantineThroughResolvedEnvelope(
              db, entityType: envelope.entityType.asString,
              entityID: envelope.entityId, version: envelope.version.description)
            if let replay = try FutureRecordHold.reconcileTerminalEnvelope(
              db, envelope: envelope, outcome: outcome)
            {
              futureLocalIntentReplays.append(replay)
            }
            skipped += 1
          case .deferred(let reason):
            do {
              try PendingInboxDrain.enqueueDeferred(db, envelope: envelope, reason: reason)
              deferred += 1
            } catch let enqueueError as EnqueueError {
              // Deterministic single-record poison: drop/log the envelope so the
              // CloudKit token can still advance. Transient DB errors are not
              // `EnqueueError` and still abort the batch for retry.
              if let cloudRecordName {
                resolvedCloudRecordNames.remove(cloudRecordName)
                corruptCloudRecordNames.insert(cloudRecordName)
              }
              invalid += 1
              ErrorLog.appendBestEffort(
                db, source: "sync.apply.inbound_invalid",
                message:
                  "dropping inbound envelope \(envelope.entityType.asString)/\(envelope.entityId) "
                  + "version \(envelope.version.description): pending-inbox enqueue rejected payload: "
                  + "\(enqueueError)",
                details: nil, level: "error")
            }
          case .remapped(_, let toEntityId):
            try PendingInboxDrain.clearQuarantineThroughResolvedEnvelope(
              db, entityType: envelope.entityType.asString,
              entityID: envelope.entityId, version: envelope.version.description)
            if let replay = try FutureRecordHold.reconcileTerminalEnvelope(
              db, envelope: envelope, outcome: outcome)
            {
              futureLocalIntentReplays.append(replay)
            }
            remapped += 1
            changedKinds.insert(envelope.entityType)
            // A redirect-remapped habit upsert that landed on (and changed) the merge
            // WINNER produces a merged winner state a non-merging peer never replicates
            // (the archive-interleaving non-confluence). Re-emit the winner's snapshot
            // at a fresh HLC so it converges. Every other remap redirects to a merge
            // winner whose own envelope drives convergence, so
            // `remappedMergeWinnerReemitTarget` returns nil and nothing re-emits.
            if let target = try AbsencePreserveReemit.remappedMergeWinnerReemitTarget(
              db, envelope: envelope, toEntityId: toEntityId)
            {
              try Self.propagateAbsencePreserveReemit(
                db, target: target, hlc: hlc, deviceId: deviceId)
            }
          }
        }
        let summary = try PendingInboxDrain.drainPendingInbox(db, registry: Self.inboundRegistry)
        futureLocalIntentReplays.append(contentsOf: summary.futureLocalIntentReplays)
        // Drain-replayed list deletes need the same HLC-minted rehome propagation
        // as direct applies; `reenqueueRehomed` re-checks each task still exists.
        try Self.propagateListDeleteRehome(
          db, taskIds: summary.listDeleteRehomedTaskIds, hlc: hlc, deviceId: deviceId)
        // SYNC-MED-2: re-emit merged snapshots for entities a replayed drain upsert
        // preserved absent child collections for, mirroring the direct-loop re-emit.
        for target in summary.absenceReemitTargets {
          try Self.propagateAbsencePreserveReemit(
            db, target: target, hlc: hlc, deviceId: deviceId)
        }
        for obligation in summary.repairObligations {
          let kind: EntityKind
          switch obligation {
          case .reassertRequiredInbox:
            kind = .list
          case .reassertRequiredTimezone:
            kind = .preference
          case .reassertCalendarSeriesCutover:
            kind = .calendarSeriesCutover
          case .propagateCalendarCleanup(let targets, _):
            kind = targets.first?.entityType ?? .calendarEvent
          case .propagateTaskRollover:
            kind = .task
          case .resolveEqualVersionCollision(let contender, _):
            kind = contender.entityType
          }
          try Self.coalesceApplyRepair(
            obligation, kind: kind, into: &pendingRepairObligations)
        }
        for pending in pendingRepairObligations {
          try ApplyRepair.fulfill(
            db, obligation: pending.obligation,
            mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
            deviceId: deviceId)
          repaired += 1
          changedKinds.insert(pending.kind)
          changedKinds.formUnion(pending.obligation.affectedEntityTypes)
        }
        let replayChangedKinds = try FutureRecordHold.fulfillLocalIntentReplays(
          db, replays: futureLocalIntentReplays, registry: Self.inboundRegistry,
          mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
          deviceId: deviceId)
        repaired += futureLocalIntentReplays.count
        changedKinds.formUnion(replayChangedKinds)
        changedKinds.formUnion(summary.replayedEntityTypes)
        if let outboundReconciliation {
          let collisionResolution = try Self.resolveOutboundCollisions(
            db, collisions: outboundReconciliation.collisions,
            hlc: hlc, deviceId: deviceId)
          repaired += collisionResolution.changedKinds.count
          changedKinds.formUnion(collisionResolution.changedKinds)
          reconciledCollisionOutboxIds.formUnion(
            collisionResolution.reconciledOutboxIds)
        }
        // The product timezone and each anchored reminder are independent
        // records. Reconcile only after the whole page, deferred replays,
        // apply repairs, and push-collision winners have settled, so record
        // ordering cannot leave a late old-zone reminder behind. Any repaired
        // reminder is re-stamped and enqueued before this transaction (and the
        // CloudKit checkpoint) can commit.
        let timezoneReminderRepairs = try Self.reconcileTaskReminderTimezoneAnchorsAfterInbound(
          db, service: self, deviceId: deviceId, hlc: hlc)
        if timezoneReminderRepairs > 0 {
          repaired += timezoneReminderRepairs
          changedKinds.insert(.taskReminder)
        }
        if summary.retentionRejected > 0 {
          changedKinds.insert(.aiChangelog)
        }
        // Best-effort retention sweep, in the sync runtime's finalizer order. A GC
        // failure is logged and never aborts the apply of real inbound data. The
        // emit hook propagates changelog prunes to the sync
        // layer (delete envelope + tombstone) so the shared CloudKit zone stays
        // bounded and peers converge on the prune instead of re-hydrating it — the
        // same session clock and device identity the convergence re-emits above use.
        let auditCountBeforeGC =
          try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
        SyncRetention.runPostApplyGC(db, syncedAt: syncedAt)
        let auditCountAfterGC =
          try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
        let auditPrunedByGC = auditCountAfterGC < auditCountBeforeGC
        let canonicalStateChanged = [
          applied > 0,
          remapped > 0,
          summary.replayed > 0,
          summary.retentionRejected > 0,
          retentionRejected > 0,
          repaired > 0,
          physicalDeletionChangedCanonicalState,
          auditPrunedByGC,
        ].contains(true)
        // The sequence is the cross-surface canonical-data invalidation witness,
        // not merely a local-write counter. Bump once for a mutating inbound page
        // (including replay/repair/retention removal), never for an empty,
        // duplicate, deferred-only, invalid-only, or LWW-skipped page.
        if canonicalStateChanged {
          try LocalChangeSeq.bump(db)
          Overview.invalidateStreakCache(db)
        }
        try transactionClock.persistHighWaters(db)
        if !cloudReceipts.isEmpty {
          guard let cloudReceiptAccountIdentifier else {
            throw TombstoneConfirmationError.accountBoundaryMismatch
          }
          try Self.consumeInboundCloudReceipts(
            db, accountIdentifier: cloudReceiptAccountIdentifier,
            receipts: cloudReceipts)
        }
        if let outboundReconciliation {
          // The transport has already performed its final generation/account
          // boundary check. Consume every local consequence of those exact
          // results under this same BEGIN IMMEDIATE transaction.
          try Self.deferUnknownTypeRecords(
            db, raws: outboundReconciliation.deferredUnknownTypeRecords)
          if !outboundReconciliation.cloudReceipts.isEmpty
            || !outboundReconciliation.serverWinnerCloudReceipts.isEmpty
          {
            guard let accountIdentifier = outboundReconciliation.accountIdentifier else {
              throw TombstoneConfirmationError.accountBoundaryMismatch
            }
            try Self.consumeInboundCloudReceipts(
              db, accountIdentifier: accountIdentifier,
              receipts: outboundReconciliation.serverWinnerCloudReceipts)
            try Self.consumeOutboundCloudReceipts(
              db, accountIdentifier: accountIdentifier,
              receipts: outboundReconciliation.cloudReceipts)
          }
          let reconciledAt = SyncTimestampFormat.syncTimestampNow()
          for failure in outboundReconciliation.failures {
            try Self.recordOutboundFailure(db, failure: failure, retriedAt: reconciledAt)
          }
          try Self.markOutboundSynced(
            db, outboxIds: outboundReconciliation.confirmedOutboxIds,
            syncedAt: reconciledAt)
        }
        let effectiveDeferredUnknownTypeRecords = deferredUnknownTypeRecords.filter { raw in
          !deletedCloudRecordNames.contains(
            SyncRecordName.opaque(entityType: raw.entityType, entityId: raw.entityId))
        }
        try Self.deferUnknownTypeRecords(db, raws: effectiveDeferredUnknownTypeRecords)
        if traversalCommit != nil {
          for raw in effectiveDeferredUnknownTypeRecords {
            resolvedCloudRecordNames.insert(
              SyncRecordName.opaque(entityType: raw.entityType, entityId: raw.entityId))
          }
        }
        if let traversalCommit {
          var observation = inboundPageObservation ?? CloudInboundPageObservation()
          observation.resolvedRecordNames = Array(resolvedCloudRecordNames)
          observation.corruptRecordNames = Array(corruptCloudRecordNames)
          try CloudInboundCompleteness.reconcilePage(
            db, boundary: traversalCommit.boundary, observation: observation)
        }
        try Self.commitCloudTraversalPageIfPresent(db, request: traversalCommit)
        if physicalDeletionRequiresCompleteInventory, let traversalCommit {
          try Self.beginInventorySnapshotAfterPhysicalDeletion(
            db, boundary: traversalCommit.boundary)
        }
        let parkedFutureCount =
          effectiveDeferredUnknownTypeRecords.count
          + (outboundReconciliation?.deferredUnknownTypeRecords.count ?? 0)
        return (
          applied, skipped, deferred, remapped, invalid, Int(summary.replayed), changedKinds,
          parkedFutureCount, reconciledCollisionOutboxIds
        )
      }
    }
    return InboundApplyReport(
      applied: counts.0, skipped: counts.1, deferred: counts.2, remapped: counts.3,
      drainReplayed: counts.5, undecodable: undecodable + counts.4,
      deferredUnknownType: counts.7,
      appliedEntityTypes: counts.6,
      reconciledCollisionOutboxIds: counts.8)
  }

}
