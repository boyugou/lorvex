import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  public func importNativeTaskGraphIfFresh(
    _ snapshot: NativeTaskGraphSnapshot
  ) async throws -> NativeTaskGraphImportDisposition {
    try withWrite { db, hlc, deviceID in
      guard try Self.taskDomainIsFresh(db) else { return .portableFallback }

      // Validate the whole graph against the roots visible in this same
      // BEGIN IMMEDIATE before the first INSERT. A missing list/tag means the
      // portable projection remains the only safe migration path; every other
      // validation failure rejects the native restore and rolls back the write.
      let knownListIDs = Set(try String.fetchAll(db, sql: "SELECT id FROM lists"))
      let knownTagIDs = Set(try String.fetchAll(db, sql: "SELECT id FROM tags"))
      let restorePlan: NativeTaskGraphRestorePlan
      do {
        restorePlan = try NativeTaskGraphRestoreAdapter.prepare(
          snapshot, knownListIDs: knownListIDs, knownTagIDs: knownTagIDs)
      } catch let error as NativeTaskGraphValidationError {
        switch error {
        case .missingEndpoint(let relation, _)
        where relation == "task.listID" || relation == "task-tag tag":
          return .portableFallback
        default:
          throw NativeTaskGraphImportError.invalidGraph(error.description)
        }
      } catch {
        throw NativeTaskGraphImportError.invalidGraph(error.localizedDescription)
      }

      let restored = restorePlan.snapshot
      try NativeTaskGraphImportMaterialize.insert(restored, into: db)
      try self.enqueueNativeTaskGraph(
        restored, db: db, deviceID: deviceID)
      try self.enqueueNativeTaskGraphTombstones(
        restored.tombstones, db: db, deviceID: deviceID)

      if let maximumHLC = restorePlan.validation.maximumHLC {
        // Shared validation already proves an operational successor exists.
        // Reserve it only after every exact row/outbox version is materialized;
        // the import changelog may then mint strictly above the backup ceiling.
        _ = hlc.nextVersion(dominating: maximumHLC)
      }
      try self.writeNativeTaskGraphAudit(
        db, taskIDs: restorePlan.validation.taskIDs, deviceID: deviceID)
      return .imported(taskCount: restorePlan.validation.taskIDs.count)
    }
  }

  /// Keep every synced audit envelope comfortably below the wire payload cap.
  /// The empty graph still receives one restore audit, while a large graph is
  /// represented by deterministic, non-overlapping ID chunks.
  static func nativeTaskGraphAuditChunks(taskIDs: Set<String>) -> [[String]] {
    let sorted = taskIDs.sorted()
    guard !sorted.isEmpty else { return [[]] }
    return stride(from: 0, to: sorted.count, by: LorvexBatchLimits.maxItems).map { start in
      Array(sorted[start..<min(start + LorvexBatchLimits.maxItems, sorted.count)])
    }
  }

  private func writeNativeTaskGraphAudit(
    _ db: Database, taskIDs: Set<String>, deviceID: String
  ) throws {
    let chunks = Self.nativeTaskGraphAuditChunks(taskIDs: taskIDs)
    for (index, ids) in chunks.enumerated() {
      let suffix = chunks.count == 1 ? "" : " (audit batch \(index + 1) of \(chunks.count))"
      try writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "import_native_task_graph",
          entityIds: ids,
          summary:
            "Restored \(taskIDs.count) task(s) from an Apple-native backup\(suffix)",
          initiatedBy: ChangelogInitiator.importAttribution),
        deviceId: deviceID)
    }
  }

  /// Exact restore is deliberately all-or-nothing for the complete local task
  /// domain. A historical sync artifact is state too: replaying an old graph on
  /// top of a tombstone, redirect, queued write, future shadow, or staged remote
  /// record could resurrect or later overwrite one half of the restored chain.
  private static func taskDomainIsFresh(_ db: Database) throws -> Bool {
    for table in [
      "tasks", "task_recurrence_exceptions", "task_tags", "task_dependencies",
      "task_checklist_items", "task_reminders", "task_calendar_event_links",
      "task_provider_event_links", "task_reminder_delivery_state",
    ] {
      ValidationSQL.assertSafeSQLIdentifier(table)
      if try Int.fetchOne(db, sql: "SELECT 1 FROM \(table) LIMIT 1") != nil {
        return false
      }
    }

    let types = NativeTaskGraphContract.syncedEntityTypes
    let placeholders = Array(repeating: "?", count: types.count).joined(separator: ", ")
    let typeArguments = StatementArguments(types)
    for (table, column) in [
      ("sync_tombstones", "entity_type"),
      ("sync_outbox", "entity_type"),
      ("sync_pending_inbox", "envelope_entity_type"),
      ("sync_quarantine_blocklist", "entity_type"),
      ("sync_payload_shadow", "entity_type"),
    ] {
      ValidationSQL.assertSafeSQLIdentifier(table)
      ValidationSQL.assertSafeSQLIdentifier(column)
      if try Int.fetchOne(
        db,
        sql: "SELECT 1 FROM \(table) WHERE \(column) IN (\(placeholders)) LIMIT 1",
        arguments: typeArguments) != nil
      {
        return false
      }
    }
    // An immutable generation capture or authoritative adoption can already
    // contain opaque task envelopes. Do not materialize exact local history in
    // the middle of either state machine.
    let hasGenerationStaging =
      try Int.fetchOne(
        db, sql: "SELECT 1 FROM sync_generation_snapshot_staging LIMIT 1") != nil
    let hasAuthoritativeSnapshot =
      try Int.fetchOne(
        db, sql: "SELECT 1 FROM sync_authoritative_snapshot LIMIT 1") != nil
    if hasGenerationStaging || hasAuthoritativeSnapshot {
      return false
    }
    return true
  }

  private func enqueueNativeTaskGraph(
    _ snapshot: NativeTaskGraphSnapshot, db: Database, deviceID: String
  ) throws {
    for task in snapshot.tasks.sorted(by: { $0.id < $1.id }) {
      try enqueueUpsert(
        db, deviceId: deviceID, kind: .task, entityId: task.id,
        version: task.version.description, registerIntent: .task(.all))
    }
    for edge in snapshot.tagEdges.sorted(by: {
      ($0.taskID, $0.tagID) < ($1.taskID, $1.tagID)
    }) {
      try enqueueUpsert(
        db, deviceId: deviceID, kind: .taskTag,
        entityId: "\(edge.taskID):\(edge.tagID)", version: edge.version.description)
    }
    for edge in snapshot.dependencyEdges.sorted(by: {
      ($0.taskID, $0.dependsOnTaskID) < ($1.taskID, $1.dependsOnTaskID)
    }) {
      try enqueueUpsert(
        db, deviceId: deviceID, kind: .taskDependency,
        entityId: DependencyEdge.encodeEntityId(
          taskId: edge.taskID, dependsOnTaskId: edge.dependsOnTaskID),
        version: edge.version.description)
    }
    for item in snapshot.checklistItems.sorted(by: { $0.id < $1.id }) {
      try enqueueUpsert(
        db, deviceId: deviceID, kind: .taskChecklistItem, entityId: item.id,
        version: item.version.description)
    }
    for reminder in snapshot.reminders.sorted(by: { $0.id < $1.id }) {
      try enqueueUpsert(
        db, deviceId: deviceID, kind: .taskReminder, entityId: reminder.id,
        version: reminder.version.description)
    }
  }

  private func enqueueNativeTaskGraphTombstones(
    _ tombstones: [NativeTaskTombstoneSnapshot], db: Database, deviceID: String
  ) throws {
    for tombstone in tombstones.sorted(by: {
      ($0.entityType.asString, $0.entityID) < ($1.entityType.asString, $1.entityID)
    }) {
      let version = tombstone.version.description
      try enqueueDelete(
        db,
        deviceId: deviceID,
        kind: tombstone.entityType,
        entityId: tombstone.entityID,
        payload: .object(["version": .string(version)]),
        version: version)

      // Enqueue owns tombstone creation, but its wall-clock timestamp describes
      // the restore transaction. Put back the backup's original deletion time;
      // CloudKit confirmation remains NULL because that receipt belongs to the
      // exporting account/zone and cannot be transferred safely.
      try db.execute(
        sql: """
          UPDATE sync_tombstones
          SET deleted_at = ?, cloud_confirmed_at = NULL
          WHERE entity_type = ? AND entity_id = ? AND version = ?
          """,
        arguments: [
          tombstone.deletedAt, tombstone.entityType.asString,
          tombstone.entityID, version,
        ])
      guard db.changesCount == 1 else {
        throw LorvexCoreError.unsupportedOperation(
          "The exact task restore could not materialize one deletion marker.")
      }
    }
  }
}
