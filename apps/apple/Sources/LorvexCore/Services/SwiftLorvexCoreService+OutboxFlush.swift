import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Outbound outbox-enqueue flush for `SwiftLorvexCoreService`.
///
/// Every mutation funnels through `withWrite` (`+WriteSurface`). After the
/// workflow op has mutated rows but before the transaction commits, the surface
/// must push a `SyncEnvelope` for each touched entity into `sync_outbox` so the
/// CloudKit coordinator's `pendingOutbound()` has something to ship. These
/// helpers are that flush step.
///
/// They route exclusively through the ported `OutboxEnqueue` engine
/// (`enqueuePayloadUpsert` / `enqueuePayloadDelete` / `readEntityPayloadSnapshot`):
/// no envelope encoding or outbox SQL is hand-rolled here. Callers either mint
/// a fresh HLC from the mutation's `HlcSession` or pass the exact version their
/// workflow already persisted, so the envelope version is causally ordered with
/// (and committed atomically in) the same transaction as the mutation.
///
/// Only syncable kinds reach the outbox: every entry point guards on
/// ``EntityKind/isSyncableKind`` and silently no-ops for local-only kinds
/// (`device_state`, `feedback`). Coalescing
/// (enqueuing the same `(type, id)` twice before a push collapses to one row) is
/// the engine's job — these helpers just call enqueue.
extension SwiftLorvexCoreService {

  // MARK: - Primary entity upsert

  /// Read the current snapshot of `(kind, entityId)` and enqueue an Upsert
  /// envelope, minting a fresh version from `hlc`. No-op for local-only kinds.
  ///
  /// The snapshot reader (`readEntityPayloadSnapshot`) handles aggregate roots
  /// with embedded children (`current_focus`, `focus_schedule`, `daily_review`,
  /// `calendar_event`), `preference`, and the generic
  /// column-copy path. The caller passes the entity AFTER its row mutation has
  /// landed so the snapshot reflects the new state.
  func enqueueUpsert(
    _ db: Database, hlc: HlcSession, deviceId: String,
    kind: EntityKind, entityId: String,
    registerIntent: EntityRegisterIntent? = nil
  ) throws {
    try enqueueUpsert(
      db,
      deviceId: deviceId,
      kind: kind,
      entityId: entityId,
      version: hlc.nextVersionString(),
      registerIntent: registerIntent)
  }

  /// Enqueue an Upsert at the exact version the workflow already minted and
  /// persisted for the row.
  func enqueueUpsert(
    _ db: Database, deviceId: String,
    kind: EntityKind, entityId: String, version: String,
    registerIntent explicitRegisterIntent: EntityRegisterIntent? = nil
  ) throws {
    guard kind.isSyncableKind else { return }
    let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: kind.asString, entityId: entityId)
    // Inference is correct for single-stamp create/full-snapshot paths. Task
    // mutations spanning multiple registers must supply their explicit union.
    let registerIntent = explicitRegisterIntent
      ?? EntityRegisterIntent.inferredLocalMutation(entityType: kind, from: payload)
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: kind.asString, entityId: entityId, payload: payload,
      context: OutboxWriteContext(
        version: version, deviceId: deviceId,
        registerIntent: registerIntent))
  }

  /// Enqueue Upsert envelopes for a batch of simple-PK entities of one kind.
  func enqueueUpserts(
    _ db: Database, hlc: HlcSession, deviceId: String,
    kind: EntityKind, entityIds: [String]
  ) throws {
    for id in entityIds {
      try enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: kind, entityId: id)
    }
  }

  // MARK: - Append-only audit stream (emit-once)

  /// Enqueue the single emit-once `ai_changelog` upsert envelope for a row just
  /// written, minting versions from the mutation's own `session` clock.
  ///
  /// The append-only audit stream has no simple `(table, pk)`, so the caller
  /// passes a pre-built `payload`
  /// (``ChangelogWrite/buildChangelogSyncPayload(_:)``) instead of routing through
  /// `readEntityPayloadSnapshot`. Convergence is id-dedup on the peer
  /// (`INSERT OR IGNORE`, no LWW), so the ordinary mutation path emits it once.
  /// A candidate-zone baseline deliberately re-stages every still-retained row;
  /// ordinary full-resync does not. Retention removes expired records through a
  /// durable exact-zone CloudKit physical-delete queue, never sync tombstones.
  /// No-op for a non-syncable kind (defensive — the caller always passes
  /// `.aiChangelog`).
  func enqueueChangelogUpsert(
    _ db: Database, session: HlcSession, deviceId: String,
    kind: EntityKind, entityId: String, payload: JSONValue
  ) throws {
    guard kind.isSyncableKind else { return }
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: kind.asString, entityId: entityId, payload: payload,
      context: OutboxWriteContext(
        version: session.nextVersionString(), deviceId: deviceId))
  }

  // MARK: - Primary entity delete

  /// Enqueue a Delete envelope with a caller-supplied pre-delete `payload`
  /// snapshot (Delete never re-reads the row). No-op for local-only kinds.
  ///
  /// The caller MUST capture `payload` BEFORE the workflow DELETE removed the
  /// row, so a peer that missed the upsert can still reconstruct it for
  /// restore-from-trash.
  func enqueueDelete(
    _ db: Database, hlc: HlcSession, deviceId: String,
    kind: EntityKind, entityId: String, payload: JSONValue
  ) throws {
    try enqueueDelete(
      db,
      deviceId: deviceId,
      kind: kind,
      entityId: entityId,
      payload: payload,
      version: hlc.nextVersionString())
  }

  /// Enqueue a Delete at the exact version the workflow minted before removing
  /// the row. The payload must carry the same version.
  func enqueueDelete(
    _ db: Database, deviceId: String,
    kind: EntityKind, entityId: String, payload: JSONValue, version: String
  ) throws {
    guard kind.isSyncableKind else { return }
    try OutboxEnqueue.enqueuePayloadDelete(
      db, entityType: kind.asString, entityId: entityId, payload: payload,
      context: OutboxWriteContext(version: version, deviceId: deviceId))
  }

  // MARK: - Edge upserts (composite-PK)

  /// Enqueue an Upsert for one composite-PK edge with a caller-built `payload`.
  ///
  /// Edges have no `tablePk`, so `readEntityPayloadSnapshot` cannot read them;
  /// every edge enqueue builds its payload via the dedicated `PayloadLoaders`
  /// row loaders. A missing row (the edge id no longer resolves) is skipped.
  private func enqueueEdgeUpsert(
    _ db: Database, hlc: HlcSession, deviceId: String,
    kind: EntityKind, entityId: String, payload: JSONValue?
  ) throws {
    guard let payload else { return }
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: kind.asString, entityId: entityId, payload: payload,
      context: OutboxWriteContext(
        version: hlc.nextVersionString(), deviceId: deviceId))
  }

  /// Enqueue an Upsert for each `task_tag` edge id (`{task_id}:{tag_id}`).
  func enqueueTaskTagEdgeUpserts(
    _ db: Database, hlc: HlcSession, deviceId: String, edgeIds: [String]
  ) throws {
    for edgeId in edgeIds {
      let (taskId, tagId) = Self.splitCompositeId(edgeId)
      let payload = try PayloadLoaders.loadTaskTagSyncPayload(db, taskId: taskId, tagId: tagId)
      try enqueueEdgeUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .taskTag, entityId: edgeId, payload: payload)
    }
  }

  /// Enqueue an Upsert for each `task_dependency` edge id
  /// (`{task_id}:{depends_on_task_id}`).
  func enqueueDependencyEdgeUpserts(
    _ db: Database, hlc: HlcSession, deviceId: String, edgeIds: [String]
  ) throws {
    for edgeId in edgeIds {
      let (taskId, depId) = Self.splitCompositeId(edgeId)
      let payload: JSONValue? = try Row.fetchOne(
        db,
        sql: """
          SELECT task_id, depends_on_task_id, version, created_at FROM task_dependencies
          WHERE task_id = ? AND depends_on_task_id = ?
          """,
        arguments: [taskId, depId]
      ).map { row in
        PayloadLoaders.taskDependencyPayload(
          taskId: row["task_id"], dependsOnTaskId: row["depends_on_task_id"],
          version: row["version"], createdAt: row["created_at"])
      }
      try enqueueEdgeUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .taskDependency, entityId: edgeId,
        payload: payload)
    }
  }

  /// Enqueue an Upsert for a copied tag edge (spawned-successor inheritance).
  /// The `CopiedTagEdge` carries every payload field, so no DB read is needed.
  func enqueueCopiedTagEdgeUpsert(
    _ db: Database, hlc: HlcSession, deviceId: String, edge: CopiedTagEdge
  ) throws {
    let payload = PayloadLoaders.taskTagPayload(
      taskId: edge.taskId, tagId: edge.tagId, version: edge.version, createdAt: edge.createdAt)
    try enqueueEdgeUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .taskTag,
      entityId: "\(edge.taskId):\(edge.tagId)", payload: payload)
  }

  /// Enqueue an Upsert for one `habit_completions` edge
  /// (`{habit_id}:{completed_date}`), building the payload from the live row.
  func enqueueHabitCompletionUpsert(
    _ db: Database, hlc: HlcSession, deviceId: String, habitId: String, completedDate: String
  ) throws {
    let payload = try PayloadLoaders.loadHabitCompletionSyncPayload(
      db, habitId: habitId, completedDate: completedDate)
    try enqueueEdgeUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .habitCompletion,
      entityId: "\(habitId):\(completedDate)", payload: payload)
  }

  /// Enqueue an Upsert for one `task_calendar_event_links` edge
  /// (`{task_id}:{calendar_event_id}`), building the payload from the live row.
  func enqueueTaskCalendarEventLinkUpsert(
    _ db: Database, hlc: HlcSession, deviceId: String, taskId: String, calendarEventId: String
  ) throws {
    let payload = try PayloadLoaders.loadTaskCalendarEventLinkSyncPayload(
      db, taskId: taskId, calendarEventId: calendarEventId)
    try enqueueEdgeUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .taskCalendarEventLink,
      entityId: "\(taskId):\(calendarEventId)", payload: payload)
  }

  /// Split a composite edge id `"a:b"` into its two components on the first
  /// colon (entity ids are UUIDv7 / natural keys without embedded colons).
  static func splitCompositeId(_ id: String) -> (String, String) {
    guard let range = id.range(of: ":") else { return (id, "") }
    return (String(id[id.startIndex..<range.lowerBound]),
      String(id[range.upperBound...]))
  }
}
