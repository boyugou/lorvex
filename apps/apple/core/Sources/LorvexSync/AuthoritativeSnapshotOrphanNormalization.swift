import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Complete-inventory reasoning for hard-FK children in a CloudKit
/// authoritative snapshot.
///
/// CloudKit saves individual records rather than one relational transaction. A
/// drained zone can therefore contain a parent Delete (or no parent record) and
/// a stale child Upsert left by an interrupted push. Replaying that child as an
/// ordinary inbound envelope defers forever once the parent is gone. The
/// authoritative path delays only this contradictory shape until remote Deletes
/// and post-session local intent have settled, then either applies the child on
/// top of a protected parent or replaces the impossible CloudKit record with a
/// strict-successor Delete.
struct AuthoritativeSnapshotInventory {
  var currentByRecordName: [String: SyncEnvelope]
  var futureOrUnknownRecordNames: Set<String>
  var protectedLiveRecordNames: Set<String>
  var protectedRecordNames: Set<String>

  init(
    remoteEnvelopes: [SyncEnvelope], allRecordNames: Set<String>,
    localIntents: [AuthoritativeSnapshotLocalIntent]
  ) throws {
    var current: [String: SyncEnvelope] = [:]
    for envelope in remoteEnvelopes {
      let recordName = Self.recordName(
        entityType: envelope.entityType, entityId: envelope.entityId)
      guard current.updateValue(envelope, forKey: recordName) == nil else {
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: envelope.entityType.asString, entityId: envelope.entityId,
          reason: "complete snapshot contains duplicate current envelopes")
      }
    }
    currentByRecordName = current
    futureOrUnknownRecordNames = allRecordNames.subtracting(current.keys)
    protectedLiveRecordNames = Set(
      localIntents.lazy
        .filter { $0.envelope.operation == .upsert && $0.futureResolution == nil }
        .map(\.recordName))
    protectedRecordNames = Set(localIntents.lazy.map(\.recordName))
  }

  static func recordName(entityType: EntityKind, entityId: String) -> String {
    SyncRecordName.opaque(entityType: entityType.asString, entityId: entityId)
  }
}

extension AuthoritativeSnapshot {
  static func effectiveAuthoritativeEnvelope(
    _ envelope: SyncEnvelope, inventory: AuthoritativeSnapshotInventory,
    authoritativeLiveRecordNames: Set<String>
  ) throws -> SyncEnvelope {
    let softReferenceNormalized = try normalizeAuthoritativeSoftReferences(
      envelope, inventory: inventory)
    if try taskHasFutureOrUnknownListDependency(
      softReferenceNormalized, inventory: inventory)
    {
      return softReferenceNormalized
    }
    return try rehomeAuthoritativeTaskIfListAbsent(
      softReferenceNormalized,
      authoritativeLiveRecordNames: authoritativeLiveRecordNames)
  }

  /// Remove day-scoped soft references only when this complete inventory proves
  /// the target record absent (or explicitly deleted). Ordinary incremental
  /// pages cannot make that inference because a referenced task/event may arrive
  /// on a later page. Future/opaque records and post-session local Upserts remain
  /// protected evidence of a live target.
  static func normalizeAuthoritativeSoftReferences(
    _ envelope: SyncEnvelope, inventory: AuthoritativeSnapshotInventory
  ) throws -> SyncEnvelope {
    try normalizeAuthoritativeSoftReferences(envelope) { kind, entityID in
      inventoryProvesLive(
        kind: kind, entityID: entityID, inventory: inventory)
    }
  }

  static func normalizeAuthoritativeSoftReferences(
    _ envelope: SyncEnvelope,
    targetIsLive: (EntityKind, String) -> Bool
  ) throws -> SyncEnvelope {
    guard envelope.operation == .upsert,
      envelope.entityType == .currentFocus || envelope.entityType == .focusSchedule,
      case .object(var object)? = JSONValue.parse(envelope.payload)
    else { return envelope }

    var changed = false
    if envelope.entityType == .currentFocus,
      case .array(let taskIDs)? = object["task_ids"]
    {
      let retained = taskIDs.filter { value in
        guard case .string(let taskID) = value else { return true }
        let live = targetIsLive(.task, taskID)
        if !live { changed = true }
        return live
      }
      object["task_ids"] = .array(retained)
    }

    if envelope.entityType == .focusSchedule,
      case .array(let blocks)? = object["blocks"]
    {
      let retained = blocks.filter { value in
        guard case .object(let block) = value else { return true }
        if case .string(let taskID)? = block["task_id"],
          !targetIsLive(.task, taskID)
        {
          changed = true
          return false
        }
        if block["event_source"] == .string(FocusScheduleEventSource.canonical.rawValue),
          case .string(let eventID)? = block["calendar_event_id"],
          !targetIsLive(.calendarEvent, eventID)
        {
          changed = true
          return false
        }
        return true
      }
      object["blocks"] = .array(retained)
    }

    guard changed else { return envelope }
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: envelope.operation, version: envelope.version,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: envelope.deviceId)
  }

  private static func inventoryProvesLive(
    kind: EntityKind, entityID: String,
    inventory: AuthoritativeSnapshotInventory
  ) -> Bool {
    let recordName = AuthoritativeSnapshotInventory.recordName(
      entityType: kind, entityId: entityID)
    if inventory.futureOrUnknownRecordNames.contains(recordName)
      || inventory.protectedLiveRecordNames.contains(recordName)
    {
      return true
    }
    return inventory.currentByRecordName[recordName]?.operation == .upsert
  }

  static func authoritativeNormalizationReemitTarget(
    original: SyncEnvelope, effective: SyncEnvelope
  ) -> AbsenceReemitTarget? {
    guard original != effective,
      original.entityType == .currentFocus || original.entityType == .focusSchedule
    else { return nil }
    return AbsenceReemitTarget(
      entityType: original.entityType.asString, entityId: original.entityId)
  }

  /// A task whose list record is present but opaque/future must not be treated as
  /// if that list were authoritatively absent. Keep its exact payload so normal
  /// typed apply either uses a retained local parent or fails closed on the
  /// missing dependency; only a genuinely absent/current-Delete list takes the
  /// established inbox-rehome path.
  static func taskHasFutureOrUnknownListDependency(
    _ envelope: SyncEnvelope, inventory: AuthoritativeSnapshotInventory
  ) throws -> Bool {
    guard envelope.entityType == .task, envelope.operation == .upsert else {
      return false
    }
    return try ApplyFk.requiredDependencies(
      entityType: envelope.entityType.asString, entityId: envelope.entityId,
      payload: envelope.payload
    ).contains { kind, id in
      inventory.futureOrUnknownRecordNames.contains(
        AuthoritativeSnapshotInventory.recordName(
          entityType: kind, entityId: id))
    }
  }

  /// Whether a current, typed remote Upsert must wait for final dependency
  /// resolution. Tasks retain their established missing-list -> inbox repair;
  /// entity redirects retain their absorbing alias semantics. Every other kind
  /// is selected through the shared `ApplyFk.requiredDependencies` declaration,
  /// so new hard-FK children cannot silently bypass this inventory check.
  static func shouldDelayHardFkUpsert(
    _ envelope: SyncEnvelope, inventory: AuthoritativeSnapshotInventory
  ) throws -> Bool {
    guard envelope.operation == .upsert,
      envelope.payloadSchemaVersion <= LorvexVersion.payloadSchemaVersion,
      envelope.entityType != .task,
      envelope.entityType != .entityRedirect
    else { return false }

    let dependencies = try ApplyFk.requiredDependencies(
      entityType: envelope.entityType.asString, entityId: envelope.entityId,
      payload: envelope.payload)
    guard !dependencies.isEmpty else { return false }

    var hasAbsentOrDeletedDependency = false
    for (kind, id) in dependencies {
      let recordName = AuthoritativeSnapshotInventory.recordName(
        entityType: kind, entityId: id)
      // A record whose operation/schema this build cannot understand is still
      // inventory evidence. Never infer its absence or author a destructive
      // repair around it.
      if inventory.futureOrUnknownRecordNames.contains(recordName) {
        return false
      }
      if inventory.currentByRecordName[recordName]?.operation == .upsert {
        continue
      }
      hasAbsentOrDeletedDependency = true
    }
    return hasAbsentOrDeletedDependency
  }

  /// Prepare one contradictory child for replay after the parent/delete and
  /// post-session phases. Returning `true` tells the caller not to apply it in
  /// the ordinary current-record loop.
  static func stageDelayedHardFkUpsertIfNeeded(
    _ db: Database, envelope: SyncEnvelope,
    inventory: AuthoritativeSnapshotInventory,
    delayed: inout [SyncEnvelope]
  ) throws -> Bool {
    guard try shouldDelayHardFkUpsert(envelope, inventory: inventory) else {
      return false
    }
    // Reset the superseded child now, while its pre-adoption row is still
    // identifiable. Delayed ordinary apply admits the remote baseline unless a
    // post-session child intent has since won LWW.
    _ = try Tombstone.removeTombstone(
      db, entityType: envelope.entityType.asString,
      entityId: envelope.entityId)
    _ = try ApplyLww.resetVersionForAuthoritativeSnapshot(
      db, entityType: envelope.entityType.asString,
      entityId: envelope.entityId)
    delayed.append(envelope)
    return true
  }

  /// Resolve one delayed hard-FK Upsert after remote Deletes and post-session
  /// intent have both replayed. A now-live dependency admits the ordinary
  /// Upsert. A still-missing dependency is normalized only when the complete
  /// inventory proves it absent/deleted and no future record or protected local
  /// parent makes that conclusion unsafe.
  static func reconcileDelayedHardFkUpsert(
    _ db: Database, envelope: SyncEnvelope,
    inventory: AuthoritativeSnapshotInventory,
    registry: EntityApplierRegistry, hlc: HlcSession, deviceId: String,
    report: inout AuthoritativeSnapshotReport
  ) throws {
    let outcome = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
    switch outcome {
    case .applied:
      try FutureRecordHold.reconcileTerminalEnvelope(
        db, envelope: envelope, outcome: outcome)
      report.replayedRemoteRecords += 1
      report.changedEntityTypes.insert(envelope.entityType)
      if let target = try AbsencePreserveReemit.convergenceReemitTarget(
        db, envelope: envelope)
      {
        try enqueueConvergenceReemit(
          db, target: target, hlc: hlc, deviceId: deviceId)
      }

    case .remapped(_, let toEntityId):
      try FutureRecordHold.reconcileTerminalEnvelope(
        db, envelope: envelope, outcome: outcome)
      report.replayedRemoteRecords += 1
      report.changedEntityTypes.insert(envelope.entityType)
      if let target = try AbsencePreserveReemit.remappedMergeWinnerReemitTarget(
        db, envelope: envelope, toEntityId: toEntityId)
      {
        try enqueueConvergenceReemit(
          db, target: target, hlc: hlc, deviceId: deviceId)
      }

    case .skipped(let reason, _):
      let recordName = AuthoritativeSnapshotInventory.recordName(
        entityType: envelope.entityType, entityId: envelope.entityId)
      guard inventory.protectedRecordNames.contains(recordName) else {
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: envelope.entityType.asString, entityId: envelope.entityId,
          reason: "delayed authoritative child was unexpectedly skipped: \(reason)")
      }
      // A freshly re-stamped post-session mutation won LWW. The remote record is
      // reconciled without overwriting that causally-later local intent.
      report.replayedRemoteRecords += 1

    case .deferred(.missingDependency(let dependencyKind, let dependencyID)):
      guard
        let floor = try authoritativeOrphanDeleteFloor(
          envelope, missingDependency: (dependencyKind, dependencyID),
          inventory: inventory)
      else {
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: envelope.entityType.asString, entityId: envelope.entityId,
          reason: DeferralReason.missingDependency(
            entityType: dependencyKind, entityId: dependencyID
          ).message)
      }
      try authorOrphanDelete(
        db, envelope: envelope, floor: floor, hlc: hlc, deviceId: deviceId)
      report.replayedRemoteRecords += 1
      report.changedEntityTypes.insert(envelope.entityType)

    case .deferred(let reason):
      throw AuthoritativeSnapshotError.applyRejected(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        reason: reason.message)

    case .repairRequired(let obligation):
      try FutureRecordHold.reconcileTerminalEnvelope(
        db, envelope: envelope, outcome: outcome)
      try ApplyRepair.fulfill(
        db, obligation: obligation,
        mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
        deviceId: deviceId)
      report.replayedRemoteRecords += 1
      report.changedEntityTypes.insert(envelope.entityType)
      report.changedEntityTypes.formUnion(obligation.affectedEntityTypes)

    case .upsertRejectedByRetention:
      throw AuthoritativeSnapshotError.applyRejected(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        reason: "hard-FK child was unexpectedly rejected by audit retention")
    }
  }

  /// Return the exact floor for a safe orphan Delete, or `nil` when inventory
  /// evidence is not strong enough. The reported typed deferral must name a
  /// dependency declared by `ApplyFk`; current remote live parents, future/opaque
  /// records, and protected post-session parent Upserts all fail closed.
  private static func authoritativeOrphanDeleteFloor(
    _ envelope: SyncEnvelope,
    missingDependency: (EntityKind, String),
    inventory: AuthoritativeSnapshotInventory
  ) throws -> Hlc? {
    let dependencies = try ApplyFk.requiredDependencies(
      entityType: envelope.entityType.asString, entityId: envelope.entityId,
      payload: envelope.payload)
    guard
      dependencies.contains(where: {
        $0.0 == missingDependency.0 && $0.1 == missingDependency.1
      })
    else { return nil }

    for (kind, id) in dependencies {
      let recordName = AuthoritativeSnapshotInventory.recordName(
        entityType: kind, entityId: id)
      if inventory.futureOrUnknownRecordNames.contains(recordName) {
        return nil
      }
    }

    let missingRecordName = AuthoritativeSnapshotInventory.recordName(
      entityType: missingDependency.0, entityId: missingDependency.1)
    if inventory.protectedLiveRecordNames.contains(missingRecordName) {
      return nil
    }
    if inventory.currentByRecordName[missingRecordName]?.operation == .upsert {
      return nil
    }

    var floor = envelope.version
    for (kind, id) in dependencies {
      let recordName = AuthoritativeSnapshotInventory.recordName(
        entityType: kind, entityId: id)
      if let parent = inventory.currentByRecordName[recordName],
        parent.operation == .delete
      {
        floor = max(floor, parent.version)
      }
    }
    return floor
  }

  /// Materialize the repair as ordinary durable death state for the child's
  /// exact CloudKit identity. The Upsert already deferred because a hard parent
  /// is missing, so no relational row can legally remain. Writing the tombstone
  /// directly also avoids remapping a composite-edge Delete through an unrelated
  /// parent alias: the stale CloudKit slot itself is what must be replaced.
  private static func authorOrphanDelete(
    _ db: Database, envelope: SyncEnvelope, floor: Hlc,
    hlc: HlcSession, deviceId: String
  ) throws {
    let successor = hlc.nextVersion(dominating: floor)
    guard successor > floor else {
      throw EnqueueError.versionSuperseded(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        attemptedVersion: successor.description, existingVersion: floor.description)
    }
    let base = SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: .delete, version: floor,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{}", deviceId: deviceId)
    let delete = try SyncMutationSemantics.restamp(
      base, version: successor, deviceId: deviceId)

    guard
      try ApplyLww.getLocalVersion(
        db, entityType: envelope.entityType.asString,
        entityId: envelope.entityId) == nil
    else {
      throw AuthoritativeSnapshotError.applyRejected(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        reason: "hard-FK orphan remained materialized after dependency deferral")
    }
    try Tombstone.createTombstone(
      db, entityType: delete.entityType.asString, entityId: delete.entityId,
      version: delete.version.description,
      deletedAt: SyncTimestampFormat.syncTimestampNow())
    guard try Outbox.enqueueCoalesced(db, delete) != nil else {
      throw AuthoritativeSnapshotError.applyRejected(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        reason: "orphan Delete did not enter the active outbox")
    }
    ErrorLog.appendBestEffort(
      db, source: "sync.authoritative_snapshot.orphan_normalized",
      message: "replaced inconsistent remote hard-FK Upsert with a successor Delete",
      details: "entity=\(envelope.entityType.asString)/\(envelope.entityId)",
      level: "warning")
  }
}
