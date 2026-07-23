import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Permanent same-type identity aliases produced by deterministic dedup merges.
///
/// A redirect is not a deletion. `sync_tombstones` retains the loser's ordinary
/// LWW death barrier, while this table permanently records where stale writes to
/// that identity belong. Redirects are absorbing: competing targets join to the
/// lexicographically smallest terminal id and a corrective HLC is emitted when
/// that join differs from the incoming record.
public enum EntityRedirect {
  public enum ReassertionOutcome: Sendable, Equatable {
    case enqueued
    case alreadyPending
  }

  public struct Record: Sendable, Equatable {
    public var sourceType: EntityKind
    public var sourceId: String
    public var targetId: String
    public var version: String
    public var createdAt: String
  }

  struct UpsertOutcome: Sendable, Equatable {
    var record: Record
    var differsFromIncoming: Bool
    var compressionRoots: [String]
    /// When two aliases for the same source name different terminal targets,
    /// their components must be unioned as well as rewriting the source row.
    /// This is the losing (larger) terminal that must become an alias of
    /// `record.targetId`; nil when both inputs already resolve to one terminal.
    var displacedTerminalId: String?
  }

  struct Payload: Sendable, Equatable {
    var sourceType: EntityKind
    var sourceId: String
    var targetId: String
    var version: String
  }

  /// The independent wire identity for a redirect. The payload carries the
  /// source tuple explicitly and inbound apply verifies this digest, so a domain
  /// record and its alias can never share a CloudKit record namespace.
  public static func wireEntityId(sourceType: EntityKind, sourceId: String) -> String {
    SyncRecordName.opaque(entityType: sourceType.asString, entityId: sourceId)
  }

  public static func get(
    _ db: Database, sourceType: String, sourceId: String
  ) throws -> Record? {
    return try Row.fetchOne(
      db,
      sql: """
        SELECT source_type, source_id, target_id, version, created_at
        FROM sync_entity_redirects
        WHERE source_type = ? AND source_id = ?
        """,
      arguments: [sourceType, sourceId]
    ).map(record(from:))
  }

  /// Resolves the opaque CloudKit identity back to its permanent local alias.
  /// Redirect wire ids are digests rather than reversible encodings, so the rare
  /// physical-deletion recovery path performs a deterministic table scan.
  /// More than one match is treated as corruption instead of choosing an alias.
  public static func get(
    _ db: Database, wireEntityId: String
  ) throws -> Record? {
    var match: Record?
    for row in try Row.fetchAll(
      db,
      sql: """
        SELECT source_type, source_id, target_id, version, created_at
        FROM sync_entity_redirects
        ORDER BY source_type, source_id
        """)
    {
      let candidate = try record(from: row)
      guard self.wireEntityId(
        sourceType: candidate.sourceType, sourceId: candidate.sourceId) == wireEntityId
      else { continue }
      guard match == nil else {
        throw ApplyError.invalidPayload(
          "multiple entity redirects share one opaque wire identity")
      }
      match = candidate
    }
    return match
  }

  /// Re-enqueues an existing permanent alias after CloudKit physically removed
  /// its record slot. The stored HLC is intentionally preserved: absence has no
  /// competing value to dominate, while minting a newer semantic version could
  /// incorrectly outrank a future-schema redirect that later reappears.
  public static func reassertCurrent(
    _ db: Database, wireEntityId: String, deviceId: String
  ) throws -> ReassertionOutcome {
    guard let record = try get(db, wireEntityId: wireEntityId) else {
      throw ApplyError.invalidPayload(
        "entity redirect recovery could not resolve its opaque wire identity")
    }
    let envelope = try makeEnvelope(record: record, deviceId: deviceId)
    do {
      if try Outbox.enqueueCoalesced(db, envelope) != nil { return .enqueued }
    } catch { throw ApplyError.lift(error) }

    // Equal-version coalescing is deliberately a no-op when the exact
    // obligation is already ready to emit. Treat only that fully canonical,
    // eligible row as success: a newer row or an adoption/future-record fence
    // must still abort the inbound page instead of being silently accepted.
    let alreadyReady = try Bool.fetchOne(
      db,
      sql: """
        SELECT EXISTS(
          SELECT 1 FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            AND operation = ? AND version = ?
            AND payload_schema_version = ? AND payload = ?
            AND disposition IS NULL AND retry_count < ?
        )
        """,
      arguments: [
        EntityName.entityRedirect, wireEntityId, SyncNaming.opUpsert,
        envelope.version.description, envelope.payloadSchemaVersion,
        envelope.payload, Outbox.maxRetries,
      ]) ?? false
    guard alreadyReady else {
      throw ApplyError.store(
        "entity redirect recovery did not establish an eligible canonical outbox row")
    }
    return .alreadyPending
  }

  /// Advance and enqueue the canonical redirect occupying `wireEntityId` above
  /// both its stored clock and an external conflict floor. Push reconciliation
  /// uses this after a competing redirect join, or after rejecting an invalid
  /// logical Delete, so the old outbox capability is replaced before CloudKit's
  /// change tag can be cached.
  public static func enqueueStrictSuccessor(
    _ db: Database, wireEntityId: String, additionalFloor: Hlc,
    mintVersion: (Hlc) -> String, deviceId: String
  ) throws {
    guard var record = try get(db, wireEntityId: wireEntityId) else {
      throw ApplyError.invalidPayload(
        "entity redirect conflict could not resolve its opaque wire identity")
    }
    let stored = try Hlc.parseCanonical(record.version)
    let floor = max(stored, additionalFloor)
    let minted = try Hlc.parseCanonical(mintVersion(floor))
    guard minted > floor else {
      throw ApplyError.invalidVersion(minted.description)
    }
    record.version = minted.description
    try db.execute(
      sql: """
        UPDATE sync_entity_redirects
        SET version = ?
        WHERE source_type = ? AND source_id = ?
        """,
      arguments: [record.version, record.sourceType.asString, record.sourceId])
    guard try enqueue(db, record: record, deviceId: deviceId) else {
      throw ApplyError.store(
        "entity redirect conflict did not enqueue its strict successor")
    }
  }

  private static func record(from row: Row) throws -> Record {
    let sourceType: String = row["source_type"]
    guard let kind = EntityKind.parse(sourceType) else {
      throw ApplyError.unknownEntityType(sourceType)
    }
    return Record(
      sourceType: kind, sourceId: row["source_id"], targetId: row["target_id"],
      version: row["version"], createdAt: row["created_at"])
  }

  /// Store the min-target join for one source. When competing targets differ,
  /// the stored version becomes the smallest canonical successor of both inputs;
  /// this makes the corrective alias dominate either stale CloudKit value in
  /// every arrival order.
  static func upsertJoined(
    _ db: Database, sourceType: EntityKind, sourceId: String, targetId rawTargetId: String,
    version incomingVersion: String, createdAt: String
  ) throws -> UpsertOutcome {
    try validateSourceAndTarget(
      sourceType: sourceType, sourceId: sourceId, targetId: rawTargetId)
    guard let incomingHlc = try? Hlc.parseCanonical(incomingVersion) else {
      throw ApplyError.invalidVersion(incomingVersion)
    }

    let targetChase = try ApplyRedirect.chaseRedirectChain(
      db, initialEntityType: sourceType.asString, initialEntityId: rawTargetId)
    guard targetChase.finalType == sourceType.asString else {
      throw ApplyError.invalidPayload("entity redirect must remain within one entity type")
    }
    let incomingTargetId = targetChase.finalId
    var compressionRoots = targetChase.hops.last.map { [$0.fromEntityId] } ?? []
    try validateSourceAndTarget(
      sourceType: sourceType, sourceId: sourceId, targetId: incomingTargetId)

    let existing = try get(db, sourceType: sourceType.asString, sourceId: sourceId)
    let targetId: String
    let storedVersion: Hlc
    var displacedTerminalId: String?
    if let existing {
      guard let existingHlc = try? Hlc.parseCanonical(existing.version) else {
        throw ApplyError.invalidVersion(existing.version)
      }
      let existingChase = try ApplyRedirect.chaseRedirectChain(
        db, initialEntityType: sourceType.asString, initialEntityId: existing.targetId)
      guard existingChase.finalType == sourceType.asString else {
        throw ApplyError.invalidPayload("stored entity redirect crossed entity types")
      }
      if let root = existingChase.hops.last?.fromEntityId {
        compressionRoots.append(root)
      }
      targetId = min(existingChase.finalId, incomingTargetId)
      if existingChase.finalId != incomingTargetId {
        displacedTerminalId = max(existingChase.finalId, incomingTargetId)
      }
      try validateSourceAndTarget(sourceType: sourceType, sourceId: sourceId, targetId: targetId)
      let floor = max(existingHlc, incomingHlc)
      if existing.targetId != targetId || incomingTargetId != targetId {
        storedVersion = try AggregateMergeEngine.mintMergeHlcAfter(
          floor, mergeSuffix: floor.deviceSuffix, context: "entity redirect target join")
        SyncHlcObserver.observeLocalEvent(storedVersion)
      } else {
        storedVersion = floor
      }
    } else {
      targetId = incomingTargetId
      storedVersion = incomingHlc
    }

    try db.execute(
      sql: """
        INSERT INTO sync_entity_redirects
            (source_type, source_id, target_id, version, created_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(source_type, source_id) DO UPDATE SET
            target_id = excluded.target_id,
            version = excluded.version,
            created_at = min(sync_entity_redirects.created_at, excluded.created_at)
        """,
      arguments: [
        sourceType.asString, sourceId, targetId, storedVersion.description, createdAt,
      ])

    guard
      let record = try get(
        db, sourceType: sourceType.asString, sourceId: sourceId)
    else {
      throw ApplyError.store("entity redirect disappeared after its atomic upsert")
    }
    return UpsertOutcome(
      record: record,
      differsFromIncoming: targetId != rawTargetId || storedVersion.description != incomingVersion,
      compressionRoots: Array(Set(compressionRoots)).sorted(),
      displacedTerminalId: displacedTerminalId)
  }

  /// Persist an alias and enqueue its canonical independent upsert. Aggregate
  /// merge producers call this inside the same savepoint that deletes the loser.
  @discardableResult
  static func upsertAndEnqueue(
    _ db: Database, sourceType: EntityKind, sourceId: String, targetId: String,
    version: String, createdAt: String, deviceId: String
  ) throws -> Record {
    let outcome = try upsertJoined(
      db, sourceType: sourceType, sourceId: sourceId, targetId: targetId,
      version: version, createdAt: createdAt)
    try PayloadShadow.mergeShadowIntoRedirect(
      db, fromEntityType: sourceType.asString, fromEntityID: sourceId,
      toEntityType: sourceType.asString, toEntityID: outcome.record.targetId)
    try enqueue(db, record: outcome.record, deviceId: deviceId)
    if let displacedTerminalId = outcome.displacedTerminalId {
      for terminalId in [outcome.record.targetId, displacedTerminalId] {
        let isKnown =
          try entityExists(db, kind: sourceType, entityId: terminalId)
          || Tombstone.getTombstone(
            db, entityType: sourceType.asString, entityId: terminalId) != nil
        guard isKnown else {
          throw ApplyError.store(
            "local entity redirect join is missing terminal state for "
              + "\(sourceType.asString):\(terminalId)")
        }
      }
      try reconcileDisplacedTerminal(
        db,
        registry: EntityApplierRegistry(
          appliers: EntityApplierRegistry.defaultEntityAppliers()),
        sourceType: sourceType, displacedId: displacedTerminalId,
        winnerId: outcome.record.targetId, redirectVersion: outcome.record.version,
        applyTs: createdAt)
    }
    try compressKnownPaths(
      db, sourceType: sourceType, sourceId: sourceId, outcome: outcome,
      createdAt: createdAt, deviceId: deviceId)
    return outcome.record
  }

  /// Apply one inbound absorbing redirect. A missing target defers durably. If
  /// both source and target are live, the source is merged through the same
  /// aggregate hooks that produced the alias, preserving content and children
  /// before the source death barrier is written.
  static func applyInbound(
    _ db: Database, registry: EntityApplierRegistry, envelope: SyncEnvelope, applyTs: String
  ) throws -> ApplyResult {
    guard envelope.operation == .upsert else {
      throw ApplyError.invalidOperation(
        entityType: EntityName.entityRedirect, operation: envelope.operation.asString)
    }
    let payload = try decodePayload(
      wireEntityId: envelope.entityId, payload: envelope.payload)
    guard payload.version == envelope.version.description else {
      throw ApplyError.invalidPayload("entity redirect payload version must equal envelope version")
    }

    let outcome = try upsertJoined(
      db, sourceType: payload.sourceType, sourceId: payload.sourceId,
      targetId: payload.targetId,
      version: envelope.version.description, createdAt: applyTs)
    let sourceType = outcome.record.sourceType
    let sourceId = outcome.record.sourceId
    let terminalTarget = outcome.record.targetId
    let targetIsLive = try entityExists(
      db, kind: sourceType, entityId: terminalTarget)
    let targetTombstone = try Tombstone.getTombstone(
      db, entityType: sourceType.asString, entityId: terminalTarget)
    guard targetIsLive || targetTombstone != nil else {
      return .deferred(
        reason: .missingDependency(entityType: sourceType, entityId: terminalTarget))
    }

    if let displacedTerminalId = outcome.displacedTerminalId {
      let displacedIsLive = try entityExists(
        db, kind: sourceType, entityId: displacedTerminalId)
      let displacedTombstone = try Tombstone.getTombstone(
        db, entityType: sourceType.asString, entityId: displacedTerminalId)
      guard displacedIsLive || displacedTombstone != nil else {
        return .deferred(
          reason: .missingDependency(
            entityType: sourceType, entityId: displacedTerminalId))
      }
      try reconcileDisplacedTerminal(
        db, registry: registry, sourceType: sourceType,
        displacedId: displacedTerminalId, winnerId: terminalTarget,
        redirectVersion: outcome.record.version, applyTs: applyTs)
    }

    let sourceIsLive = try entityExists(db, kind: sourceType, entityId: sourceId)
    var sourceDeathVersion = outcome.record.version
    let finalTargetIsLive = try entityExists(
      db, kind: sourceType, entityId: terminalTarget)
    let finalTargetTombstone = try Tombstone.getTombstone(
      db, entityType: sourceType.asString, entityId: terminalTarget)
    if finalTargetIsLive, sourceIsLive {
      try mergeLiveSource(
        db, kind: sourceType, sourceId: sourceId, targetId: terminalTarget,
        redirectVersion: outcome.record.version, applyTs: applyTs)
    } else if let finalTargetTombstone {
      sourceDeathVersion = try suppressAliasIntoDeletedTarget(
        db, registry: registry, sourceType: sourceType, sourceId: sourceId,
        sourceIsLive: sourceIsLive, targetId: terminalTarget,
        targetTombstone: finalTargetTombstone, aliasVersion: outcome.record.version,
        applyTs: applyTs)
    } else if finalTargetIsLive {
      // No live source remains to participate in the aggregate merge. Move any
      // source-addressed future-field snapshot only now, after all live-content
      // provenance decisions have finished. Moving it in `upsertJoined` would
      // hide a live source's shadow from the aggregate's P* selection and then
      // reap the relocated copy as if P* had no future fields.
      try PayloadShadow.mergeShadowIntoRedirect(
        db, fromEntityType: sourceType.asString, fromEntityID: sourceId,
        toEntityType: sourceType.asString, toEntityID: terminalTarget)
    }

    guard
      let finalRecord = try get(
        db, sourceType: sourceType.asString, sourceId: sourceId)
    else { throw ApplyError.store("entity redirect disappeared during inbound apply") }
    try Tombstone.createTombstone(
      db, entityType: sourceType.asString, entityId: sourceId,
      version: sourceDeathVersion, deletedAt: applyTs)

    let differsFromIncoming =
      finalRecord.targetId != payload.targetId
      || finalRecord.version != envelope.version.description
    if differsFromIncoming {
      let deviceId = try SyncCheckpoints.getOrCreateDeviceId(db)
      try enqueue(db, record: finalRecord, deviceId: deviceId)
    }
    try compressKnownPaths(
      db, sourceType: sourceType, sourceId: sourceId,
      outcome: UpsertOutcome(
        record: finalRecord, differsFromIncoming: differsFromIncoming,
        compressionRoots: outcome.compressionRoots,
        displacedTerminalId: nil),
      createdAt: applyTs, deviceId: nil)
    return .applied
  }

  /// Complete the union implied by competing aliases for one source. Merely
  /// changing `source -> oldTarget` into `source -> minTarget` is insufficient:
  /// the old target may already hold the source's content from an earlier merge.
  /// It must itself become a durable loser of the min target, otherwise two live
  /// aggregates survive and different arrival orders diverge.
  private static func reconcileDisplacedTerminal(
    _ db: Database, registry: EntityApplierRegistry, sourceType: EntityKind,
    displacedId: String, winnerId: String, redirectVersion: String, applyTs: String
  ) throws {
    let winnerIsLive = try entityExists(db, kind: sourceType, entityId: winnerId)
    let winnerTombstone = try Tombstone.getTombstone(
      db, entityType: sourceType.asString, entityId: winnerId)
    let displacedIsLive = try entityExists(
      db, kind: sourceType, entityId: displacedId)

    if winnerIsLive, displacedIsLive {
      try mergeLiveSource(
        db, kind: sourceType, sourceId: displacedId, targetId: winnerId,
        redirectVersion: redirectVersion, applyTs: applyTs)
      return
    }

    let deviceId = try SyncCheckpoints.getOrCreateDeviceId(db)
    let redirect = try upsertAndEnqueue(
      db, sourceType: sourceType, sourceId: displacedId, targetId: winnerId,
      version: redirectVersion, createdAt: applyTs, deviceId: deviceId)

    if let winnerTombstone {
      _ = try suppressAliasIntoDeletedTarget(
        db, registry: registry, sourceType: sourceType, sourceId: displacedId,
        sourceIsLive: displacedIsLive, targetId: winnerId,
        targetTombstone: winnerTombstone, aliasVersion: redirect.version,
        applyTs: applyTs)
      return
    }

    guard winnerIsLive else {
      throw ApplyError.store(
        "entity redirect target disappeared while joining competing aliases")
    }
    try Tombstone.createTombstone(
      db, entityType: sourceType.asString, entityId: displacedId,
      version: redirect.version, deletedAt: applyTs)
    let finalDeath = try Tombstone.getTombstone(
      db, entityType: sourceType.asString, entityId: displacedId)
    _ = try OutboxEnqueue.enqueueAliasSourceDelete(
      db, entityType: sourceType.asString, entityId: displacedId,
      version: finalDeath?.version ?? redirect.version, deviceId: deviceId)
  }

  private static func compressKnownPaths(
    _ db: Database, sourceType: EntityKind, sourceId: String,
    outcome: UpsertOutcome, createdAt: String, deviceId: String?
  ) throws {
    for root in outcome.compressionRoots where root != outcome.record.targetId {
      try compressPredecessors(
        db, sourceType: sourceType, through: root, to: outcome.record.targetId,
        floorVersion: outcome.record.version, createdAt: createdAt, deviceId: deviceId)
    }
    try compressPredecessors(
      db, sourceType: sourceType, through: sourceId, to: outcome.record.targetId,
      floorVersion: outcome.record.version, createdAt: createdAt, deviceId: deviceId)
  }

  /// Parse and validate the shared redirect payload shape. `ApplyFk` reuses this
  /// exact boundary so authoritative local-intent dependency closure cannot
  /// drift from inbound apply.
  static func decodePayload(wireEntityId: String, payload rawPayload: String) throws -> Payload {
    let object = try ApplyJSON.parseObject(rawPayload)
    let expectedKeys: Set<String> = ["source_type", "source_id", "target_id", "version"]
    guard Set(object.keys) == expectedKeys else {
      throw ApplyError.invalidPayload(
        "entity redirect payload must contain exactly source_type, source_id, target_id, version")
    }
    let sourceTypeRaw = try ApplyJSON.requiredStr(
      object, "source_type", entity: EntityName.entityRedirect)
    guard let sourceType = EntityKind.parse(sourceTypeRaw) else {
      throw ApplyError.unknownEntityType(sourceTypeRaw)
    }
    let sourceId = try ApplyJSON.requiredStr(
      object, "source_id", entity: EntityName.entityRedirect)
    let targetId = try ApplyJSON.requiredStr(
      object, "target_id", entity: EntityName.entityRedirect)
    let version = try ApplyJSON.requiredStr(
      object, "version", entity: EntityName.entityRedirect)
    try validateSourceAndTarget(
      sourceType: sourceType, sourceId: sourceId, targetId: targetId)
    guard wireEntityId == self.wireEntityId(sourceType: sourceType, sourceId: sourceId) else {
      throw ApplyError.invalidPayload("entity redirect wire identity does not match its source")
    }
    guard (try? Hlc.parseCanonical(version)) != nil else {
      throw ApplyError.invalidVersion(version)
    }
    return Payload(
      sourceType: sourceType, sourceId: sourceId, targetId: targetId, version: version)
  }

  /// A permanent alias whose target is already deleted represents the same
  /// deleted logical entity. Advance the target barrier when necessary so it
  /// dominates every pre-alias source write, delete any still-live source via
  /// its typed aggregate applier, then emit both corrective deletes.
  private static func suppressAliasIntoDeletedTarget(
    _ db: Database, registry: EntityApplierRegistry, sourceType: EntityKind,
    sourceId: String, sourceIsLive: Bool, targetId: String,
    targetTombstone: Tombstone.Record, aliasVersion: String, applyTs: String
  ) throws -> String {
    guard let aliasHlc = try? Hlc.parseCanonical(aliasVersion),
      let targetDeath = try? Hlc.parseCanonical(targetTombstone.version)
    else { throw ApplyError.invalidVersion("entity redirect deletion barrier is noncanonical") }
    var floor = max(aliasHlc, targetDeath)
    var establishedDeath = targetDeath
    if let sourceTombstone = try Tombstone.getTombstone(
      db, entityType: sourceType.asString, entityId: sourceId)
    {
      guard let sourceDeath = try? Hlc.parseCanonical(sourceTombstone.version)
      else { throw ApplyError.invalidVersion(sourceTombstone.version) }
      floor = max(floor, sourceDeath)
      establishedDeath = max(establishedDeath, sourceDeath)
    }
    if sourceIsLive,
      let sourceVersionRaw = try ApplyLww.getLocalVersion(
        db, entityType: sourceType.asString, entityId: sourceId)
    {
      guard let sourceVersion = try? Hlc.parseCanonical(sourceVersionRaw)
      else { throw ApplyError.invalidVersion(sourceVersionRaw) }
      floor = max(floor, sourceVersion)
    }
    let barrier: Hlc
    if establishedDeath > aliasHlc, !sourceIsLive {
      barrier = establishedDeath
    } else {
      barrier = try AggregateMergeEngine.mintMergeHlcAfter(
        floor, mergeSuffix: floor.deviceSuffix,
        context: "entity redirect into deleted target")
      SyncHlcObserver.observeLocalEvent(barrier)
    }
    let deviceId = try SyncCheckpoints.getOrCreateDeviceId(db)

    if sourceIsLive {
      let deletePayload = try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(barrier.description)]))
      let deleteEnvelope = SyncEnvelope(
        entityType: sourceType, entityId: sourceId, operation: .delete,
        version: barrier, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: deletePayload, deviceId: deviceId)
      let deleteOutcome = try ApplyDispatch.dispatch(
        db, registry: registry, envelope: deleteEnvelope,
        tieBreak: .rejectEqual, applyTs: applyTs)
      guard deleteOutcome == .applied else {
        throw ApplyError.store(
          "entity redirect could not suppress a live source whose target is deleted")
      }
    }

    if barrier > targetDeath {
      try OutboxEnqueue.enqueuePayloadDelete(
        db, entityType: sourceType.asString, entityId: targetId,
        payload: .object(["version": .string(targetTombstone.version)]),
        context: OutboxWriteContext(version: barrier.description, deviceId: deviceId))
    }
    try Tombstone.createTombstone(
      db, entityType: sourceType.asString, entityId: sourceId,
      version: barrier.description, deletedAt: applyTs)
    _ = try OutboxEnqueue.enqueueAliasSourceDelete(
      db, entityType: sourceType.asString, entityId: sourceId,
      version: barrier.description, deviceId: deviceId)
    return barrier.description
  }

  /// Rewrite every durable predecessor of `through` directly to the terminal
  /// target. Each changed alias receives an HLC that dominates both its prior
  /// value and the topology-changing alias, then emits a corrective wire upsert.
  ///
  /// The descending-id invariant makes the graph acyclic. The explicit visited
  /// set still fails closed if a corrupt database violates that invariant, and
  /// the row-count budget bounds work even if a hostile database is supplied.
  private static func compressPredecessors(
    _ db: Database, sourceType: EntityKind, through sourceId: String, to terminalId: String,
    floorVersion: String, createdAt: String, deviceId suppliedDeviceId: String?
  ) throws {
    guard sourceId != terminalId else { return }
    guard let initialFloor = try? Hlc.parseCanonical(floorVersion)
    else { throw ApplyError.invalidVersion(floorVersion) }

    let rowBudget =
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM sync_entity_redirects WHERE source_type = ?",
        arguments: [sourceType.asString]) ?? 0
    var frontier = [sourceId]
    var visited = Set<String>()
    var processed = 0
    var deviceId = suppliedDeviceId

    while let node = frontier.popLast() {
      guard visited.insert(node).inserted else {
        throw ApplyError.entityRedirectCycle(
          entityType: sourceType.asString, entityId: node)
      }
      let predecessors = try Row.fetchAll(
        db,
        sql: """
          SELECT source_id, target_id, version, created_at
          FROM sync_entity_redirects
          WHERE source_type = ? AND target_id = ?
          ORDER BY source_id COLLATE BINARY
          """,
        arguments: [sourceType.asString, node]
      )
      for row in predecessors {
        processed += 1
        guard processed <= rowBudget else {
          throw ApplyError.entityRedirectCycle(
            entityType: sourceType.asString, entityId: row["source_id"])
        }
        let predecessorId: String = row["source_id"]
        frontier.append(predecessorId)

        let oldTargetId: String = row["target_id"]
        guard oldTargetId != terminalId else { continue }
        try validateSourceAndTarget(
          sourceType: sourceType, sourceId: predecessorId, targetId: terminalId)
        let oldVersionRaw: String = row["version"]
        guard let oldVersion = try? Hlc.parseCanonical(oldVersionRaw)
        else { throw ApplyError.invalidVersion(oldVersionRaw) }
        let floor = max(oldVersion, initialFloor)
        let correction = try AggregateMergeEngine.mintMergeHlcAfter(
          floor, mergeSuffix: floor.deviceSuffix,
          context: "entity redirect path compression")
        SyncHlcObserver.observeLocalEvent(correction)
        let storedCreatedAt: String = row["created_at"]
        let canonicalCreatedAt = min(storedCreatedAt, createdAt)
        try db.execute(
          sql: """
            UPDATE sync_entity_redirects
            SET target_id = ?, version = ?, created_at = ?
            WHERE source_type = ? AND source_id = ?
            """,
          arguments: [
            terminalId, correction.description, canonicalCreatedAt,
            sourceType.asString, predecessorId,
          ])
        try PayloadShadow.mergeShadowIntoRedirect(
          db, fromEntityType: sourceType.asString, fromEntityID: predecessorId,
          toEntityType: sourceType.asString, toEntityID: terminalId)
        if deviceId == nil {
          deviceId = try SyncCheckpoints.getOrCreateDeviceId(db)
        }
        guard let correctionDeviceId = deviceId else {
          throw ApplyError.store("entity redirect correction device id was not created")
        }
        try enqueue(
          db,
          record: Record(
            sourceType: sourceType, sourceId: predecessorId, targetId: terminalId,
            version: correction.description, createdAt: canonicalCreatedAt),
          deviceId: correctionDeviceId)
      }
    }
  }

  @discardableResult
  static func enqueue(_ db: Database, record: Record, deviceId: String) throws -> Bool {
    let envelope = try makeEnvelope(record: record, deviceId: deviceId)
    do {
      return try Outbox.enqueueCoalesced(db, envelope) != nil
    } catch { throw ApplyError.lift(error) }
  }

  static func makeEnvelope(record: Record, deviceId: String) throws -> SyncEnvelope {
    try validateSourceAndTarget(
      sourceType: record.sourceType, sourceId: record.sourceId, targetId: record.targetId)
    guard let version = try? Hlc.parseCanonical(record.version) else {
      throw ApplyError.invalidVersion(record.version)
    }
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "source_id": .string(record.sourceId),
        "source_type": .string(record.sourceType.asString),
        "target_id": .string(record.targetId),
        "version": .string(record.version),
      ]))
    return SyncEnvelope(
      entityType: .entityRedirect,
      entityId: wireEntityId(sourceType: record.sourceType, sourceId: record.sourceId),
      operation: .upsert, version: version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private static func validateSourceAndTarget(
    sourceType: EntityKind, sourceId: String, targetId: String
  ) throws {
    switch sourceType {
    case .tag, .habit, .memory, .habitReminderPolicy:
      break
    default:
      throw ApplyError.invalidPayload(
        "entity type \(sourceType.asString) cannot participate in identity redirects")
    }
    guard sourceId != targetId else {
      throw ApplyError.entityRedirectCycle(
        entityType: sourceType.asString, entityId: sourceId)
    }
    guard targetId < sourceId else {
      throw ApplyError.invalidPayload(
        "entity redirect target must be lexicographically smaller than its source")
    }
    for id in [sourceId, targetId] {
      if case .failure(let error) = SyncEntityId.validateForKind(sourceType, id) {
        throw ApplyError.invalidPayload(
          "entity redirect \(sourceType.asString) identity is noncanonical: \(error)")
      }
    }
  }

  static func entityExists(
    _ db: Database, kind: EntityKind, entityId: String
  ) throws -> Bool {
    if let (table, pk) = kind.tablePk {
      ValidationSQL.assertSafeSQLIdentifier(table)
      ValidationSQL.assertSafeSQLIdentifier(pk)
      return try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM \(table) WHERE \(pk) = ?", arguments: [entityId]) == 1
    }
    guard kind.isEdge else { return false }
    let (left, right): (String, String)
    switch CompositeEdge.splitCompositeEdgeId(entityId) {
    case .success(let pair): (left, right) = pair
    case .failure: return false
    }
    let sql: String
    switch kind {
    case .taskTag:
      sql = "SELECT COUNT(*) FROM task_tags WHERE task_id = ? AND tag_id = ?"
    case .taskDependency:
      sql = "SELECT COUNT(*) FROM task_dependencies WHERE task_id = ? AND depends_on_task_id = ?"
    case .taskCalendarEventLink:
      sql =
        "SELECT COUNT(*) FROM task_calendar_event_links WHERE task_id = ? AND calendar_event_id = ?"
    case .habitCompletion:
      sql = "SELECT COUNT(*) FROM habit_completions WHERE habit_id = ? AND completed_date = ?"
    default:
      return false
    }
    return try Int.fetchOne(db, sql: sql, arguments: [left, right]) == 1
  }

  static func mergeLiveSource(
    _ db: Database, kind: EntityKind, sourceId: String, targetId: String,
    redirectVersion: String, applyTs: String
  ) throws {
    let rows: [(String, String)]
    if let (table, pk) = kind.tablePk {
      ValidationSQL.assertSafeSQLIdentifier(table)
      ValidationSQL.assertSafeSQLIdentifier(pk)
      rows = try Row.fetchAll(
        db,
        sql: "SELECT \(pk), version FROM \(table) WHERE \(pk) IN (?, ?) ORDER BY \(pk)",
        arguments: [sourceId, targetId]
      ).map { ($0[0], $0[1]) }
    } else {
      rows = []
    }
    guard rows.count == 2 else {
      throw ApplyError.invalidPayload(
        "entity redirect source is live but cannot be merged through a supported aggregate hook")
    }
    let merger: AggregateMergeEngine
    switch kind {
    case .tag: merger = ApplyTagMerge.merger
    case .habit: merger = ApplyHabitMerge.merger
    case .memory: merger = ApplyMemoryMerge.merger
    case .habitReminderPolicy: merger = ApplyHabitReminderPolicyMerge.merger
    default:
      throw ApplyError.invalidPayload(
        "entity redirect source type \(kind.asString) has no aggregate merge hook")
    }
    _ = try merger.mergeKnownDuplicate(
      db, rows: rows, triggeringVersion: redirectVersion, applyTs: applyTs,
      mode: .permanentAlias)
  }
}
