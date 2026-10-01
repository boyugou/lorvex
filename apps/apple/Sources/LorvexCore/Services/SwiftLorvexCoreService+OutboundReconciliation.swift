import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync

/// Outbound CloudKit-result bookkeeping and its atomic reconciliation funnel.
extension SwiftLorvexCoreService {
  struct OutboundCollisionResolution {
    var changedKinds: Set<EntityKind> = []
    var reconciledOutboxIds: Set<Int64> = []
  }

  enum OutboundCollisionReconciliationError: Error, Equatable {
    case mismatchedIdentity(outboxId: Int64)
    case mismatchedVersion(outboxId: Int64)
    case semanticKindMismatch(outboxId: Int64)
    case semanticApplyRejected(outboxId: Int64)
    case semanticTargetMissing(outboxId: Int64)
    case successorDidNotReplaceOutbox(outboxId: Int64)
  }

  public func markOutboundSynced(outboxIds: [Int64]) throws {
    if outboxIds.isEmpty { return }
    try write { db in
      try Self.markOutboundSynced(
        db, outboxIds: outboxIds, syncedAt: SyncTimestampFormat.syncTimestampNow())
    }
  }

  static func markOutboundSynced(
    _ db: Database, outboxIds: [Int64], syncedAt: String
  ) throws {
    if outboxIds.isEmpty { return }
    for outboxID in outboxIds {
      guard let entry = try Outbox.entry(db, id: outboxID) else { continue }
      let envelope = entry.envelope
      // A confirmed local write replaced the same CloudKit slot with a valid
      // envelope. It resolves any quarantined predecessor it dominates even if
      // the replacement is not echoed back through the incremental fetch.
      try PendingInboxDrain.clearQuarantineThroughResolvedEnvelope(
        db, entityType: envelope.entityType.asString,
        entityID: envelope.entityId, version: envelope.version.description)
    }
    try Outbox.markManySynced(db, outboxIds: outboxIds, syncedAt: syncedAt)
  }

  public func recordOutboundFailure(
    outboxId: Int64, error: String, kind: OutboundFailureKind
  ) throws {
    try write { db in
      try Self.recordOutboundFailure(
        db, failure: OutboundFailureRecord(outboxId: outboxId, error: error, kind: kind),
        retriedAt: SyncTimestampFormat.syncTimestampNow())
    }
  }

  static func recordOutboundFailure(
    _ db: Database, failure: OutboundFailureRecord, retriedAt: String
  ) throws {
    if failure.kind == .transient {
      // A transient transport outage affects every pending row identically;
      // retain diagnostics without advancing the retry budget.
      try Outbox.recordTransientFailure(
        db, outboxId: failure.outboxId, retriedAt: retriedAt, error: failure.error)
      return
    }
    // Same-error fast-forward is valid only for a per-record rejection. A
    // wholesale error still advances linearly, but cannot pause the whole queue
    // after three identical transport failures.
    let outcome = try Outbox.recordRetry(
      db, outboxId: failure.outboxId, retriedAt: retriedAt, error: failure.error,
      escalateOnRepeatedError: failure.kind == .perRecord)
    if outcome.exhaustedNow {
      ErrorLog.appendBestEffort(
        db, source: "sync.outbox.retry_wait",
        message:
          "outbox row \(failure.outboxId) entered retry wait after "
          + "\(outcome.newRetryCount) failed pushes; next_retry_at="
          + "\(outcome.nextRetryAt ?? "unknown"): \(failure.error)",
        details: nil, level: "error")
    }
  }

  public func deferUnknownTypeRecords(_ raws: [RawEnvelopeFields]) throws {
    if raws.isEmpty { return }
    try write { db in try Self.deferUnknownTypeRecords(db, raws: raws) }
  }

  static func deferUnknownTypeRecords(
    _ db: Database, raws: [RawEnvelopeFields]
  ) throws {
    // HOLD semantics: timestamp refresh on re-delivery, no attempt bump; future
    // builds drain understood records and the horizon GC sheds the rest.
    for raw in raws {
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: raw)
    }
  }

  /// Resolve transport-classified slot collisions under the same SQLite
  /// transaction that later consumes failures and confirmations. A missing old
  /// id is a stale callback after coalescing and is ignored; a matching id is a
  /// capability for exactly one local envelope, never merely an entity name.
  ///
  /// Each collision runs in its own savepoint. One that cannot be reconciled
  /// is rolled back alone and recorded as a per-record failure of its outbox
  /// row, so the retry policy governs it and the rest of the batch commits.
  /// Database errors still abort the whole transaction.
  static func resolveOutboundCollisions(
    _ db: Database, collisions: [OutboundCollisionRecord], hlc: HlcSession,
    deviceId: String
  ) throws -> OutboundCollisionResolution {
    var resolution = OutboundCollisionResolution()
    for collision in collisions {
      do {
        try db.inSavepoint {
          try resolveOutboundCollision(
            db, collision: collision, hlc: hlc, deviceId: deviceId, into: &resolution)
          return .commit
        }
      } catch let error as OutboundCollisionReconciliationError {
        try recordOutboundFailure(
          db,
          failure: OutboundFailureRecord(
            outboxId: collision.outboxId,
            error: "the collision with the server record could not be reconciled: \(error)",
            kind: .perRecord),
          retriedAt: SyncTimestampFormat.syncTimestampNow())
      }
    }
    return resolution
  }

  /// A collision whose server record is held (a future clock, or an apply
  /// deferred until a dependency arrives) leaves its outbox row unsynced. The
  /// row is backed off through the retry policy rather than re-sent at once
  /// against the same server version, which would collide again.
  private static func holdCollision(_ db: Database, outboxId: Int64) throws {
    try recordOutboundFailure(
      db,
      failure: OutboundFailureRecord(
        outboxId: outboxId, error: "waiting for a held server record to apply",
        kind: .perRecord),
      retriedAt: SyncTimestampFormat.syncTimestampNow())
  }

  private static func resolveOutboundCollision(
    _ db: Database, collision: OutboundCollisionRecord, hlc: HlcSession, deviceId: String,
    into resolution: inout OutboundCollisionResolution
  ) throws {
    guard let entry = try Outbox.entry(db, id: collision.outboxId), entry.syncedAt == nil else {
      return
    }
    let local = entry.envelope
    let contender: SyncEnvelope
    let additionalFloor: Hlc?
    switch collision.kind {
    case .corruptServerSlot(let serverVersionFloor):
      contender = local
      additionalFloor = serverVersionFloor
    case .semanticMerge(let expectedKind, let server):
      guard local.entityType == server.entityType,
        local.entityId == server.entityId,
        try SemanticPushConflictRouting.classify(client: local, server: server)
          == expectedKind
      else {
        throw OutboundCollisionReconciliationError.semanticKindMismatch(
          outboxId: collision.outboxId)
      }

      if let reason = FutureRecordHold.clockDeferralReason(for: server.version) {
        try PendingInboxDrain.enqueueDeferred(db, envelope: server, reason: reason)
        try holdCollision(db, outboxId: collision.outboxId)
        return
      }

      let serverForApply = try semanticServerEnvelopeForApply(
        local: local, server: server, kind: expectedKind)
      let applyResult = try Apply.applyEnvelope(
        db,
        registry: EntityApplierRegistry(
          appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: serverForApply)
      switch applyResult {
      case .applied, .skipped, .remapped:
        break
      case .repairRequired(let obligation):
        try ApplyRepair.fulfill(
          db, obligation: obligation,
          mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
          deviceId: deviceId)
        resolution.changedKinds.formUnion(obligation.affectedEntityTypes)
      case .deferred(let reason):
        try PendingInboxDrain.enqueueDeferred(db, envelope: server, reason: reason)
        try holdCollision(db, outboxId: collision.outboxId)
        return
      default:
        throw OutboundCollisionReconciliationError.semanticApplyRejected(
          outboxId: collision.outboxId)
      }

      let contenderFloor = max(local.version, server.version)
      if try Outbox.entry(db, id: collision.outboxId) != nil {
        if expectedKind == .entityRedirect {
          try EntityRedirect.enqueueStrictSuccessor(
            db, wireEntityId: local.entityId, additionalFloor: contenderFloor,
            mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
            deviceId: deviceId)
        } else {
          let emission = try ConvergenceEmitter.enqueueCurrentSnapshot(
            db, entityType: local.entityType.asString, entityId: local.entityId,
            mintVersion: { storedFloor in
              hlc.nextVersionString(
                dominating: storedFloor.map { max($0, contenderFloor) } ?? contenderFloor)
            },
            deviceId: deviceId)
          guard emission == .enqueued else {
            throw OutboundCollisionReconciliationError.semanticTargetMissing(
              outboxId: collision.outboxId)
          }
        }
      }
      try requireStrictSuccessor(
        db, replacing: collision.outboxId, local: local, floor: contenderFloor)
      resolution.changedKinds.formUnion(
        try SyncMutationImpact.affectedEntityTypes(for: local))
      resolution.reconciledOutboxIds.insert(collision.outboxId)
      return

    case .entityRedirectDelete(let server):
      guard local.entityType == .entityRedirect, local.operation == .upsert,
        server.entityType == .entityRedirect, server.operation == .delete,
        local.entityId == server.entityId
      else {
        throw OutboundCollisionReconciliationError.semanticKindMismatch(
          outboxId: collision.outboxId)
      }
      if let reason = FutureRecordHold.clockDeferralReason(for: server.version) {
        try PendingInboxDrain.enqueueDeferred(db, envelope: server, reason: reason)
        try holdCollision(db, outboxId: collision.outboxId)
        return
      }
      let contenderFloor = max(local.version, server.version)
      try EntityRedirect.enqueueStrictSuccessor(
        db, wireEntityId: local.entityId, additionalFloor: contenderFloor,
        mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
        deviceId: deviceId)
      try requireStrictSuccessor(
        db, replacing: collision.outboxId, local: local, floor: contenderFloor)
      resolution.changedKinds.insert(.entityRedirect)
      resolution.reconciledOutboxIds.insert(collision.outboxId)
      return
    case .equalVersion(let server):
      guard local.entityType == server.entityType, local.entityId == server.entityId else {
        throw OutboundCollisionReconciliationError.mismatchedIdentity(
          outboxId: collision.outboxId)
      }
      guard local.version == server.version else {
        throw OutboundCollisionReconciliationError.mismatchedVersion(
          outboxId: collision.outboxId)
      }
      if try SyncMutationSemantics.isExactSemanticReplay(local, server) {
        try Self.markOutboundSynced(
          db, outboxIds: [collision.outboxId],
          syncedAt: SyncTimestampFormat.syncTimestampNow())
        resolution.reconciledOutboxIds.insert(collision.outboxId)
        return
      }
      contender = try SyncMutationSemantics.deterministicWinner(local, server)
      additionalFloor = nil
    }

    try ApplyRepair.fulfill(
      db,
      obligation: .resolveEqualVersionCollision(
        contender: contender, additionalFloor: additionalFloor),
      mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
      deviceId: deviceId)
    if let old = try Outbox.entry(db, id: collision.outboxId), old.syncedAt == nil {
      throw OutboundCollisionReconciliationError.successorDidNotReplaceOutbox(
        outboxId: collision.outboxId)
    }
    resolution.changedKinds.insert(local.entityType)
    resolution.reconciledOutboxIds.insert(collision.outboxId)
  }

  private static func requireStrictSuccessor(
    _ db: Database, replacing oldOutboxId: Int64,
    local: SyncEnvelope, floor: Hlc
  ) throws {
    if let old = try Outbox.entry(db, id: oldOutboxId), old.syncedAt == nil {
      throw OutboundCollisionReconciliationError.successorDidNotReplaceOutbox(
        outboxId: oldOutboxId)
    }
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT id, version, disposition
          FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [local.entityType.asString, local.entityId]),
      (row["id"] as Int64) != oldOutboxId,
      (row["disposition"] as String?) == nil,
      try Hlc.parseCanonical(row["version"] as String) > floor
    else {
      throw OutboundCollisionReconciliationError.successorDidNotReplaceOutbox(
        outboxId: oldOutboxId)
    }
  }

  /// A one-version-ahead client can carry fields this runtime only preserves in
  /// payload shadow while its current fields are still governed by typed
  /// registers. When an older outer-version server snapshot wins one of those
  /// current registers, applying it verbatim would precede the shadow base and
  /// violate shadow provenance. Raise only the server snapshot's grouped-row
  /// high-water to the client contender before Apply; the independent register
  /// clocks and values remain unchanged, so Apply still computes the semantic
  /// join. ConvergenceEmitter then authors the strict successor and recomposes
  /// the client's unknown fields from shadow.
  private static func semanticServerEnvelopeForApply(
    local: SyncEnvelope, server: SyncEnvelope, kind: SemanticPushConflictKind
  ) throws -> SyncEnvelope {
    let clientAcceptance = Capability.checkEnvelopeVersion(
      envelopePayloadVersion: local.payloadSchemaVersion,
      localMaxVersion: LorvexVersion.payloadSchemaVersion)
    guard clientAcceptance == .parseForwardCompat,
      server.payloadSchemaVersion <= LorvexVersion.payloadSchemaVersion,
      kind == .taskRegisters || kind == .calendarBaseRegisters
        || kind == .calendarSeriesCutover,
      local.version > server.version
    else { return server }

    return try SyncMutationSemantics.restamp(
      server, version: local.version, deviceId: server.deviceId)
  }

  public func reconcileOutbound(
    _ request: OutboundReconciliationRequest
  ) throws -> OutboundReconciliationReport {
    // Reuse the inbound transaction body instead of opening four independent
    // transactions. A local error at any stage leaves the conflict winner
    // unapplied and every outbox row in its pre-attempt state.
    let inbound = try withStorageCutoverRetry {
      try self.applyInboundAttempt(
        request.serverWinnerEnvelopes, undecodable: 0,
        outboundReconciliation: request)
    }
    return OutboundReconciliationReport(
      inbound: inbound,
      reconciledCollisionOutboxIds: inbound.reconciledCollisionOutboxIds)
  }
}
