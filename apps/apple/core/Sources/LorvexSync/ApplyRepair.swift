import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Fulfills convergence writes surfaced as typed ``ApplyRepairObligation``
/// values by the inbound apply engine.
///
/// The apply layer deliberately cannot author these writes itself: it has no
/// device identity or durable HLC session. A host that consumes an envelope
/// must call this helper in the same transaction before advancing its remote
/// checkpoint. The helper validates both the stored HLC floor and the minted
/// successor, so a corrupt or non-dominating clock fails closed instead of
/// acknowledging a repair that peers would reject.
public enum ApplyRepair {
  /// Fulfill one typed apply obligation atomically.
  ///
  /// `mintVersion` receives the highest locally-known HLC for the identity,
  /// including the triggering peer version, and must return a strictly newer
  /// canonical HLC. The resulting write uses the normal payload/outbox funnel,
  /// so row stamping, payload-shadow preservation, tombstone clearing, and
  /// outbox coalescing retain their ordinary invariants.
  public static func fulfill(
    _ db: Database, obligation: ApplyRepairObligation,
    mintVersion: @escaping (_ knownVersionFloor: Hlc?) -> String,
    deviceId: String
  ) throws {
    switch obligation {
    case .reassertRequiredInbox(let remoteDeleteVersion):
      try StoreTransactions.withSavepoint(db, "repair_required_inbox") { db in
        let floor = try requiredInboxVersionFloor(
          db, additionalFloor: remoteDeleteVersion)
        let rawVersion = mintVersion(floor)
        guard let version = try? Hlc.parseCanonical(rawVersion) else {
          throw ApplyRepairError.invalidMintedVersion(rawVersion)
        }
        if version <= floor {
          throw ApplyRepairError.nonDominatingMint(
            minted: version.description, floor: floor.description)
        }

        let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.list, entityId: "inbox")
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: EntityName.list, entityId: "inbox", payload: payload,
          context: OutboxWriteContext(
            version: version.description, deviceId: deviceId))
      }
    case .reassertRequiredTimezone(
      let fallbackValue, let fallbackUpdatedAt, let remoteDeleteVersion):
      try StoreTransactions.withSavepoint(db, "repair_required_timezone") { db in
        let floorEnvelope = SyncEnvelope(
          entityType: .preference, entityId: PreferenceKeys.prefTimezone,
          operation: .delete, version: remoteDeleteVersion,
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: "{}", deviceId: deviceId)
        let floor = try equalCollisionVersionFloor(
          db, contender: floorEnvelope, additionalFloor: remoteDeleteVersion)
        let version = try dominatingRepairVersion(
          floor: floor, mintVersion: mintVersion)

        if try PayloadLoaders.loadPreferenceSyncPayload(
          db, key: PreferenceKeys.prefTimezone) == nil
        {
          let storedValue: String
          do {
            storedValue = try SyncCanonicalize.canonicalizeJSON(fallbackValue)
          } catch {
            throw ApplyRepairError.resolvedPayloadUnavailable("\(error)")
          }
          _ = try PreferenceRepo.setPreference(
            db, key: PreferenceKeys.prefTimezone, value: storedValue,
            version: version.description, now: fallbackUpdatedAt)
        }
        let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.preference,
          entityId: PreferenceKeys.prefTimezone)
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: EntityName.preference,
          entityId: PreferenceKeys.prefTimezone, payload: payload,
          context: OutboxWriteContext(
            version: version.description, deviceId: deviceId))
      }
    case .reassertCalendarSeriesCutover(let entityId, let remoteDeleteVersion):
      try StoreTransactions.withSavepoint(db, "repair_calendar_series_cutover") { db in
        guard try CalendarSeriesCutoverRepo.fetch(db, id: entityId) != nil else {
          throw ApplyRepairError.resolvedStateMissing(
            entityType: EntityName.calendarSeriesCutover, entityId: entityId)
        }
        let floorEnvelope = SyncEnvelope(
          entityType: .calendarSeriesCutover, entityId: entityId,
          operation: .upsert, version: remoteDeleteVersion,
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: "{}", deviceId: deviceId)
        let floor = try equalCollisionVersionFloor(
          db, contender: floorEnvelope, additionalFloor: remoteDeleteVersion)
        let rawVersion = mintVersion(floor)
        guard let version = try? Hlc.parseCanonical(rawVersion) else {
          throw ApplyRepairError.invalidMintedVersion(rawVersion)
        }
        guard version > floor else {
          throw ApplyRepairError.nonDominatingMint(
            minted: version.description, floor: floor.description)
        }
        let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.calendarSeriesCutover, entityId: entityId)
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: EntityName.calendarSeriesCutover, entityId: entityId,
          payload: payload,
          context: OutboxWriteContext(
            version: version.description, deviceId: deviceId))
      }
    case .propagateCalendarCleanup(let targets, let additionalFloor):
      try StoreTransactions.withSavepoint(db, "repair_calendar_cleanup") { db in
        for target in targets {
          let operation = try currentRepairOperation(
            db, entityType: target.entityType, entityId: target.entityId,
            requested: target.operation)
          let floorEnvelope = SyncEnvelope(
            entityType: target.entityType, entityId: target.entityId,
            operation: operation, version: additionalFloor,
            payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
            payload: "{}", deviceId: deviceId)
          let floor = try equalCollisionVersionFloor(
            db, contender: floorEnvelope, additionalFloor: additionalFloor)
          let rawVersion = mintVersion(floor)
          guard let version = try? Hlc.parseCanonical(rawVersion) else {
            throw ApplyRepairError.invalidMintedVersion(rawVersion)
          }
          guard version > floor else {
            throw ApplyRepairError.nonDominatingMint(
              minted: version.description, floor: floor.description)
          }
          switch operation {
          case .upsert:
            let payload: JSONValue
            do {
              payload = try OutboxEnqueue.readEntityPayloadSnapshot(
                db, entityType: target.entityType.asString,
                entityId: target.entityId)
            } catch {
              throw ApplyRepairError.resolvedPayloadUnavailable("\(error)")
            }
            try OutboxEnqueue.enqueuePayloadUpsert(
              db, entityType: target.entityType.asString,
              entityId: target.entityId, payload: payload,
              context: OutboxWriteContext(
                version: version.description, deviceId: deviceId))
          case .delete:
            try OutboxEnqueue.enqueuePayloadDelete(
              db, entityType: target.entityType.asString,
              entityId: target.entityId,
              payload: .object(["version": .string(version.description)]),
              context: OutboxWriteContext(
                version: version.description, deviceId: deviceId))
          }
        }
      }
    case .propagateTaskRollover(let targets, let additionalFloor):
      try StoreTransactions.withSavepoint(db, "repair_task_rollover") { db in
        for target in TaskGraphRepairTarget.coalesced(targets) {
          switch target {
          case .taskUpsert(let taskId, let intent):
            let operation = try currentRepairOperation(
              db, entityType: .task, entityId: taskId, requested: .upsert)
            let floorEnvelope = SyncEnvelope(
              entityType: .task, entityId: taskId, operation: operation,
              version: additionalFloor,
              payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
              payload: "{}", deviceId: deviceId)
            let floor = try equalCollisionVersionFloor(
              db, contender: floorEnvelope, additionalFloor: additionalFloor)
            let version = try dominatingRepairVersion(
              floor: floor, mintVersion: mintVersion)
            if operation == .delete {
              try OutboxEnqueue.enqueuePayloadDelete(
                db, entityType: EntityName.task, entityId: taskId,
                payload: .object(["version": .string(version.description)]),
                context: OutboxWriteContext(
                  version: version.description, deviceId: deviceId))
              continue
            }
            // Re-author every derived register at the strict successor, together
            // with the row high-water mark, before building the outbound payload.
            // A root-only convergence re-emit leaves all four group clocks intact.
            try db.execute(
              sql: """
                UPDATE tasks SET
                  content_version = CASE WHEN :content THEN :version ELSE content_version END,
                  schedule_version = CASE WHEN :schedule THEN :version ELSE schedule_version END,
                  lifecycle_version = CASE WHEN :lifecycle THEN :version ELSE lifecycle_version END,
                  archive_version = CASE WHEN :archive THEN :version ELSE archive_version END,
                  version = :version
                WHERE id = :id
                """,
              arguments: [
                "content": intent.contains(.content) ? 1 : 0,
                "schedule": intent.contains(.schedule) ? 1 : 0,
                "lifecycle": intent.contains(.lifecycle) ? 1 : 0,
                "archive": intent.contains(.archive) ? 1 : 0,
                "version": version.description, "id": taskId,
              ])
            guard db.changesCount > 0 else {
              throw ApplyRepairError.resolvedStateMissing(
                entityType: EntityName.task, entityId: taskId)
            }
            let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
              db, entityType: EntityName.task, entityId: taskId)
            try OutboxEnqueue.enqueuePayloadUpsert(
              db, entityType: EntityName.task, entityId: taskId, payload: payload,
              context: OutboxWriteContext(
                version: version.description, deviceId: deviceId,
                registerIntent: intent.isEmpty ? .none : .task(intent)))

          case .relatedEntity(
            let entityType, let entityId, let requestedOperation, let knownVersionFloor):
            let operation = try currentRepairOperation(
              db, entityType: entityType, entityId: entityId,
              requested: requestedOperation)
            let targetFloor =
              knownVersionFloor.map { max(additionalFloor, $0) }
              ?? additionalFloor
            let floorEnvelope = SyncEnvelope(
              entityType: entityType, entityId: entityId, operation: operation,
              version: targetFloor,
              payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
              payload: "{}", deviceId: deviceId)
            let floor = try equalCollisionVersionFloor(
              db, contender: floorEnvelope, additionalFloor: targetFloor)
            let version = try dominatingRepairVersion(
              floor: floor, mintVersion: mintVersion)
            switch operation {
            case .upsert:
              let payload: JSONValue
              do {
                payload = try OutboxEnqueue.readEntityPayloadSnapshot(
                  db, entityType: entityType.asString, entityId: entityId)
              } catch {
                throw ApplyRepairError.resolvedPayloadUnavailable("\(error)")
              }
              try OutboxEnqueue.enqueuePayloadUpsert(
                db, entityType: entityType.asString, entityId: entityId,
                payload: payload,
                context: OutboxWriteContext(
                  version: version.description, deviceId: deviceId))
            case .delete:
              try OutboxEnqueue.enqueuePayloadDelete(
                db, entityType: entityType.asString, entityId: entityId,
                payload: .object(["version": .string(floor.description)]),
                context: OutboxWriteContext(
                  version: version.description, deviceId: deviceId))
            }
          }
        }
      }
    case .resolveEqualVersionCollision(let contender, let additionalFloor):
      try StoreTransactions.withSavepoint(db, "repair_equal_hlc_collision") { db in
        // Repairs are fulfilled only after every envelope and pending-inbox
        // replay in the page has settled. A later ordinary mutation for this
        // identity is already the canonical winner; replaying the old equal-HLC
        // contender above it would resurrect or overwrite that final state.
        if try canonicalStateStrictlySupersedes(db, contender: contender) {
          return
        }
        let floor = try equalCollisionVersionFloor(
          db, contender: contender, additionalFloor: additionalFloor)
        let rawVersion = mintVersion(floor)
        guard let version = try? Hlc.parseCanonical(rawVersion) else {
          throw ApplyRepairError.invalidMintedVersion(rawVersion)
        }
        guard version > floor else {
          throw ApplyRepairError.nonDominatingMint(
            minted: version.description, floor: floor.description)
        }
        let successor: SyncEnvelope
        do {
          successor = try SyncMutationSemantics.restamp(
            contender, version: version, deviceId: deviceId)
        } catch {
          throw ApplyRepairError.invalidContender("\(error)")
        }
        if successor.entityType == .aiChangelog {
          // Audit identity is append-only and therefore has no LWW version
          // column. A same-id semantic collision is the exceptional repair
          // boundary: replace the old immutable projection inside this
          // savepoint, then let the ordinary retention-aware applier validate
          // and insert the deterministic winner. Any failure rolls the old row
          // and its entity-id children back together.
          try db.execute(
            sql: "DELETE FROM ai_changelog WHERE id = ?",
            arguments: [successor.entityId])
        }
        let outcome = try Apply.applyEnvelope(
          db,
          registry: EntityApplierRegistry(
            appliers: EntityApplierRegistry.defaultEntityAppliers()),
          envelope: successor)
        switch outcome {
        case .applied:
          try enqueueResolvedCurrentState(
            db, successor: successor, resolvedEntityId: successor.entityId,
            deviceId: deviceId)
        case .remapped(_, let targetId):
          try enqueueResolvedCurrentState(
            db, successor: successor, resolvedEntityId: targetId,
            deviceId: deviceId)
        case .repairRequired(.reassertRequiredInbox(let remoteDeleteVersion)):
          try fulfill(
            db, obligation: .reassertRequiredInbox(remoteDeleteVersion: remoteDeleteVersion),
            mintVersion: mintVersion, deviceId: deviceId)
        case .repairRequired(
          .reassertRequiredTimezone(
            let fallbackValue, let fallbackUpdatedAt, let remoteDeleteVersion)):
          try fulfill(
            db,
            obligation: .reassertRequiredTimezone(
              fallbackValue: fallbackValue, fallbackUpdatedAt: fallbackUpdatedAt,
              remoteDeleteVersion: remoteDeleteVersion),
            mintVersion: mintVersion, deviceId: deviceId)
        case .repairRequired(
          .reassertCalendarSeriesCutover(let entityId, let remoteDeleteVersion)):
          try fulfill(
            db,
            obligation: .reassertCalendarSeriesCutover(
              entityId: entityId, remoteDeleteVersion: remoteDeleteVersion),
            mintVersion: mintVersion, deviceId: deviceId)
        case .repairRequired(
          .propagateCalendarCleanup(let targets, let additionalFloor)):
          try fulfill(
            db,
            obligation: .propagateCalendarCleanup(
              targets: targets, additionalFloor: additionalFloor),
            mintVersion: mintVersion, deviceId: deviceId)
        case .repairRequired(
          .propagateTaskRollover(let targets, let additionalFloor)):
          try fulfill(
            db,
            obligation: .propagateTaskRollover(
              targets: targets, additionalFloor: additionalFloor),
            mintVersion: mintVersion, deviceId: deviceId)
        case .repairRequired(.resolveEqualVersionCollision):
          throw ApplyRepairError.successorDidNotResolveCollision(
            entityType: successor.entityType.asString, entityId: successor.entityId)
        case .upsertRejectedByRetention:
          // Account-scoped audit retention is the terminal authority. Its apply
          // path has already queued the physical CloudKit deletion.
          break
        case .skipped(let reason, _):
          throw ApplyRepairError.successorApplyRejected(reason)
        case .deferred(let reason):
          throw ApplyRepairError.successorApplyRejected(reason.message)
        }
      }
    }
  }

  private static func dominatingRepairVersion(
    floor: Hlc, mintVersion: (_ knownVersionFloor: Hlc?) -> String
  ) throws -> Hlc {
    let rawVersion = mintVersion(floor)
    guard let version = try? Hlc.parseCanonical(rawVersion) else {
      throw ApplyRepairError.invalidMintedVersion(rawVersion)
    }
    guard version > floor else {
      throw ApplyRepairError.nonDominatingMint(
        minted: version.description, floor: floor.description)
    }
    return version
  }

  /// Repair obligations are coalesced until the whole inbound page has been
  /// applied. A later envelope in that page may therefore delete a row an
  /// earlier repair intended to upsert, or recreate a row an earlier invariant
  /// repair deleted. Re-read the canonical materialized state at fulfillment
  /// instead of emitting the now-stale requested operation.
  private static func currentRepairOperation(
    _ db: Database, entityType: EntityKind, entityId: String,
    requested: SyncOperation
  ) throws -> SyncOperation {
    if try ApplyLww.getLocalVersion(
      db, entityType: entityType.asString, entityId: entityId) != nil
    {
      return .upsert
    }
    if requested == .delete {
      // Derived deletes intentionally remove the live row before the repair
      // funnel authors its strict-successor tombstone.
      return .delete
    }
    if try Tombstone.getTombstone(
      db, entityType: entityType.asString, entityId: entityId) != nil
    {
      return .delete
    }
    throw ApplyRepairError.resolvedStateMissing(
      entityType: entityType.asString, entityId: entityId)
  }

  /// An equal-HLC contender is obsolete when a later envelope in the same page
  /// has already established a strictly newer live row or tombstone. Audit rows
  /// are append-only and carry no materialized version, so their multi-contender
  /// join must always run.
  private static func canonicalStateStrictlySupersedes(
    _ db: Database, contender: SyncEnvelope
  ) throws -> Bool {
    guard contender.entityType != .aiChangelog else { return false }
    var frontier: Hlc?
    if let raw = try ApplyLww.getLocalVersion(
      db, entityType: contender.entityType.asString, entityId: contender.entityId)
    {
      guard let version = try? Hlc.parseCanonical(raw) else {
        throw ApplyRepairError.invalidKnownVersion(raw)
      }
      frontier = version
    }
    if let tombstone = try Tombstone.getTombstone(
      db, entityType: contender.entityType.asString, entityId: contender.entityId)
    {
      guard let version = try? Hlc.parseCanonical(tombstone.version) else {
        throw ApplyRepairError.invalidKnownVersion(tombstone.version)
      }
      frontier = frontier.map { max($0, version) } ?? version
    }
    return frontier.map { $0 > contender.version } ?? false
  }

  private static func equalCollisionVersionFloor(
    _ db: Database, contender: SyncEnvelope, additionalFloor: Hlc?
  ) throws -> Hlc {
    let entityType = contender.entityType.asString
    let entityId = contender.entityId
    let versions = try String.fetchAll(
      db,
      sql: """
        SELECT version FROM sync_outbox
        WHERE entity_type = ? AND entity_id = ?
        UNION ALL
        SELECT version FROM sync_tombstones
        WHERE entity_type = ? AND entity_id = ?
        UNION ALL
        SELECT envelope_version FROM sync_pending_inbox
        WHERE envelope_entity_type = ? AND envelope_entity_id = ?
        UNION ALL
        SELECT version FROM sync_quarantine_blocklist
        WHERE entity_type = ? AND entity_id = ?
        UNION ALL
        SELECT base_version FROM sync_payload_shadow
        WHERE entity_type = ? AND entity_id = ?
        """,
      arguments: StatementArguments([
        entityType, entityId, entityType, entityId, entityType, entityId,
        entityType, entityId, entityType, entityId,
      ]))
    var floor = additionalFloor.map { max(contender.version, $0) } ?? contender.version
    if let local = try ApplyLww.getLocalVersion(
      db, entityType: entityType, entityId: entityId)
    {
      guard let parsed = try? Hlc.parseCanonical(local) else {
        throw ApplyRepairError.invalidKnownVersion(local)
      }
      floor = max(floor, parsed)
    }
    for raw in versions {
      guard let parsed = try? Hlc.parseCanonical(raw) else {
        throw ApplyRepairError.invalidKnownVersion(raw)
      }
      floor = max(floor, parsed)
    }
    return floor
  }

  /// Re-enqueue the post-apply canonical state rather than the contender's raw
  /// payload. Aggregate merges and forward-compatible shadows may have changed
  /// the materialized winner while applying the successor.
  private static func enqueueResolvedCurrentState(
    _ db: Database, successor: SyncEnvelope, resolvedEntityId entityId: String,
    deviceId: String
  ) throws {
    let entityType = successor.entityType
    if entityType == .aiChangelog {
      guard
        var object = try AuditRetentionFrontier.canonicalAuditPayloadObject(
          db, entityId: entityId)
      else {
        throw ApplyRepairError.resolvedStateMissing(
          entityType: entityType.asString, entityId: entityId)
      }
      object["version"] = .string(successor.version.description)
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: entityType.asString, entityId: entityId,
        payload: .object(object),
        context: OutboxWriteContext(
          version: successor.version.description, deviceId: deviceId))
      return
    }
    if entityType == .entityRedirect {
      let payload = try EntityRedirect.decodePayload(
        wireEntityId: successor.entityId, payload: successor.payload)
      guard
        let record = try EntityRedirect.get(
          db, sourceType: payload.sourceType.asString, sourceId: payload.sourceId),
        EntityRedirect.wireEntityId(
          sourceType: record.sourceType, sourceId: record.sourceId) == successor.entityId
      else {
        throw ApplyRepairError.resolvedStateMissing(
          entityType: entityType.asString, entityId: successor.entityId)
      }
      try EntityRedirect.enqueue(db, record: record, deviceId: deviceId)
      return
    }
    if let tombstone = try Tombstone.getTombstone(
      db, entityType: entityType.asString, entityId: entityId)
    {
      guard let version = try? Hlc.parseCanonical(tombstone.version) else {
        throw ApplyRepairError.invalidKnownVersion(tombstone.version)
      }
      try OutboxEnqueue.enqueuePayloadDelete(
        db, entityType: entityType.asString, entityId: entityId,
        payload: .object(["version": .string(version.description)]),
        context: OutboxWriteContext(version: version.description, deviceId: deviceId))
      return
    }
    guard
      let rawVersion = try ApplyLww.getLocalVersion(
        db, entityType: entityType.asString, entityId: entityId),
      let version = try? Hlc.parseCanonical(rawVersion)
    else {
      throw ApplyRepairError.resolvedStateMissing(
        entityType: entityType.asString, entityId: entityId)
    }
    let payload: JSONValue
    do {
      payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: entityType.asString, entityId: entityId)
    } catch {
      throw ApplyRepairError.resolvedPayloadUnavailable("\(error)")
    }
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: entityType.asString, entityId: entityId, payload: payload,
      context: OutboxWriteContext(version: version.description, deviceId: deviceId))
  }

  /// Highest HLC known locally for the canonical inbox. Besides the live row
  /// and ordinary outbox/tombstone ledgers, include future-schema holds,
  /// exhausted-envelope blocklist entries, and a payload shadow's base version:
  /// each is durable evidence of a version that a self-healing upsert must beat.
  private static func requiredInboxVersionFloor(
    _ db: Database, additionalFloor: Hlc
  ) throws -> Hlc {
    let versions = try String.fetchAll(
      db,
      sql: """
        SELECT version FROM lists WHERE id = 'inbox'
        UNION ALL
        SELECT version FROM sync_outbox
        WHERE entity_type = ? AND entity_id = 'inbox'
        UNION ALL
        SELECT version FROM sync_tombstones
        WHERE entity_type = ? AND entity_id = 'inbox'
        UNION ALL
        SELECT envelope_version FROM sync_pending_inbox
        WHERE envelope_entity_type = ? AND envelope_entity_id = 'inbox'
        UNION ALL
        SELECT version FROM sync_quarantine_blocklist
        WHERE entity_type = ? AND entity_id = 'inbox'
        UNION ALL
        SELECT base_version FROM sync_payload_shadow
        WHERE entity_type = ? AND entity_id = 'inbox'
        """,
      arguments: StatementArguments(Array(repeating: EntityName.list, count: 5)))

    var floor = additionalFloor
    for raw in versions {
      guard let parsed = try? Hlc.parseCanonical(raw) else {
        throw ApplyRepairError.invalidKnownVersion(raw)
      }
      floor = max(floor, parsed)
    }
    return floor
  }
}

/// Typed failures from the convergence-repair boundary.
public enum ApplyRepairError: Error, Equatable, CustomStringConvertible {
  case invalidKnownVersion(String)
  case invalidMintedVersion(String)
  case nonDominatingMint(minted: String, floor: String)
  case invalidContender(String)
  case successorDidNotResolveCollision(entityType: String, entityId: String)
  case successorApplyRejected(String)
  case resolvedStateMissing(entityType: String, entityId: String)
  case resolvedPayloadUnavailable(String)

  public var description: String {
    switch self {
    case .invalidKnownVersion(let version):
      return "required inbox repair found an invalid known HLC: \(version)"
    case .invalidMintedVersion(let version):
      return "required inbox repair minted an invalid HLC: \(version)"
    case .nonDominatingMint(let minted, let floor):
      return "required inbox repair mint did not dominate: \(minted) <= \(floor)"
    case .invalidContender(let detail):
      return "equal-HLC collision contender is invalid: \(detail)"
    case .successorDidNotResolveCollision(let entityType, let entityId):
      return "equal-HLC successor did not resolve collision: \(entityType)/\(entityId)"
    case .successorApplyRejected(let reason):
      return "equal-HLC successor apply was rejected: \(reason)"
    case .resolvedStateMissing(let entityType, let entityId):
      return "equal-HLC resolved state is missing: \(entityType)/\(entityId)"
    case .resolvedPayloadUnavailable(let detail):
      return "equal-HLC resolved payload is unavailable: \(detail)"
    }
  }
}
