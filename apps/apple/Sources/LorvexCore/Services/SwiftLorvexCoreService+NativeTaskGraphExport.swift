import GRDB
import LorvexDomain

extension SwiftLorvexCoreService {
  /// Captures both task representations under one SQLite read transaction. The
  /// portable projection remains the AI/migration document; `nativeGraph` is the
  /// exact Apple restore input and is rejected unless its cross-row invariants
  /// are closed at this snapshot.
  public func loadTaskExportBundleForDataExport() async throws -> TaskDataExportBundle {
    try read { db in
      let portableTasks = try Self.portableTasksForDataExport(db)
      let nativeGraph = try Self.nativeTaskGraphForDataExport(
        db, includeTaskCalendarEventLinkControlState: false)
      try Self.validateTaskExportIdentityClosure(
        portableTasks: portableTasks, nativeGraph: nativeGraph)
      return TaskDataExportBundle(tasks: portableTasks, nativeGraph: nativeGraph)
    }
  }

  /// The portable projection and native restore graph are two views of the
  /// same task roots. Fail closed if either mapper drops, duplicates, or
  /// fabricates an identity; otherwise the archive would advertise an exact
  /// graph that its importer must reject against the portable payload.
  static func validateTaskExportIdentityClosure(
    portableTasks: [ExportTask], nativeGraph: NativeTaskGraphSnapshot
  ) throws {
    let portableIdentityCounts = Dictionary(
      portableTasks.map { ($0.id, 1) }, uniquingKeysWith: +)
    let nativeIdentityCounts = Dictionary(
      nativeGraph.tasks.map { ($0.id, 1) }, uniquingKeysWith: +)
    guard portableIdentityCounts == nativeIdentityCounts else {
      throw LorvexCoreError.validation(
        field: "nativeTaskGraph",
        message:
          "Task export representations are temporarily inconsistent. Retry the export after sync finishes."
      )
    }
    do {
      try BackupV1TaskProjectionConsistency.validate(
        portableTasks: portableTasks, nativeGraph: nativeGraph)
    } catch {
      throw LorvexCoreError.validation(
        field: "nativeTaskGraph",
        message:
          "Task export representations are temporarily inconsistent. Retry the export after sync finishes."
      )
    }
  }

  static func nativeTaskGraphForDataExport(
    _ db: Database, includeTaskCalendarEventLinkControlState: Bool
  ) throws -> NativeTaskGraphSnapshot {
    let taskRows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, title, body, raw_input, ai_notes, status, list_id, priority,
               due_date, estimated_minutes, recurrence, spawned_from,
               spawned_from_version, recurrence_group_id, recurrence_instance_key,
               canonical_occurrence_date, content_version, schedule_version,
               lifecycle_version, archive_version, recurrence_rollover_state,
               recurrence_successor_id, version, created_at, updated_at,
               completed_at, last_deferred_at, last_defer_reason, planned_date,
               available_from, defer_count, archived_at
        FROM tasks
        ORDER BY id ASC
        """)
    let tasks = try taskRows.map(Self.nativeTaskSnapshot)

    Self.afterNativeTaskRowsExportReadForTesting?()

    let recurrenceExceptions = try Row.fetchAll(
      db,
      sql: """
        SELECT task_id, exception_date
        FROM task_recurrence_exceptions
        ORDER BY task_id ASC, exception_date ASC
        """
    ).map { row in
      NativeTaskRecurrenceExceptionSnapshot(
        taskID: row["task_id"], exceptionDate: row["exception_date"])
    }

    let tagEdges = try Row.fetchAll(
      db,
      sql: """
        SELECT task_id, tag_id, version, created_at
        FROM task_tags
        ORDER BY task_id ASC, tag_id ASC
        """
    ).map { row in
      NativeTaskTagEdgeSnapshot(
        taskID: row["task_id"], tagID: row["tag_id"],
        version: try nativeHlc(row["version"] as String),
        createdAt: row["created_at"])
    }

    let dependencyEdges = try Row.fetchAll(
      db,
      sql: """
        SELECT task_id, depends_on_task_id, version, created_at
        FROM task_dependencies
        ORDER BY task_id ASC, depends_on_task_id ASC
        """
    ).map { row in
      NativeTaskDependencyEdgeSnapshot(
        taskID: row["task_id"], dependsOnTaskID: row["depends_on_task_id"],
        version: try nativeHlc(row["version"] as String),
        createdAt: row["created_at"])
    }

    let checklistItems = try Row.fetchAll(
      db,
      sql: """
        SELECT id, task_id, position, text, completed_at, version, created_at, updated_at
        FROM task_checklist_items
        ORDER BY task_id ASC, position ASC, id ASC
        """
    ).map { row in
      NativeTaskChecklistItemSnapshot(
        id: row["id"], taskID: row["task_id"], position: row["position"],
        text: row["text"], completedAt: row["completed_at"],
        version: try nativeHlc(row["version"] as String),
        createdAt: row["created_at"], updatedAt: row["updated_at"])
    }

    let reminders = try Row.fetchAll(
      db,
      sql: """
        SELECT id, task_id, reminder_at, dismissed_at, cancelled_at, version,
               created_at, original_local_time, original_tz
        FROM task_reminders
        ORDER BY task_id ASC, reminder_at ASC, id ASC
        """
    ).map { row in
      NativeTaskReminderSnapshot(
        id: row["id"], taskID: row["task_id"], reminderAt: row["reminder_at"],
        dismissedAt: row["dismissed_at"], cancelledAt: row["cancelled_at"],
        version: try nativeHlc(row["version"] as String),
        createdAt: row["created_at"], originalLocalTime: row["original_local_time"],
        originalTimeZone: row["original_tz"])
    }

    let syncTypes = NativeTaskGraphContract.syncedEntityKinds
      .filter {
        includeTaskCalendarEventLinkControlState || $0 != .taskCalendarEventLink
      }
      .map(\.asString)
    let placeholders = Array(repeating: "?", count: syncTypes.count).joined(separator: ", ")
    let syncTypeArguments = StatementArguments(syncTypes)
    let tombstones = try Row.fetchAll(
      db,
      sql: """
        SELECT entity_type, entity_id, version, deleted_at
        FROM sync_tombstones
        WHERE entity_type IN (\(placeholders))
        ORDER BY entity_type ASC, entity_id ASC
        """,
      arguments: syncTypeArguments
    ).map { row in
      NativeTaskTombstoneSnapshot(
        entityType: try nativeEntityKind(row["entity_type"] as String),
        entityID: row["entity_id"],
        version: try nativeHlc(row["version"] as String),
        deletedAt: row["deleted_at"])
    }

    let payloadShadows = try Row.fetchAll(
      db,
      sql: """
        SELECT entity_type, entity_id, base_version, payload_schema_version,
               raw_payload_json, source_device_id, updated_at
        FROM sync_payload_shadow
        WHERE entity_type IN (\(placeholders))
        ORDER BY entity_type ASC, entity_id ASC
        """,
      arguments: syncTypeArguments
    ).map { row -> NativeTaskPayloadShadowSnapshot in
      let storedSchemaVersion: Int64 = row["payload_schema_version"]
      guard let payloadSchemaVersion = UInt32(exactly: storedSchemaVersion) else {
        throw LorvexCoreError.validation(
          field: "nativeTaskGraph",
          message:
            "Task sync contains an invalid payload-shadow schema version. Retry after database recovery finishes."
        )
      }
      return NativeTaskPayloadShadowSnapshot(
        entityType: try nativeEntityKind(row["entity_type"] as String),
        entityID: row["entity_id"],
        baseVersion: try nativeHlc(row["base_version"] as String),
        payloadSchemaVersion: payloadSchemaVersion,
        rawPayloadJSON: row["raw_payload_json"],
        sourceDeviceID: row["source_device_id"],
        updatedAt: row["updated_at"])
    }

    let snapshot = NativeTaskGraphSnapshot(
      tasks: tasks,
      recurrenceExceptions: recurrenceExceptions,
      tagEdges: tagEdges,
      dependencyEdges: dependencyEdges,
      checklistItems: checklistItems,
      reminders: reminders,
      tombstones: tombstones,
      payloadShadows: payloadShadows)
    let knownListIDs = Set(try String.fetchAll(db, sql: "SELECT id FROM lists"))
    let knownTagIDs = Set(try String.fetchAll(db, sql: "SELECT id FROM tags"))
    do {
      _ = try NativeTaskGraphValidator.validate(
        snapshot, knownListIDs: knownListIDs, knownTagIDs: knownTagIDs)
    } catch {
      throw LorvexCoreError.validation(
        field: "nativeTaskGraph",
        message:
          "Task sync is still reconciling related records. Retry the export after sync finishes.")
    }
    return snapshot
  }

  private static func nativeTaskSnapshot(_ row: Row) throws -> NativeTaskSnapshot {
    let spawnedFromVersionRaw: String? = row["spawned_from_version"]
    return NativeTaskSnapshot(
      id: row["id"],
      title: row["title"],
      body: row["body"],
      rawInput: row["raw_input"],
      aiNotes: row["ai_notes"],
      status: row["status"],
      listID: row["list_id"],
      priority: row["priority"],
      dueDate: row["due_date"],
      estimatedMinutes: row["estimated_minutes"],
      recurrence: row["recurrence"],
      spawnedFrom: row["spawned_from"],
      spawnedFromVersion: try spawnedFromVersionRaw.map(nativeHlc),
      recurrenceGroupID: row["recurrence_group_id"],
      recurrenceInstanceKey: row["recurrence_instance_key"],
      canonicalOccurrenceDate: row["canonical_occurrence_date"],
      contentVersion: try nativeHlc(row["content_version"] as String),
      scheduleVersion: try nativeHlc(row["schedule_version"] as String),
      lifecycleVersion: try nativeHlc(row["lifecycle_version"] as String),
      archiveVersion: try nativeHlc(row["archive_version"] as String),
      recurrenceRolloverState: row["recurrence_rollover_state"],
      recurrenceSuccessorID: row["recurrence_successor_id"],
      version: try nativeHlc(row["version"] as String),
      createdAt: row["created_at"],
      updatedAt: row["updated_at"],
      completedAt: row["completed_at"],
      lastDeferredAt: row["last_deferred_at"],
      lastDeferReason: row["last_defer_reason"],
      plannedDate: row["planned_date"],
      availableFrom: row["available_from"],
      deferCount: row["defer_count"],
      archivedAt: row["archived_at"])
  }

  private static func nativeHlc(_ raw: String) throws -> Hlc {
    do {
      return try Hlc.parseCanonical(raw)
    } catch {
      throw LorvexCoreError.validation(
        field: "nativeTaskGraph",
        message:
          "Task data contains a non-canonical version. Retry after sync or database recovery finishes."
      )
    }
  }

  private static func nativeEntityKind(_ raw: String) throws -> EntityKind {
    guard let kind = EntityKind.parse(raw) else {
      throw LorvexCoreError.validation(
        field: "nativeTaskGraph",
        message:
          "Task sync contains an unknown entity type. Retry after database recovery finishes."
      )
    }
    return kind
  }
}
