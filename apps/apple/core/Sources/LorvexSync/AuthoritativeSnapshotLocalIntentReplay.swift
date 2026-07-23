import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// One active outbox row authored after the authoritative session's initial
/// atomic fence. These are user/MCP intents, not stale pre-adoption state.
struct AuthoritativeSnapshotLocalIntent: Sendable, Equatable {
  /// Present for an actual post-session outbox row. An implicit dependency is
  /// captured from the local canonical row and therefore has no queue slot yet.
  var outboxID: Int64?
  var envelope: SyncEnvelope
  var registerIntent: EntityRegisterIntent = .none
  /// Present when a current remote record is from a future schema/clock and
  /// fenced this post-session intent. The exact intent remains fenced until a
  /// later build can understand the remote record and legally mint above it.
  var futureHoldFloor: Hlc? = nil
  /// Non-nil only for an exact future-held post-session row. Such an intent
  /// remains byte-for-byte in the outbox until a later build understands the
  /// remote record; snapshot finalization must not mint above an unusable HLC.
  var futureResolution: FutureRecordHold.Resolution? = nil

  var recordName: String {
    SyncRecordName.opaque(
      entityType: envelope.entityType.asString, entityId: envelope.entityId)
  }
}

extension AuthoritativeSnapshot {
  /// Capture every active row eligible for this snapshot. Account-NULL forensic
  /// audit rows are deliberately device-local and never become snapshot intent;
  /// every cloud-addressable audit row belongs to the exact active account.
  static func capturePostSessionLocalIntents(
    _ db: Database, accountIdentifier: String, outboxBoundaryId: Int64
  ) throws -> [AuthoritativeSnapshotLocalIntent] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT outbox.id, outbox.entity_type, outbox.entity_id,
               outbox.operation, outbox.version, outbox.payload_schema_version,
               outbox.payload, outbox.register_intent, outbox.device_id,
               outbox.disposition, outbox.future_record_version,
               outbox.future_record_resolution
        FROM sync_outbox outbox
        WHERE outbox.synced_at IS NULL
          AND (
            outbox.disposition IS NULL
            OR (
              outbox.disposition = ?
              AND (
                outbox.id > ?
                OR outbox.future_record_resolution = ?
              )
            )
          )
          AND (
            outbox.entity_type <> ?
            OR EXISTS (
              SELECT 1 FROM ai_changelog audit
              WHERE audit.id = outbox.entity_id
                AND audit.retention_account_identifier = ?
            )
          )
        ORDER BY outbox.id ASC
        """,
      arguments: [
        Outbox.Disposition.futureRecordHold.rawValue,
        outboxBoundaryId, FutureRecordHold.Resolution.localAfterFuture.rawValue,
        EntityName.aiChangelog, accountIdentifier,
      ])

    return try rows.map { row in
      let entityType: String = row["entity_type"]
      let entityId: String = row["entity_id"]
      guard let kind = EntityKind.parse(entityType) else {
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: entityType, entityId: entityId,
          reason: "post-session outbox row has an unknown entity type")
      }
      let operationRaw: String = row["operation"]
      let operation: SyncOperation
      switch operationRaw {
      case SyncNaming.opUpsert: operation = .upsert
      case SyncNaming.opDelete: operation = .delete
      default:
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: entityType, entityId: entityId,
          reason: "post-session outbox row has an unknown operation")
      }
      let versionRaw: String = row["version"]
      guard let version = try? Hlc.parseCanonical(versionRaw),
        version.description == versionRaw
      else {
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: entityType, entityId: entityId,
          reason: "post-session outbox row has an invalid HLC")
      }
      let envelope = SyncEnvelope(
        entityType: kind, entityId: entityId, operation: operation,
        version: version, payloadSchemaVersion: row["payload_schema_version"],
        payload: row["payload"], deviceId: row["device_id"])
      guard case .success = envelope.validate() else {
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: entityType, entityId: entityId,
          reason: "post-session outbox row is not a valid sync envelope")
      }
      let rawRegisterIntent: Int64 = row["register_intent"]
      let registerIntent = try EntityRegisterIntent.validatedStored(
        rawValue: rawRegisterIntent, entityType: kind,
        operation: operation, payload: envelope.payload)
      let dispositionRaw: String? = row["disposition"]
      let futureHoldFloor: Hlc?
      let futureResolution: FutureRecordHold.Resolution?
      if dispositionRaw == Outbox.Disposition.futureRecordHold.rawValue {
        let floorRaw: String? = row["future_record_version"]
        guard let floorRaw, let floor = try? Hlc.parseCanonical(floorRaw),
          floor.description == floorRaw
        else {
          throw AuthoritativeSnapshotError.applyRejected(
            entityType: entityType, entityId: entityId,
            reason: "post-session future fence has an invalid canonical floor")
        }
        if operation == .delete {
          guard
            let tombstone = try Tombstone.getTombstone(
              db, entityType: entityType, entityId: entityId),
            tombstone.version == version.description
          else {
            throw AuthoritativeSnapshotError.applyRejected(
              entityType: entityType, entityId: entityId,
              reason: "post-session future-held delete has no exact tombstone")
          }
        }
        futureHoldFloor = floor
        guard
          let resolution = FutureRecordHold.Resolution(
            rawValue: row["future_record_resolution"] as String),
          resolution == .localAfterFuture
        else {
          throw AuthoritativeSnapshotError.applyRejected(
            entityType: entityType, entityId: entityId,
            reason: "post-session future fence lacks local-intent provenance")
        }
        futureResolution = resolution
      } else {
        guard dispositionRaw == nil else {
          throw AuthoritativeSnapshotError.applyRejected(
            entityType: entityType, entityId: entityId,
            reason: "post-session outbox row has an unsupported fence")
        }
        futureHoldFloor = nil
        futureResolution = nil
      }
      return AuthoritativeSnapshotLocalIntent(
        outboxID: row["id"], envelope: envelope,
        registerIntent: registerIntent,
        futureHoldFloor: futureHoldFloor,
        futureResolution: futureResolution)
    }
  }

  /// Add canonical local parent upserts for fresh child/edge intents whose
  /// dependencies are absent (or deleted) in the authoritative remote
  /// inventory. Editing a child after adoption starts is a causal assertion
  /// that its still-live parent must survive too. Without this closure the
  /// synthetic remote-absence pass deletes that parent, then the child replay
  /// defers forever on its FK and rolls back every finalization attempt.
  ///
  /// A parent already represented by a remote upsert is intentionally not
  /// promoted: replaying a freshly stamped stale local snapshot over a newer
  /// authoritative parent would preserve existence by destroying remote field
  /// edits. Dependencies recurse (child -> task -> list), and the shared
  /// ``ApplyFk/requiredDependencies(entityType:entityId:payload:)`` declaration
  /// covers every hard-FK child and edge kind.
  static func includingAbsentAuthoritativeDependencies(
    _ db: Database, intents: [AuthoritativeSnapshotLocalIntent],
    authoritativeLiveRecordNames: Set<String>,
    authoritativeUnresolvedRecordNames: Set<String> = [],
    deviceId: String
  ) throws -> [AuthoritativeSnapshotLocalIntent] {
    var result = intents
    var knownIndex: [String: Int] = [:]
    for (index, intent) in intents.enumerated() {
      guard knownIndex.updateValue(index, forKey: intent.recordName) == nil else {
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: intent.envelope.entityType.asString,
          entityId: intent.envelope.entityId,
          reason: "duplicate active post-session outbox identity")
      }
    }
    // Cutovers are permanent upsert-only fences, not ordinary authoritative
    // snapshot-owned rows. A complete zone that omits (or physically Deletes)
    // one may have lost the record, but absence must never erase the local
    // resurrection barrier. Promote every such local row to an implicit intent;
    // the normal replay mints a strict successor and republishes its full state.
    let localCutovers = try Row.fetchAll(
      db,
      sql: """
        SELECT id, version FROM calendar_series_cutovers ORDER BY id
        """)
    for row in localCutovers {
      let id: String = row["id"]
      let recordName = SyncRecordName.opaque(
        entityType: EntityName.calendarSeriesCutover, entityId: id)
      if authoritativeLiveRecordNames.contains(recordName) || knownIndex[recordName] != nil {
        continue
      }
      let versionRaw: String = row["version"]
      guard let version = try? Hlc.parseCanonical(versionRaw),
        version.description == versionRaw
      else {
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: EntityName.calendarSeriesCutover, entityId: id,
          reason: "local calendar series cutover has an invalid HLC")
      }
      let payload = try SyncCanonicalize.canonicalizeJSON(
        OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.calendarSeriesCutover, entityId: id))
      let envelope = SyncEnvelope(
        entityType: .calendarSeriesCutover, entityId: id,
        operation: .upsert, version: version,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: deviceId)
      result.append(
        AuthoritativeSnapshotLocalIntent(outboxID: nil, envelope: envelope))
      knownIndex[recordName] = result.count - 1
    }
    var cursor = 0
    intentLoop: while cursor < result.count {
      let intentIndex = cursor
      var intent = result[intentIndex]
      cursor += 1
      guard intent.envelope.operation == .upsert else { continue }
      let dependencies = try ApplyFk.requiredDependencies(
        entityType: intent.envelope.entityType.asString,
        entityId: intent.envelope.entityId,
        payload: intent.envelope.payload)
      for (dependencyKind, dependencyID) in dependencies {
        let recordName = SyncRecordName.opaque(
          entityType: dependencyKind.asString, entityId: dependencyID)
        let localDependencyVersionRaw = try ApplyLww.getLocalVersion(
          db, entityType: dependencyKind.asString, entityId: dependencyID)
        if let dependencyIntentIndex = knownIndex[recordName] {
          let dependencyIntent = result[dependencyIntentIndex]
          if dependencyIntent.envelope.operation == .delete,
            localDependencyVersionRaw == nil
          {
            if intent.envelope.entityType == .task,
              dependencyKind == .list
            {
              // Lists delete by re-homing their tasks rather than cascading
              // them. If the list row is already gone, encode that same product
              // invariant directly into the fresh task replay.
              intent.envelope = try rehomedTaskIntent(intent.envelope)
              intent.registerIntent = try intent.registerIntent.union(.task(.content))
              result[intentIndex] = intent
              continue
            }
            // For cascading parents, the canonical SQLite state is decisive:
            // a committed parent delete has already removed this child. A
            // leftover child-upsert queue row is stale transport residue, even
            // if its HLC was minted before a contending transaction committed.
            // Convert it to a dominating child delete so remote baseline replay
            // cannot resurrect an orphan and finalization never wedges on FK.
            intent.envelope = try orphanDeleteIntent(
              intent.envelope,
              dominating: dependencyIntent.envelope.version)
            intent.registerIntent = .none
            result[intentIndex] = intent
            continue intentLoop
          }
          continue
        }
        if authoritativeLiveRecordNames.contains(recordName) { continue }
        guard
          let versionRaw = localDependencyVersionRaw
        else {
          // There is no local canonical dependency to preserve. Ordinary apply
          // will still succeed if another remote record materializes it; if not,
          // the finalization fails closed rather than inventing a parent.
          continue
        }
        guard let version = try? Hlc.parseCanonical(versionRaw),
          version.description == versionRaw
        else {
          throw AuthoritativeSnapshotError.applyRejected(
            entityType: dependencyKind.asString, entityId: dependencyID,
            reason: "local dependency has an invalid HLC")
        }
        let payloadValue = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: dependencyKind.asString, entityId: dependencyID)
        let payload = try SyncCanonicalize.canonicalizeJSON(payloadValue)
        let envelope = SyncEnvelope(
          entityType: dependencyKind, entityId: dependencyID,
          operation: .upsert, version: version,
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: payload, deviceId: deviceId)
        guard case .success = envelope.validate() else {
          throw AuthoritativeSnapshotError.applyRejected(
            entityType: dependencyKind.asString, entityId: dependencyID,
            reason: "local dependency did not form a valid sync envelope")
        }
        let registerIntent: EntityRegisterIntent
        switch dependencyKind {
        case .calendarEvent:
          registerIntent =
            CalendarEventRegisterIntent.isBasePayload(envelope.payload)
            ? .calendar(.all) : .none
        case .task:
          registerIntent = .task(.all)
        default:
          registerIntent = .none
        }
        result.append(
          AuthoritativeSnapshotLocalIntent(
            outboxID: nil, envelope: envelope, registerIntent: registerIntent))
        knownIndex[recordName] = result.count - 1
      }
    }

    // Day-scoped aggregates deliberately use soft references, so they do not
    // enter the hard-dependency closure above. A preserved local focus/schedule
    // intent must nevertheless not replay a reference to a target that this
    // complete inventory proves absent. Retain the reference only for a typed
    // remote Upsert, an opaque/future remote record, or an explicit local target
    // Upsert that this same replay will preserve.
    let locallyProtectedLiveRecordNames = Set(
      result.lazy
        .filter { $0.envelope.operation == .upsert }
        .map(\.recordName))
    for index in result.indices {
      result[index].envelope = try normalizeAuthoritativeSoftReferences(
        result[index].envelope
      ) { kind, entityID in
        let recordName = SyncRecordName.opaque(
          entityType: kind.asString, entityId: entityID)
        return authoritativeLiveRecordNames.contains(recordName)
          || authoritativeUnresolvedRecordNames.contains(recordName)
          || locallyProtectedLiveRecordNames.contains(recordName)
      }
    }
    return result
  }

  static func rehomedTaskIntent(
    _ envelope: SyncEnvelope
  ) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(envelope.payload) else {
      throw AuthoritativeSnapshotError.applyRejected(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        reason: "post-session task payload is not an object")
    }
    object["list_id"] = .string("inbox")
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: envelope.operation, version: envelope.version,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: envelope.deviceId)
  }

  /// Normalize an internally-inconsistent authoritative task upsert whose named
  /// list has no live record in the same complete snapshot. The task is valid
  /// user data, while retaining the dangling FK would make finalization retry
  /// forever. Re-home to the required inbox and let the ordinary divergence
  /// detector emit the repaired snapshot at a fresh local HLC.
  static func rehomeAuthoritativeTaskIfListAbsent(
    _ envelope: SyncEnvelope, authoritativeLiveRecordNames: Set<String>
  ) throws -> SyncEnvelope {
    guard envelope.entityType == .task, envelope.operation == .upsert,
      case .object(let object)? = JSONValue.parse(envelope.payload),
      case .string(let listId)? = object["list_id"], !listId.isEmpty
    else { return envelope }
    let listRecordName = SyncRecordName.opaque(
      entityType: EntityName.list, entityId: listId)
    guard !authoritativeLiveRecordNames.contains(listRecordName) else {
      return envelope
    }
    return try rehomedTaskIntent(envelope)
  }

  private static func orphanDeleteIntent(
    _ envelope: SyncEnvelope, dominating parentDeleteVersion: Hlc
  ) throws -> SyncEnvelope {
    let floor = max(envelope.version, parentDeleteVersion)
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object(["version": .string(floor.description)]))
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: .delete, version: floor,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: payload, deviceId: envelope.deviceId)
  }

  static func discardCapturedIntentQueueRows(
    _ db: Database, intents: [AuthoritativeSnapshotLocalIntent]
  ) throws {
    let ids = intents.filter { $0.futureResolution == nil }.compactMap(\.outboxID)
    for start in stride(from: 0, to: ids.count, by: 500) {
      let chunk = Array(ids[start..<min(start + 500, ids.count)])
      let placeholders = Array(repeating: "?", count: chunk.count)
        .joined(separator: ",")
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE id IN (\(placeholders))",
        arguments: StatementArguments(chunk))
    }
  }

  /// A complete remote inventory owns the active account's cloud-addressable
  /// audit rows. Account-NULL forensic rows remain device-local and never enter
  /// this inventory.
  static func auditIDsInWorkingSet(
    _ db: Database, accountIdentifier: String
  ) throws -> [String] {
    try String.fetchAll(
      db,
      sql: """
        SELECT id FROM ai_changelog
        WHERE retention_account_identifier = ?
        ORDER BY id
        """,
      arguments: [accountIdentifier])
  }

  static func replayPostSessionLocalIntents(
    _ db: Database, intents: [AuthoritativeSnapshotLocalIntent],
    registry: EntityApplierRegistry, hlc: HlcSession, deviceId: String,
    report: inout AuthoritativeSnapshotReport
  ) throws {
    let ordered = try orderedPostSessionLocalIntents(
      intents.filter { $0.futureResolution == nil })

    for intent in ordered {
      let version = try localIntentReplayVersion(db, intent: intent, hlc: hlc)
      let replayResult = try PostBaselineLocalIntentReplay.applyAndEnqueue(
        db, intent: intent.envelope,
        registerIntent: intent.registerIntent,
        version: version, deviceId: deviceId, registry: registry)
      guard case .replayed(let replay, let outcome, let enqueued) = replayResult else {
        continue
      }
      switch outcome {
      case .applied:
        guard enqueued else {
          throw AuthoritativeSnapshotError.applyRejected(
            entityType: replay.entityType.asString, entityId: replay.entityId,
            reason: "post-session intent did not enter the active outbox")
        }
        report.changedEntityTypes.insert(replay.entityType)
      case .repairRequired(let obligation):
        try ApplyRepair.fulfill(
          db, obligation: obligation,
          mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
          deviceId: deviceId)
        report.changedEntityTypes.insert(replay.entityType)
        report.changedEntityTypes.formUnion(obligation.affectedEntityTypes)
      case .upsertRejectedByRetention:
        // A post-session audit event may have aged out while a long snapshot was
        // draining. The account policy remains authoritative; its purge queue is
        // the correct terminal result and no outbound record is recreated.
        break
      case .skipped(let reason, _):
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: replay.entityType.asString, entityId: replay.entityId,
          reason: "post-session replay was skipped: \(reason)")
      case .deferred(let reason):
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: replay.entityType.asString, entityId: replay.entityId,
          reason: "post-session replay deferred: \(reason.message)")
      case .remapped(let fromEntityId, let toEntityId):
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: replay.entityType.asString, entityId: replay.entityId,
          reason: "post-session replay remapped from \(fromEntityId) to \(toEntityId)")
      }
    }
  }

  /// Preserve exact post-session delete barriers whose remote identity is still
  /// occupied by an opaque future record. The authoritative tombstone reset
  /// rebuilds every other death marker from the remote inventory; these are the
  /// sole local barriers that remain valid but cannot yet be re-authored.
  static func futureHeldPostSessionTombstones(
    _ db: Database, intents: [AuthoritativeSnapshotLocalIntent]
  ) throws -> [Tombstone.Record] {
    try intents.compactMap { intent in
      guard intent.futureResolution == .localAfterFuture,
        intent.envelope.operation == .delete
      else { return nil }
      guard
        let tombstone = try Tombstone.getTombstone(
          db, entityType: intent.envelope.entityType.asString,
          entityId: intent.envelope.entityId),
        tombstone.version == intent.envelope.version.description
      else {
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: intent.envelope.entityType.asString,
          entityId: intent.envelope.entityId,
          reason: "future-held post-session delete lost its exact tombstone")
      }
      return tombstone
    }
  }

  static func restoreFutureHeldPostSessionTombstones(
    _ db: Database, tombstones: [Tombstone.Record]
  ) throws {
    for tombstone in tombstones {
      try db.execute(
        sql: """
          INSERT INTO sync_tombstones
              (entity_type, entity_id, version, deleted_at, cloud_confirmed_at)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          tombstone.entityType, tombstone.entityId, tombstone.version,
          tombstone.deletedAt, tombstone.cloudConfirmedAt,
        ])
    }
  }

  private static func localIntentReplayVersion(
    _ db: Database, intent: AuthoritativeSnapshotLocalIntent, hlc: HlcSession
  ) throws -> Hlc {
    let envelope = intent.envelope
    var floor = envelope.version
    if let futureHoldFloor = intent.futureHoldFloor {
      floor = max(floor, futureHoldFloor)
    }
    if let localRaw = try ApplyLww.getLocalVersion(
      db, entityType: envelope.entityType.asString, entityId: envelope.entityId),
      let local = try? Hlc.parseCanonical(localRaw)
    {
      floor = max(floor, local)
    }
    if let tombstone = try Tombstone.getTombstone(
      db, entityType: envelope.entityType.asString, entityId: envelope.entityId),
      let death = try? Hlc.parseCanonical(tombstone.version)
    {
      floor = max(floor, death)
    }
    if let queuedRaw = try String.fetchOne(
      db,
      sql: """
        SELECT version FROM sync_outbox
        WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
        LIMIT 1
        """,
      arguments: [envelope.entityType.asString, envelope.entityId]),
      let queued = try? Hlc.parseCanonical(queuedRaw)
    {
      floor = max(floor, queued)
    }
    let version = hlc.nextVersion(dominating: floor)
    guard version > floor else {
      throw EnqueueError.versionSuperseded(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        attemptedVersion: version.description, existingVersion: floor.description)
    }

    return version
  }

}
