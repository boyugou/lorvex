import Foundation
import GRDB
import LorvexDomain

/// Durable evidence that the current build has not yet materialized every
/// CloudKit record it observed for an exact ready generation.
public struct CloudInboundCompletenessState: Sendable, Equatable {
  public let pendingRecordCount: Int
  public let corruptRecordCount: Int

  public init(pendingRecordCount: Int, corruptRecordCount: Int) {
    self.pendingRecordCount = pendingRecordCount
    self.corruptRecordCount = corruptRecordCount
  }

  public var isComplete: Bool {
    pendingRecordCount == 0 && corruptRecordCount == 0
  }
}

/// Canonical consequences of reconciling physically deleted CloudKit record
/// slots. The host uses this to invalidate affected surfaces, re-create
/// permanent invariant records, and schedule a durable complete-inventory pass
/// before changing relational aggregate roots.
public struct CloudPhysicalDeletionReassertion: Sendable, Hashable {
  public let entityType: EntityKind
  public let entityId: String

  public init(entityType: EntityKind, entityId: String) {
    self.entityType = entityType
    self.entityId = entityId
  }
}

public struct CloudPhysicalDeletionReconciliation: Sendable, Equatable {
  public var removedEntityTypes: Set<EntityKind>
  public var requiredReassertions: Set<CloudPhysicalDeletionReassertion>
  public var completeInventoryRequiredByEntityTypes: Set<EntityKind>

  public init(
    removedEntityTypes: Set<EntityKind> = [],
    requiredReassertions: Set<CloudPhysicalDeletionReassertion> = [],
    completeInventoryRequiredByEntityTypes: Set<EntityKind> = []
  ) {
    self.removedEntityTypes = removedEntityTypes
    self.requiredReassertions = requiredReassertions
    self.completeInventoryRequiredByEntityTypes = completeInventoryRequiredByEntityTypes
  }

  public var requiresCompleteInventory: Bool {
    !completeInventoryRequiredByEntityTypes.isEmpty
  }
}

/// Record-name observations attached to one transactionally committed
/// CloudKit traversal page. Core augments `resolvedRecordNames` with envelopes
/// it successfully validated and augments `corruptRecordNames` when a decoded
/// envelope still fails the canonical apply contract.
public struct CloudInboundPageObservation: Sendable, Equatable {
  public var resolvedRecordNames: [String]
  public var corruptRecordNames: [String]
  public var deletedRecordNames: [String]

  public init(
    resolvedRecordNames: [String] = [],
    corruptRecordNames: [String] = [],
    deletedRecordNames: [String] = []
  ) {
    self.resolvedRecordNames = resolvedRecordNames
    self.corruptRecordNames = corruptRecordNames
    self.deletedRecordNames = deletedRecordNames
  }
}

/// SQLite home for fail-closed inbound completeness debt.
public enum CloudInboundCompleteness {
  private static let maximumRecordNameBytes = 1_024

  private struct LiveIdentity: Hashable {
    let kind: EntityKind
    let entityID: String
  }

  public static func state(
    _ db: Database,
    boundary: CloudTraversalBoundary
  ) throws -> CloudInboundCompletenessState {
    let pending = try Int.fetchOne(
      db, sql: "SELECT COUNT(*) FROM sync_pending_inbox") ?? 0
    // An active authoritative session is durable inbound debt of its own. In
    // particular, incremental physical deletion of a relational root starts an
    // intent-preserving complete-inventory session after committing that page.
    // Counting it here prevents terminal drains/imports from declaring success
    // in the crash window before the snapshot has reconciled the graph.
    let activeSnapshot = try Int.fetchOne(
      db,
      sql: """
        SELECT COUNT(*)
        FROM sync_authoritative_snapshot
        WHERE account_identifier = ? AND zone_name = ?
          AND generation = ? AND generation_identifier = ? AND ready_witness = ?
        """,
      arguments: [
        boundary.accountIdentifier, boundary.zoneIdentifier, boundary.generation,
        boundary.generationIdentifier, boundary.readyWitness,
      ]) ?? 0
    let scopedCorrupt = try Int.fetchOne(
      db,
      sql: """
        SELECT COUNT(*)
        FROM sync_cloudkit_corrupt_record_fences
        WHERE account_identifier = ? AND zone_identifier = ?
          AND generation = ? AND generation_identifier = ? AND ready_witness = ?
        """,
      arguments: [
        boundary.accountIdentifier, boundary.zoneIdentifier, boundary.generation,
        boundary.generationIdentifier, boundary.readyWitness,
      ]) ?? 0
    // A retry-exhausted decoded envelope leaves the pending inbox but remains
    // unmaterialized. The global blocklist is canonical-database debt (like the
    // global pending inbox), while transport-decode corruption is scoped to an
    // exact CloudKit generation above. A valid replacement/outbound overwrite
    // clears dominated blocklist rows; an authoritative snapshot clears all.
    let quarantined = try PendingInboxDrain.quarantinedRecordCount(db)
    return CloudInboundCompletenessState(
      pendingRecordCount: pending + activeSnapshot,
      corruptRecordCount: scopedCorrupt + quarantined)
  }

  /// Apply a page's replacement/deletion/corruption observations in the same
  /// transaction that advances its CloudKit cursor. Deletion wins if a
  /// pathological page mentions the same record in more than one collection;
  /// otherwise corruption wins over a simultaneous resolved classification.
  public static func reconcilePage(
    _ db: Database,
    boundary: CloudTraversalBoundary,
    observation: CloudInboundPageObservation
  ) throws {
    let deleted = try validatedNames(observation.deletedRecordNames)
    let corrupt = try validatedNames(observation.corruptRecordNames).subtracting(deleted)
    let resolved = try validatedNames(observation.resolvedRecordNames)
      .subtracting(corrupt)
      .union(deleted)

    _ = try reconcilePhysicalDeletions(db, deletedRecordNames: deleted)

    for recordName in resolved.sorted() {
      try deleteFence(db, boundary: boundary, recordName: recordName)
    }

    let observedAt = SyncTimestampFormat.syncTimestampNow()
    for recordName in corrupt.sorted() {
      try db.execute(
        sql: """
          INSERT INTO sync_cloudkit_corrupt_record_fences (
              account_identifier, zone_identifier, generation,
              generation_identifier, ready_witness, record_name,
              first_observed_at, last_observed_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT (
              account_identifier, zone_identifier, generation,
              generation_identifier, ready_witness, record_name
          ) DO UPDATE SET last_observed_at = excluded.last_observed_at
          """,
        arguments: [
          boundary.accountIdentifier, boundary.zoneIdentifier, boundary.generation,
          boundary.generationIdentifier, boundary.readyWitness, recordName,
          observedAt, observedAt,
        ])
    }
  }

  /// A successfully finalized authoritative snapshot examined the complete
  /// generation inventory and would have aborted on any corrupt LorvexEntity.
  /// It therefore supersedes every incremental corrupt fence for this boundary.
  public static func clearAfterAuthoritativeSnapshot(
    _ db: Database,
    boundary: CloudTraversalBoundary
  ) throws {
    try db.execute(
      sql: """
        DELETE FROM sync_cloudkit_corrupt_record_fences
        WHERE account_identifier = ? AND zone_identifier = ?
          AND generation = ? AND generation_identifier = ? AND ready_witness = ?
        """,
      arguments: [
        boundary.accountIdentifier, boundary.zoneIdentifier, boundary.generation,
        boundary.generationIdentifier, boundary.readyWitness,
      ])
  }

  /// A confirmed whole-zone deletion is terminal for transport corruption
  /// observed in every generation that ever occupied that exact account/zone.
  /// Other accounts and zones remain independent recovery boundaries.
  public static func clearForDeletedZone(
    _ db: Database, accountIdentifier: String, zoneIdentifier: String
  ) throws {
    try CloudTraversalWitness.validateAccountIdentifier(accountIdentifier)
    try CloudTraversalWitness.validateZoneIdentifier(zoneIdentifier)
    try db.execute(
      sql: """
        DELETE FROM sync_cloudkit_corrupt_record_fences
        WHERE account_identifier = ? AND zone_identifier = ?
        """,
      arguments: [accountIdentifier, zoneIdentifier])
  }

  private static func deleteFence(
    _ db: Database,
    boundary: CloudTraversalBoundary,
    recordName: String
  ) throws {
    try db.execute(
      sql: """
        DELETE FROM sync_cloudkit_corrupt_record_fences
        WHERE account_identifier = ? AND zone_identifier = ?
          AND generation = ? AND generation_identifier = ? AND ready_witness = ?
          AND record_name = ?
        """,
      arguments: [
        boundary.accountIdentifier, boundary.zoneIdentifier, boundary.generation,
        boundary.generationIdentifier, boundary.readyWitness, recordName,
      ])
  }

  /// Physical CloudKit deletion is a terminal observation for any locally
  /// parked/quarantined copy of that opaque record slot. Recover the type/id
  /// from durable local provenance, compare its deterministic record name, and
  /// clear the whole obsolete retry lane in this page/cursor transaction. A
  /// preserved local intent is either re-armed or discarded according to its
  /// future-record resolution policy.
  /// Resolve locally parked debt for CloudKit slots physically deleted on this
  /// page. The apply driver invokes this immediately after duplicate-page
  /// preflight, before any envelope or pending-inbox replay, so a deleted child
  /// cannot materialize merely because its parent arrives on the same page.
  /// ``reconcilePage(_:boundary:observation:)`` repeats it idempotently at the
  /// cursor commit boundary as defense in depth.
  @discardableResult
  public static func reconcilePhysicalDeletions(
    _ db: Database, deletedRecordNames: Set<String>
  ) throws -> CloudPhysicalDeletionReconciliation {
    guard !deletedRecordNames.isEmpty else {
      return CloudPhysicalDeletionReconciliation()
    }
    var result = CloudPhysicalDeletionReconciliation()
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT envelope_entity_type AS entity_type,
               envelope_entity_id AS entity_id
        FROM sync_pending_inbox
        UNION
        SELECT entity_type, entity_id
        FROM sync_quarantine_blocklist
        UNION
        SELECT entity_type, entity_id
        FROM sync_outbox
        WHERE synced_at IS NULL AND disposition = ?
        """,
      arguments: [Outbox.Disposition.futureRecordHold.rawValue])
    for row in rows {
      let entityType: String = row["entity_type"]
      let entityID: String = row["entity_id"]
      let recordName = SyncRecordName.opaque(
        entityType: entityType, entityId: entityID)
      guard deletedRecordNames.contains(recordName) else { continue }
      switch try FutureRecordHold.reconcilePhysicalCloudDeletion(
        db, entityType: entityType, entityId: entityID)
      {
      case .unchanged:
        break
      case .removedRemoteAuthoritative(let kind):
        result.removedEntityTypes.insert(kind)
      case .requiredInvariantNeedsReassertion(let kind, let entityID):
        result.requiredReassertions.insert(
          CloudPhysicalDeletionReassertion(entityType: kind, entityId: entityID))
      case .requiresAuthoritativeSnapshot(let kind):
        result.completeInventoryRequiredByEntityTypes.insert(kind)
      }
      try db.execute(
        sql: """
          DELETE FROM sync_pending_inbox
          WHERE envelope_entity_type = ? AND envelope_entity_id = ?
          """,
        arguments: [entityType, entityID])
      try db.execute(
        sql: """
          DELETE FROM sync_quarantine_blocklist
          WHERE entity_type = ? AND entity_id = ?
        """,
        arguments: [entityType, entityID])
    }
    try collectPermanentRedirectTargetTombstoneReassertions(
      db, deletedRecordNames: deletedRecordNames, into: &result)
    try reconcileCleanLiveIdentities(
      db, deletedRecordNames: deletedRecordNames, into: &result)
    return result
  }

  /// A terminal tombstone directly referenced by a permanent redirect is part
  /// of the alias graph, not ordinary reclaimable delete history. Its original
  /// Delete may already be confirmed and absent from the active outbox, so it is
  /// not discoverable through future-hold provenance or the live-row inventory.
  /// Match only this narrow tombstone subset and re-enqueue the exact stored
  /// death HLC; ordinary confirmed tombstones remain normal CloudKit retention.
  private static func collectPermanentRedirectTargetTombstoneReassertions(
    _ db: Database, deletedRecordNames: Set<String>,
    into result: inout CloudPhysicalDeletionReconciliation
  ) throws {
    for row in try Row.fetchAll(
      db,
      sql: """
        SELECT tombstone.entity_type, tombstone.entity_id
        FROM sync_tombstones AS tombstone
        WHERE \(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL)
        ORDER BY tombstone.entity_type, tombstone.entity_id COLLATE BINARY
        """)
    {
      let entityType: String = row["entity_type"]
      let entityID: String = row["entity_id"]
      guard let kind = EntityKind.parse(entityType), kind.isSyncableKind else {
        throw CloudInboundCompletenessError.invalidInvariantIdentity
      }
      guard deletedRecordNames.contains(
        SyncRecordName.opaque(entityType: entityType, entityId: entityID))
      else { continue }
      result.requiredReassertions.insert(
        CloudPhysicalDeletionReassertion(entityType: kind, entityId: entityID))
    }
  }

  /// Resolve deleted CloudKit slots whose local row is ordinary, already-sent
  /// canonical state (and therefore has no pending-inbox/future-hold provenance).
  /// Record names are intentionally one-way hashes, so compare the deleted set
  /// against the streaming canonical inventory rather than attempting to parse
  /// a record name.
  ///
  /// A still-pending local write wins an absent remote slot and is re-authored
  /// from current canonical storage. Otherwise remote absence is authoritative:
  /// independent leaves are pruned exactly, while relational roots defer to a
  /// complete-inventory snapshot so children and soft references are reconciled
  /// atomically. Delete envelopes are ignored here — physical removal of an
  /// already-confirmed tombstone is normal retention, not a live-row decision.
  private static func reconcileCleanLiveIdentities(
    _ db: Database, deletedRecordNames: Set<String>,
    into result: inout CloudPhysicalDeletionReconciliation
  ) throws {
    var localIntent = Set<LiveIdentity>()
    for row in try Row.fetchAll(
      db,
      sql: """
        SELECT entity_type, entity_id
        FROM sync_outbox
        WHERE synced_at IS NULL
          AND COALESCE(disposition, '') != ?
        """,
      arguments: [Outbox.Disposition.futureRecordHold.rawValue])
    {
      let typeRaw: String = row["entity_type"]
      guard let kind = EntityKind.parse(typeRaw), kind.isSyncableKind else {
        throw CloudInboundCompletenessError.invalidInvariantIdentity
      }
      localIntent.insert(LiveIdentity(kind: kind, entityID: row["entity_id"]))
    }

    var matched = Set<LiveIdentity>()
    try forEachLiveIdentity(db) { identity in
      let recordName = SyncRecordName.opaque(
        entityType: identity.kind.asString, entityId: identity.entityID)
      guard deletedRecordNames.contains(recordName) else { return }
      matched.insert(identity)
    }

    for identity in matched.sorted(by: {
      if $0.kind.asString != $1.kind.asString {
        return $0.kind.asString < $1.kind.asString
      }
      return $0.entityID < $1.entityID
    }) {
      if localIntent.contains(identity) {
        // Audit entries are append-only and carry their creation HLC only in
        // the existing outbox payload; there is no canonical row version from
        // which ConvergenceEmitter could mint a replacement envelope. Keep the
        // row and its exact pending upsert so the normal outbound pass recreates
        // the physically absent CloudKit slot without rewriting audit history.
        if identity.kind == .aiChangelog {
          continue
        }
        result.requiredReassertions.insert(
          CloudPhysicalDeletionReassertion(
            entityType: identity.kind, entityId: identity.entityID))
        continue
      }

      // Redirects are permanent aliases, so their live terminal target is an
      // invariant too. Pruning a target while retaining the alias would leave a
      // dangling ledger entry; deferring a relational target to a complete
      // inventory would make that inventory unable to apply the redirect. Keep
      // and re-author the target before the generic leaf/root policy instead.
      if try AuthoritativeAbsence.isPermanentRedirectTarget(
        db, entityType: identity.kind.asString, entityId: identity.entityID)
      {
        result.requiredReassertions.insert(
          CloudPhysicalDeletionReassertion(
            entityType: identity.kind, entityId: identity.entityID))
        continue
      }

      switch try AuthoritativeAbsence.incrementalPhysicalDeletionPolicy(
        entityType: identity.kind.asString, entityId: identity.entityID)
      {
      case .exactPrune:
        switch try AuthoritativeAbsence.prune(
          db, entityType: identity.kind.asString, entityId: identity.entityID)
        {
        case .unchanged:
          break
        case .removed(let kind):
          result.removedEntityTypes.insert(kind)
        case .requiredInboxNeedsReassertion:
          result.requiredReassertions.insert(
            CloudPhysicalDeletionReassertion(
              entityType: .list, entityId: identity.entityID))
        case .requiredTimezoneNeedsReassertion:
          result.requiredReassertions.insert(
            CloudPhysicalDeletionReassertion(
              entityType: .preference, entityId: identity.entityID))
        }
      case .reassertInvariant:
        result.requiredReassertions.insert(
          CloudPhysicalDeletionReassertion(
            entityType: identity.kind, entityId: identity.entityID))
      case .requireCompleteInventory:
        try AuthoritativeAbsence.clearIdentityMetadata(
          db, entityType: identity.kind.asString, entityId: identity.entityID)
        result.completeInventoryRequiredByEntityTypes.insert(identity.kind)
      }
    }

  }

  /// Enumerate canonical live sync identities without loading payload JSON.
  /// Physical CloudKit deletions are rare but may arrive in retention-sized
  /// batches; hashing only primary keys keeps the page transaction bounded and
  /// avoids an O(database) payload/enrichment pass under the writer lock.
  private static func forEachLiveIdentity(
    _ db: Database, _ consume: (LiveIdentity) throws -> Void
  ) throws {
    let kinds = EntityKind.topologicalEntityOrder.compactMap(EntityKind.parse)
    for kind in kinds {
      if kind == .entityRedirect {
        for row in try Row.fetchAll(
          db,
          sql: """
            SELECT source_type, source_id
            FROM sync_entity_redirects
            ORDER BY source_type, source_id COLLATE BINARY
            """)
        {
          let sourceTypeRaw: String = row["source_type"]
          guard let sourceType = EntityKind.parse(sourceTypeRaw) else {
            throw CloudInboundCompletenessError.invalidInvariantIdentity
          }
          let sourceID: String = row["source_id"]
          try consume(
            LiveIdentity(
              kind: .entityRedirect,
              entityID: EntityRedirect.wireEntityId(
                sourceType: sourceType, sourceId: sourceID)))
        }
        continue
      }

      if kind.isEdge {
        let sql: String
        switch kind {
        case .taskTag:
          sql = "SELECT task_id AS a, tag_id AS b FROM task_tags ORDER BY a, b"
        case .taskDependency:
          sql =
            "SELECT task_id AS a, depends_on_task_id AS b "
            + "FROM task_dependencies ORDER BY a, b"
        case .taskCalendarEventLink:
          sql =
            "SELECT task_id AS a, calendar_event_id AS b "
            + "FROM task_calendar_event_links ORDER BY a, b"
        case .habitCompletion:
          sql =
            "SELECT habit_id AS a, completed_date AS b "
            + "FROM habit_completions ORDER BY a, b"
        default:
          continue
        }
        for row in try Row.fetchAll(db, sql: sql) {
          let left: String = row["a"]
          let right: String = row["b"]
          try consume(LiveIdentity(kind: kind, entityID: "\(left):\(right)"))
        }
        continue
      }

      guard let (table, primaryKey) = kind.tablePk else { continue }
      ValidationSQL.assertSafeSQLIdentifier(table)
      ValidationSQL.assertSafeSQLIdentifier(primaryKey)
      for entityID in try String.fetchAll(
        db, sql: "SELECT \(primaryKey) FROM \(table) ORDER BY \(primaryKey)")
      {
        if kind == .preference,
          PreferenceKeys.isExcludedFromPreferenceEntitySync(entityID)
        {
          continue
        }
        try consume(LiveIdentity(kind: kind, entityID: entityID))
      }
    }

    // Audit entries intentionally do not participate in topological inbound
    // apply order: they are append-only evidence, not dependencies of canonical
    // entities. They are nevertheless live CloudKit identities and must be in
    // the physical-deletion inventory. Enumerate them separately so a clean,
    // already-sent row can be exact-pruned without changing topology semantics.
    for entityID in try String.fetchAll(
      db, sql: "SELECT id FROM ai_changelog ORDER BY id")
    {
      try consume(LiveIdentity(kind: .aiChangelog, entityID: entityID))
    }
  }

  private static func validatedNames(_ names: [String]) throws -> Set<String> {
    var result = Set<String>()
    result.reserveCapacity(names.count)
    for name in names {
      guard !name.isEmpty, name.utf8.count <= maximumRecordNameBytes else {
        throw CloudInboundCompletenessError.invalidRecordName
      }
      result.insert(name)
    }
    return result
  }
}

public enum CloudInboundCompletenessError: Error, Sendable, Equatable {
  case invalidRecordName
  case invalidInvariantIdentity
  /// The transport's undecodable count and durable record-name evidence must
  /// describe the same set of records before the cursor can advance.
  case corruptRecordCountMismatch
}
