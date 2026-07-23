import GRDB
import LorvexDomain
import LorvexStore

/// Cross-record convergence for a recurring task parent's durable rollover
/// decision and its deterministic successor row.
enum TaskRolloverReconciliation {
  /// Hold an early successor until the exact parent authorization clock has
  /// arrived. A parent tombstone is terminal authority and lets apply re-root
  /// the surviving successor instead of waiting forever.
  static func deferralReason(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> DeferralReason? {
    guard envelope.operation == .upsert, envelope.entityType == .task,
      case .object(let object)? = JSONValue.parse(envelope.payload),
      case .string(let parentId)? = object["spawned_from"],
      case .string(let rawAuthorization)? = object["spawned_from_version"]
    else { return nil }
    guard let authorization = try? Hlc.parseCanonical(rawAuthorization) else {
      throw ApplyError.invalidPayload(
        "task \(envelope.entityId) spawned_from_version must be a canonical HLC")
    }
    guard let parent = try TaskSyncRow.load(db, id: parentId) else {
      if let tombstone = try Tombstone.getTombstone(
        db, entityType: EntityName.task, entityId: parentId)
      {
        guard let tombstoneClock = try? Hlc.parseCanonical(tombstone.version) else {
          throw ApplyError.invalidPayload("task \(parentId) has a corrupt tombstone version")
        }
        if tombstoneClock >= authorization { return nil }
      }
      return .missingDependency(entityType: .task, entityId: parentId)
    }
    guard let parentClock = try? Hlc.parseCanonical(parent.lifecycleVersion) else {
      throw ApplyError.invalidPayload(
        "task \(parentId) has a corrupt lifecycle_version")
    }
    if parentClock < authorization {
      return .aggregateInvariantBlocked(
        entityType: .task, entityId: parentId,
        invariant: "successor authorization \(rawAuthorization) has not arrived on its parent")
    }
    return nil
  }

  /// Reconcile an incoming successor against the current parent decision before
  /// writing it. The deferral preflight guarantees a live parent is never older
  /// than `spawned_from_version` here.
  static func reconcileIncoming(
    _ db: Database, row: TaskSyncRow
  ) throws -> (row: TaskSyncRow, repairIntent: TaskRegisterIntent) {
    guard let parentId = row.spawnedFrom else { return (row, []) }
    guard let parent = try TaskSyncRow.load(db, id: parentId) else {
      guard
        let tombstone = try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: parentId)
      else {
        throw ApplyError.invalidPayload(
          "task \(row.id) successor parent disappeared after dependency preflight")
      }
      var survivor = row
      try survivor.reRootSuccessor(at: tombstone.version)
      return (survivor, try survivor.changedRegisters(comparedTo: row))
    }
    let reconciled = try reconcile(child: row, parent: parent)
    return (reconciled, try reconciled.changedRegisters(comparedTo: row))
  }

  /// After a parent decision lands, normalize every already-materialized direct
  /// successor and its independently-synced dependent graph. The caller returns
  /// typed repair targets so the host re-emits every normalized record before
  /// acknowledging CloudKit.
  static func reconcileDescendants(
    _ db: Database, parentId: String, applyTs: String
  ) throws -> [TaskGraphRepairTarget] {
    guard var parent = try TaskSyncRow.load(db, id: parentId) else { return [] }
    var changed: [TaskGraphRepairTarget] = []

    // CloudKit does not order records across identities. The successor Delete
    // can therefore arrive before the parent snapshot that authorized it. If
    // that tombstone is at least as new as the authorization clock, the durable
    // delete is the terminal fact and the parent must not retain an authorization
    // pointing at a missing child. An older tombstone is superseded history: keep
    // the authorization so the later child Upsert can clear it normally.
    if parent.recurrenceRolloverState == "authorized",
      let successorId = parent.recurrenceSuccessorId,
      try TaskSyncRow.load(db, id: successorId) == nil,
      let tombstone = try Tombstone.getTombstone(
        db, entityType: EntityName.task, entityId: successorId)
    {
      guard let tombstoneVersion = try? Hlc.parseCanonical(tombstone.version),
        let authorizationVersion = try? Hlc.parseCanonical(parent.lifecycleVersion)
      else {
        throw ApplyError.invalidPayload(
          "task \(parentId) or successor \(successorId) has a non-canonical rollover clock")
      }
      if tombstoneVersion >= authorizationVersion {
        let original = parent
        try parent.endAuthorizationForDeletedSuccessor(at: tombstone.version)
        try ApplyTask.writeReconciledTask(db, row: parent)
        changed.append(
          .taskUpsert(
            taskId: parentId,
            registerIntent: try parent.changedRegisters(comparedTo: original)))
      }
    }

    var ids = Set(
      try String.fetchAll(
        db, sql: "SELECT id FROM tasks WHERE spawned_from = ?", arguments: [parentId]))
    if let successorId = parent.recurrenceSuccessorId, successorId != parentId {
      ids.insert(successorId)
    }
    for id in ids.sorted() {
      guard let child = try TaskSyncRow.load(db, id: id) else { continue }
      let reconciled = try reconcile(child: child, parent: parent)
      if reconciled != child {
        try ApplyTask.writeReconciledTask(db, row: reconciled)
        changed.append(
          .taskUpsert(
            taskId: id,
            registerIntent: try reconciled.changedRegisters(comparedTo: child)))
        changed += try TaskGraphReconciliation.repairTargetsAfterTaskWrite(
          db, taskId: id, applyTs: applyTs)
      }
    }
    return TaskGraphRepairTarget.coalesced(changed)
  }

  private static func reconcile(
    child: TaskSyncRow, parent: TaskSyncRow
  ) throws -> TaskSyncRow {
    if child.spawnedFrom == parent.id {
      guard let groupId = child.recurrenceGroupId,
        TaskRecurrenceSuccessorID.make(
          parentTaskId: parent.id, recurrenceGroupId: groupId) == child.id
      else {
        throw ApplyError.invalidPayload(
          "task \(child.id) is not the deterministic successor of \(parent.id)")
      }
    }
    if parent.recurrenceRolloverState == "authorized"
      || parent.recurrenceRolloverState == "revoked"
    {
      guard let groupId = parent.recurrenceGroupId,
        let recorded = parent.recurrenceSuccessorId,
        TaskRecurrenceSuccessorID.make(
          parentTaskId: parent.id, recurrenceGroupId: groupId) == recorded
      else {
        throw ApplyError.invalidPayload(
          "task \(parent.id) has a non-deterministic recurrence_successor_id")
      }
    }
    // A previously re-rooted advanced successor is independent unless the
    // parent explicitly re-authorizes its reserved deterministic identity.
    if child.spawnedFrom == nil,
      !(parent.recurrenceRolloverState == "authorized"
        && parent.recurrenceSuccessorId == child.id)
    {
      return child
    }
    let authorized =
      parent.recurrenceRolloverState == "authorized"
      && parent.recurrenceSuccessorId == child.id
    var result = child
    if authorized {
      try result.acceptAuthorization(
        parentId: parent.id, parentVersion: parent.lifecycleVersion,
        reviveIfDominated: true)
      return result
    }

    // A genuine edit that causally follows the contradicting parent decision is
    // preserved as an independent task. A pristine generated row is retained in
    // a cancelled form so re-completion can revive the exact deterministic id.
    let resolution: TaskRolloverContradictionResolution
    do {
      resolution = try TaskRolloverPolicy.resolveContradiction(
        decisionVersion: parent.lifecycleVersion,
        childClocks: TaskRolloverRegisterClocks(
          content: result.contentVersion, schedule: result.scheduleVersion,
          lifecycle: result.lifecycleVersion, archive: result.archiveVersion))
    } catch {
      throw ApplyError.invalidPayload(
        "task \(child.id) rollover register clocks are invalid: \(error)")
    }
    switch resolution {
    case .rerootAdvancedSuccessor:
      try result.reRootSuccessor(at: parent.lifecycleVersion)
    case .cancelStableSuccessor:
      try result.cancelRevokedSuccessor(at: parent.lifecycleVersion)
    }
    return result
  }
}
