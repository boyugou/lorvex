import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexWorkflow

/// Per-entity apply handlers for the composite-edge relation entities.
///
/// Edge `entity_id`s use the composite `"part1:part2"` form; the handler splits
/// on `:` via ``CompositeEdge/splitCompositeEdgeId(_:)`` to recover the
/// two-column primary key. Each upsert runs the shared LWW-gated `LwwUpsertSpec`;
/// each delete routes through ``ApplyLww/lwwGatedDelete``. FK-deferral (a missing
/// endpoint parks the envelope in `sync_pending_inbox`) happens upstream in
/// ``ApplyFk/checkFkDependencies(_:entityType:entityId:payload:)``.
///
/// Ported in full: `task_tag`, `task_calendar_event_link`,
/// `habit_completion`, and `task_dependency` including the cycle-break upsert
/// path.
enum ApplyEdge {

  private static func splitCompositeId(_ entityId: String) throws -> (String, String) {
    switch CompositeEdge.splitCompositeEdgeId(entityId) {
    case let .success(pair):
      return pair
    case let .failure(err):
      throw ApplyError.invalidPayload(err.description)
    }
  }

  // MARK: - task_tag

  static func applyTaskTagUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws {
    let (taskId, tagId) = try splitCompositeId(entityId)
    let val = try ApplyJSON.parseObject(payload)
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "task_tag")

    let sql = LwwUpsertSpec(
      table: "task_tags",
      columns: SyncEntityDescriptor.require(.taskTag).plainColumns,
      conflict: ["task_id", "tag_id"], tieBreak: tieBreak
    ).buildSQL()
    do {
      try db.execute(
        sql: sql,
        arguments: ["task_id": taskId, "tag_id": tagId, "created_at": createdAt, "version": version]
      )
    } catch { throw ApplyError.lift(error) }
  }

  static func applyTaskTagDelete(_ db: Database, entityId: String, version: String) throws {
    let (taskId, tagId) = try splitCompositeId(entityId)
    try ApplyLww.lwwGatedDelete(
      db, table: "task_tags", pkColumns: ["task_id", "tag_id"], pkValues: [taskId, tagId],
      incomingVersion: version)
  }

  // MARK: - task_calendar_event_link

  static func applyTaskCalendarEventLinkUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws {
    let (taskId, eventId) = try splitCompositeId(entityId)
    let val = try ApplyJSON.parseObject(payload)
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "task_calendar_event_link")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "task_calendar_event_link")

    // Canonical task-event edges are series-level. First-party writers
    // normalize a visible replacement to its master; accepting a decision row
    // from the wire would make the edge disappear when that generation resets.
    // A missing endpoint is intentionally left to the upstream FK dependency
    // parker, so only a present child endpoint is an invalid payload here.
    do {
      if let event = try Row.fetchOne(
        db, sql: "SELECT series_id FROM calendar_events WHERE id = ?", arguments: [eventId]),
        let seriesID: String = event[0]
      {
        throw ApplyError.invalidPayload(
          "task_calendar_event_link calendar_event_id must reference a base event; "
            + "decision '\(eventId)' belongs to series '\(seriesID)'")
      }
    } catch let error as ApplyError {
      throw error
    } catch {
      throw ApplyError.lift(error)
    }

    let sql = LwwUpsertSpec(
      table: "task_calendar_event_links",
      columns: SyncEntityDescriptor.require(.taskCalendarEventLink).plainColumns,
      conflict: ["task_id", "calendar_event_id"], tieBreak: tieBreak
    ).buildSQL()
    do {
      try db.execute(
        sql: sql,
        arguments: [
          "task_id": taskId, "calendar_event_id": eventId, "created_at": createdAt,
          "updated_at": updatedAt, "version": version,
        ])
    } catch { throw ApplyError.lift(error) }
  }

  static func applyTaskCalendarEventLinkDelete(_ db: Database, entityId: String, version: String)
    throws
  {
    let (taskId, eventId) = try splitCompositeId(entityId)
    try ApplyLww.lwwGatedDelete(
      db, table: "task_calendar_event_links", pkColumns: ["task_id", "calendar_event_id"],
      pkValues: [taskId, eventId], incomingVersion: version)
  }

  // MARK: - habit_completion

  static func applyHabitCompletionUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws {
    let (habitId, completedDate) = try splitCompositeId(entityId)
    let val = try ApplyJSON.parseObject(payload)
    let value = try ApplyJSON.requiredInt64(val, "value", entity: "habit_completion")
    // A completion count is always positive — every first-party writer in both
    // apps clamps to >= 1 (a count reaching 0 deletes the row). This relay binds
    // the peer's `value` verbatim, so pre-validate it against the schema
    // `CHECK (value > 0)` here: a hostile / corrupt envelope carrying `value <= 0`
    // drops as a typed InvalidPayload skip with a clear reason instead of tripping
    // the constraint at bind time.
    if value <= 0 {
      throw ApplyError.invalidPayload(
        "habit_completion payload.value must be > 0 (got \(value))")
    }
    let note = try ApplyJSON.optionalStr(val, "note", entity: "habit_completion")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "habit_completion")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "habit_completion")

    let sql = LwwUpsertSpec(
      table: "habit_completions",
      columns: SyncEntityDescriptor.require(.habitCompletion).plainColumns,
      conflict: ["habit_id", "completed_date"], tieBreak: tieBreak
    ).buildSQL()
    do {
      try db.execute(
        sql: sql,
        arguments: [
          "habit_id": habitId, "completed_date": completedDate, "value": value, "note": note,
          "created_at": createdAt, "updated_at": updatedAt, "version": version,
        ])
    } catch { throw ApplyError.lift(error) }
  }

  static func applyHabitCompletionDelete(_ db: Database, entityId: String, version: String) throws {
    let (habitId, completedDate) = try splitCompositeId(entityId)
    try ApplyLww.lwwGatedDelete(
      db, table: "habit_completions", pkColumns: ["habit_id", "completed_date"],
      pkValues: [habitId, completedDate], incomingVersion: version)
  }

  // MARK: - task_dependency

  /// Outcome of ``tryBreakCycleByHlc``. See ``applyTaskDependencyUpsert`` for the
  /// decision policy.
  private enum CycleBreak {
    /// The incoming edge has the oldest HLC on the SCC; reject it (the caller
    /// surfaces the validator's `StoreError.validation` via the conflict log).
    case incomingLoses
    /// An existing local edge has the oldest HLC; it has been deleted +
    /// tombstoned so the insert can proceed. Carries the loser edge's HLC for
    /// the conflict-log `loser_version` / `loser_device_id`.
    case existingLoses(
      loserTaskId: String, loserDependsOn: String, loserVersion: String, loserDeviceSuffix: String)
    /// The cycle vanished between the validator and the tiebreak; no tombstone /
    /// conflict-log row.
    case noCycle
  }

  @discardableResult
  static func applyTaskDependencyUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak,
    applyTs: String
  ) throws -> TaskGraphRepairTarget? {
    let (taskIdStr, dependsOnStr) = try splitCompositeId(entityId)
    let val = try ApplyJSON.parseObject(payload)
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "task_dependency")
    if let repair = try TaskGraphReconciliation.rejectDependencyWithCancelledEndpoint(
      db, entityId: entityId, taskId: taskIdStr, dependsOnTaskId: dependsOnStr,
      incomingVersion: version)
    {
      return repair
    }

    // Two devices operating offline can each add an edge that, merged, closes a
    // cycle. The local write path validates cycles before every insert, so a
    // remote edge must pass the same gate or the DAG invariant collapses. Wrap
    // cycle-break + INSERT in a savepoint so a partial failure cannot leave a
    // hole (the loser already deleted + tombstoned, the INSERT then failing).
    try StoreTransactions.withSavepoint(db, "cycle_break_and_insert") { db in
      let taskId = TaskId(trusted: taskIdStr)
      var cycleError: Error?
      do {
        try DependencyValidation.validateNoDependencyCycle(
          db, taskId: taskId, newDependsOn: [dependsOnStr])
      } catch {
        cycleError = error
      }

      if cycleError != nil {
        // Self-dependencies never break via tiebreak — the CHECK constraint and
        // the validator's explicit self-dep check both forbid the edge.
        if taskIdStr == dependsOnStr {
          throw ApplyError.dependencyCycleRejected(taskId: taskIdStr, dependsOn: dependsOnStr)
        }
        // One incoming edge can close SEVERAL edge-disjoint cycles at once (one
        // per existing dependsOn→taskId path). Each round evicts only that
        // round's SCC-minimum edge, so break and re-check until no path
        // remains. The loop terminates (every round removes one edge from a
        // finite set) and stays deterministic (each round's loser is a pure
        // function of the then-current edge set). If a later round's minimum
        // beats the incoming edge, the thrown rejection rolls the whole
        // savepoint back — earlier evictions included — so a rejected edge
        // never leaves partial cycle-break damage behind.
        cycleBreaking: while true {
          switch try tryBreakCycleByHlc(
            db, taskId: taskIdStr, dependsOn: dependsOnStr, incomingVersion: version,
            applyTs: applyTs)
          {
          case .incomingLoses:
            throw ApplyError.dependencyCycleRejected(taskId: taskIdStr, dependsOn: dependsOnStr)
          case .noCycle:
            break cycleBreaking
          case let .existingLoses(loserTaskId, loserDependsOn, loserVersion, loserDeviceSuffix):
            // The loser is already deleted + tombstoned. Log the resolution,
            // then re-check for a further disjoint cycle.
            try ConflictLog.logConflict(
              db,
              ConflictLog.Entry(
                entityType: EdgeName.taskDependency, entityId: "\(loserTaskId):\(loserDependsOn)",
                winnerVersion: version, loserVersion: loserVersion,
                loserDeviceId: loserDeviceSuffix, loserPayload: nil, resolvedAt: applyTs,
                resolutionType: ResolutionName.cycleBreak))
          }
        }
      }

      let sql = LwwUpsertSpec(
        table: "task_dependencies",
        columns: SyncEntityDescriptor.require(.taskDependency).plainColumns,
        conflict: ["task_id", "depends_on_task_id"], tieBreak: tieBreak
      ).buildSQL()
      do {
        try db.execute(
          sql: sql,
          arguments: [
            "task_id": taskIdStr, "depends_on_task_id": dependsOnStr, "created_at": createdAt,
            "version": version,
          ])
      } catch { throw ApplyError.lift(error) }
    }
    return nil
  }

  /// Resolve an edge-closes-cycle conflict deterministically. Enumerates every
  /// existing edge inside the strongly-connected component the incoming edge
  /// would close (via a recursive forward/backward CTE — depends only on the
  /// edge set, never insertion history, so every device computes the same set),
  /// and picks the globally-minimum `(version, task_id, depends_on_task_id)` as
  /// the loser. On `existingLoses`, deletes + tombstones that loser so the
  /// decision propagates; on `incomingLoses`, the incoming edge simply fails to
  /// apply.
  private static func tryBreakCycleByHlc(
    _ db: Database, taskId: String, dependsOn: String, incomingVersion: String, applyTs: String
  ) throws -> CycleBreak {
    // Quick rejection: no path from dependsOn back to taskId ⇒ no cycle.
    if try DependencyValidation.findCyclePath(
      db, targetId: TaskId(trusted: taskId), startId: TaskId(trusted: dependsOn)) == nil
    {
      return .noCycle
    }

    // Deterministic global MIN over all existing edges in the SCC.
    let candidate: (String, String, String)?
    do {
      candidate = try Row.fetchOne(
        db,
        sql: """
          WITH RECURSIVE
               forward(node) AS (
                   SELECT :start_id
                   UNION
                   SELECT td.depends_on_task_id
                   FROM task_dependencies td
                   JOIN forward f ON td.task_id = f.node
               ),
               backward(node) AS (
                   SELECT :target_id
                   UNION
                   SELECT td.task_id
                   FROM task_dependencies td
                   JOIN backward b ON td.depends_on_task_id = b.node
               )
           SELECT td.task_id, td.depends_on_task_id, td.version
           FROM task_dependencies td
           WHERE td.task_id IN forward
             AND td.depends_on_task_id IN forward
             AND td.task_id IN backward
             AND td.depends_on_task_id IN backward
           ORDER BY td.version ASC, td.task_id ASC, td.depends_on_task_id ASC
           LIMIT 1
          """,
        arguments: ["start_id": dependsOn, "target_id": taskId]
      ).map { ($0[0] as String, $0[1] as String, $0[2] as String) }
    } catch { throw ApplyError.lift(error) }

    // Compare the SCC-min existing edge against the incoming edge: the incoming
    // wins iff it strictly dominates the candidate under the canonical-preferring
    // tiebreak (typed `Hlc` when both parse; the canonical side when exactly one
    // does; a raw byte compare when neither does).
    guard let (existingTask, existingDep, existingVersion) = candidate,
      canonicalPreferringDominates(incoming: incomingVersion, existing: existingVersion)
    else {
      return .incomingLoses
    }

    do {
      try db.execute(
        sql: "DELETE FROM task_dependencies WHERE task_id = ?1 AND depends_on_task_id = ?2",
        arguments: [existingTask, existingDep])
    } catch { throw ApplyError.lift(error) }
    // Tombstone the loser using the incoming edge's version as the cluster-agreed
    // decision HLC (strictly greater than the loser's, else it wouldn't lose).
    try Tombstone.createTombstone(
      db, entityType: EdgeName.taskDependency, entityId: "\(existingTask):\(existingDep)",
      version: incomingVersion, deletedAt: applyTs)
    // Propagate the loser's removal to the server. Without this the local delete +
    // tombstone stay device-local while the loser's server record remains a live
    // upsert, so a brand-new device — or a changeTokenExpired full replay on the
    // peer that rejected the loser (incomingLoses) — RESURRECTS the dropped edge
    // once the winner is later deleted. The delete rides the decision HLC
    // (incomingVersion, strictly greater than the loser's), so it dominates the
    // loser's live record under LWW. The peer that OWNS the loser always reaches
    // this arm on merge, so its propagation reaches every peer (including the
    // incomingLoses peer, which therefore needs no local write of its own — one
    // that would in any case roll back with its cycle-rejection throw).
    try propagateCycleBreakLoserDelete(
      db, loserEntityId: "\(existingTask):\(existingDep)", decisionVersion: incomingVersion)
    let loserDeviceSuffix = (try? Hlc.parseCanonical(existingVersion))?.deviceSuffix ?? ""
    return .existingLoses(
      loserTaskId: existingTask, loserDependsOn: existingDep, loserVersion: existingVersion,
      loserDeviceSuffix: loserDeviceSuffix)
  }

  /// Enqueue a server-bound delete for a cycle-break loser edge at the decision
  /// HLC, so the tombstone reaches peers that would otherwise materialize the
  /// loser from its still-live server upsert. The local edge row is already
  /// deleted + tombstoned at `decisionVersion`, so the enqueue's version-stamp is
  /// a benign `entityNotFound` (delete path) and its tombstone mint a monotonic
  /// no-op. Enqueuing a `task_dependency` edge delete triggers no nested pending
  /// drain: an edge is never a foreign-key parent, so `hasPendingForTarget` is
  /// always false for it.
  ///
  /// This enqueue is part of the enclosing `cycle_break_and_insert` savepoint.
  /// It is deliberately fail-closed: advancing the inbound cursor after keeping
  /// only a device-local tombstone would leave the server's loser Upsert live,
  /// allowing a fresh device or full replay to resurrect the cycle. Any enqueue
  /// failure therefore rolls the loser delete, tombstone, conflict log, and
  /// incoming insert back together so the entire inbound envelope can retry.
  private static func propagateCycleBreakLoserDelete(
    _ db: Database, loserEntityId: String, decisionVersion: String
  ) throws {
    let deviceId = try SyncCheckpoints.getOrCreateDeviceId(db)
    try OutboxEnqueue.enqueuePayloadDelete(
      db, entityType: EdgeName.taskDependency, entityId: loserEntityId, payload: .object([:]),
      context: OutboxWriteContext(version: decisionVersion, deviceId: deviceId))
  }

  static func applyTaskDependencyDelete(_ db: Database, entityId: String, version: String) throws {
    let (taskId, dep) = try splitCompositeId(entityId)
    try ApplyLww.lwwGatedDelete(
      db, table: "task_dependencies", pkColumns: ["task_id", "depends_on_task_id"],
      pkValues: [taskId, dep], incomingVersion: version)
  }
}

// MARK: - EntityApplier conformances

public struct TaskTagApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityKind.taskTag.asString] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyEdge.applyTaskTagUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyEdge.applyTaskTagDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

public struct TaskCalendarEventLinkApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityKind.taskCalendarEventLink.asString] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyEdge.applyTaskCalendarEventLinkUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyEdge.applyTaskCalendarEventLinkDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

public struct HabitCompletionApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityKind.habitCompletion.asString] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyEdge.applyHabitCompletionUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyEdge.applyHabitCompletionDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

/// Apply handler for the `task_dependency` edge.
///
/// The upsert validates that the inbound edge does not close a dependency cycle
/// (`LorvexWorkflow.DependencyValidation.validateNoDependencyCycle` /
/// `findCyclePath`, matching the local write path) and, on a cycle, runs a
/// deterministic HLC-min tiebreak over the strongly-connected component the edge
/// would close: the globally-minimum-HLC edge loses and is deleted + tombstoned
/// so the verdict converges across the cluster. The whole gate + INSERT runs in
/// a savepoint. `applyDelete` is the in-row LWW-gated DELETE.
public struct TaskDependencyApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityKind.taskDependency.asString] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    let repair = try ApplyEdge.applyTaskDependencyUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak, applyTs: applyTs)
    if let repair {
      return .repairRequired(
        .propagateTaskRollover(
          targets: [repair], additionalFloor: envelope.version))
    }
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyEdge.applyTaskDependencyDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}
