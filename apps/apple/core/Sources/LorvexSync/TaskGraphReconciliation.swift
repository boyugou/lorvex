import GRDB
import LorvexDomain
import LorvexStore

/// Cross-record normalization driven by terminal task lifecycle state.
///
/// Reminders and dependency edges sync independently from their task, while
/// current-focus and focus-schedule children travel inside day-root snapshots.
/// These helpers make the task lifecycle decision an absorbing gate for those
/// records and surface every derived mutation through the typed repair funnel.
enum TaskGraphReconciliation {
  static func repairTargetsAfterTaskWrite(
    _ db: Database, taskId: String, applyTs: String
  ) throws -> [TaskGraphRepairTarget] {
    guard
      let task = try Row.fetchOne(
        db,
        sql: "SELECT status, archived_at FROM tasks WHERE id = ?1",
        arguments: [taskId])
    else { return [] }
    let status: String = task["status"]
    let archivedAt: String? = task["archived_at"]
    var targets: [TaskGraphRepairTarget] = []

    // Archive is an absorbing eligibility decision for both day-plan
    // aggregates. Unlike completion/cancellation, an archived task is never a
    // valid current-focus item or focus-schedule block. Clean references that
    // arrived first and re-emit the affected aggregate roots.
    if archivedAt != nil {
      targets += try removeFocusReferences(db, taskId: taskId)
    }
    guard status == StatusName.completed || status == StatusName.cancelled else {
      return TaskGraphRepairTarget.coalesced(targets)
    }

    targets += try cancelActiveReminders(db, taskId: taskId, applyTs: applyTs)
    if status == StatusName.cancelled {
      targets += try detachDependencies(db, taskId: taskId)
      if try isContradictedStableSuccessor(db, taskId: taskId) {
        targets += try removeFocusReferences(db, taskId: taskId)
      }
    }
    return TaskGraphRepairTarget.coalesced(targets)
  }

  static func normalizeReminderForTerminalTask(
    _ db: Database, reminderId: String, taskId: String, applyTs: String
  ) throws -> TaskGraphRepairTarget? {
    guard
      let status = try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?1", arguments: [taskId]),
      status == StatusName.completed || status == StatusName.cancelled,
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT version FROM task_reminders WHERE id = ?1 "
          + "AND dismissed_at IS NULL AND cancelled_at IS NULL",
        arguments: [reminderId])
    else { return nil }
    let version = try canonicalHlc(row["version"], entityType: .taskReminder, entityId: reminderId)
    try db.execute(
      sql: "UPDATE task_reminders SET cancelled_at = ?1 WHERE id = ?2",
      arguments: [applyTs, reminderId])
    guard db.changesCount == 1 else { return nil }
    return .relatedEntity(
      entityType: .taskReminder, entityId: reminderId, operation: .upsert,
      knownVersionFloor: version)
  }

  static func rejectDependencyWithCancelledEndpoint(
    _ db: Database, entityId: String, taskId: String, dependsOnTaskId: String,
    incomingVersion: String
  ) throws -> TaskGraphRepairTarget? {
    let cancelledCount =
      try Int.fetchOne(
        db,
        sql:
          "SELECT COUNT(*) FROM tasks WHERE id IN (?1, ?2) AND status = 'cancelled'",
        arguments: [taskId, dependsOnTaskId]) ?? 0
    guard cancelledCount > 0 else { return nil }

    let storedVersion = try String.fetchOne(
      db,
      sql:
        "SELECT version FROM task_dependencies "
        + "WHERE task_id = ?1 AND depends_on_task_id = ?2",
      arguments: [taskId, dependsOnTaskId])
    try db.execute(
      sql:
        "DELETE FROM task_dependencies "
        + "WHERE task_id = ?1 AND depends_on_task_id = ?2",
      arguments: [taskId, dependsOnTaskId])
    let incomingFloor = try canonicalHlc(
      incomingVersion, entityType: .taskDependency, entityId: entityId)
    let floor: Hlc
    if let storedVersion {
      floor = max(
        incomingFloor,
        try canonicalHlc(
          storedVersion, entityType: .taskDependency, entityId: entityId))
    } else {
      floor = incomingFloor
    }
    return .relatedEntity(
      entityType: .taskDependency, entityId: entityId, operation: .delete,
      knownVersionFloor: floor)
  }

  static func removingIneligibleFocusTasks(
    _ db: Database, from taskIds: [String]
  ) throws -> (taskIds: [String], removed: Bool) {
    var kept: [String] = []
    kept.reserveCapacity(taskIds.count)
    var removed = false
    for taskId in taskIds {
      if try isDeleted(db, taskId: taskId)
        || (try isArchived(db, taskId: taskId))
        || (try isContradictedStableSuccessor(db, taskId: taskId))
      {
        removed = true
      } else {
        kept.append(taskId)
      }
    }
    return (kept, removed)
  }

  private static func cancelActiveReminders(
    _ db: Database, taskId: String, applyTs: String
  ) throws -> [TaskGraphRepairTarget] {
    let rows = try Row.fetchAll(
      db,
      sql:
        "SELECT id, version FROM task_reminders "
        + "WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL "
        + "ORDER BY id",
      arguments: [taskId])
    var targets: [TaskGraphRepairTarget] = []
    targets.reserveCapacity(rows.count)
    for row in rows {
      let reminderId: String = row["id"]
      let floor = try canonicalHlc(
        row["version"], entityType: .taskReminder, entityId: reminderId)
      try db.execute(
        sql: "UPDATE task_reminders SET cancelled_at = ?1 WHERE id = ?2",
        arguments: [applyTs, reminderId])
      if db.changesCount == 1 {
        targets.append(
          .relatedEntity(
            entityType: .taskReminder, entityId: reminderId, operation: .upsert,
            knownVersionFloor: floor))
      }
    }
    return targets
  }

  private static func detachDependencies(
    _ db: Database, taskId: String
  ) throws -> [TaskGraphRepairTarget] {
    var rows = try Row.fetchAll(
      db,
      sql:
        "SELECT task_id, depends_on_task_id, version FROM task_dependencies "
        + "WHERE task_id = ?1 ORDER BY depends_on_task_id",
      arguments: [taskId])
    rows += try Row.fetchAll(
      db,
      sql:
        "SELECT task_id, depends_on_task_id, version FROM task_dependencies "
        + "WHERE depends_on_task_id = ?1 ORDER BY task_id",
      arguments: [taskId])
    var targets: [TaskGraphRepairTarget] = []
    targets.reserveCapacity(rows.count)
    for row in rows {
      let source: String = row["task_id"]
      let dependency: String = row["depends_on_task_id"]
      let entityId = "\(source):\(dependency)"
      targets.append(
        .relatedEntity(
          entityType: .taskDependency, entityId: entityId, operation: .delete,
          knownVersionFloor: try canonicalHlc(
            row["version"], entityType: .taskDependency, entityId: entityId)))
    }
    try db.execute(
      sql: "DELETE FROM task_dependencies WHERE task_id = ?1", arguments: [taskId])
    try db.execute(
      sql: "DELETE FROM task_dependencies WHERE depends_on_task_id = ?1",
      arguments: [taskId])
    return targets
  }

  static func removeFocusReferences(
    _ db: Database, taskId: String
  ) throws -> [TaskGraphRepairTarget] {
    let focusRows = try Row.fetchAll(
      db,
      sql:
        "SELECT DISTINCT root.date, root.version "
        + "FROM current_focus root "
        + "JOIN current_focus_items item ON item.date = root.date "
        + "WHERE item.task_id = ?1 ORDER BY root.date",
      arguments: [taskId])
    let scheduleRows = try Row.fetchAll(
      db,
      sql:
        "SELECT DISTINCT root.date, root.version "
        + "FROM focus_schedule root "
        + "JOIN focus_schedule_blocks block ON block.date = root.date "
        + "WHERE block.task_id = ?1 ORDER BY root.date",
      arguments: [taskId])
    try db.execute(
      sql: "DELETE FROM current_focus_items WHERE task_id = ?1", arguments: [taskId])
    try db.execute(
      sql: "DELETE FROM focus_schedule_blocks WHERE task_id = ?1", arguments: [taskId])

    var targets: [TaskGraphRepairTarget] = []
    for row in focusRows {
      let date: String = row["date"]
      let remaining =
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM current_focus_items WHERE date = ?1",
          arguments: [date]) ?? 0
      let operation: SyncOperation
      if remaining == 0 {
        try db.execute(
          sql: "DELETE FROM current_focus WHERE date = ?1", arguments: [date])
        operation = .delete
      } else {
        operation = .upsert
      }
      targets.append(
        .relatedEntity(
          entityType: .currentFocus, entityId: date, operation: operation,
          knownVersionFloor: try canonicalHlc(
            row["version"], entityType: .currentFocus, entityId: date)))
    }
    for row in scheduleRows {
      let date: String = row["date"]
      let remaining =
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?1",
          arguments: [date]) ?? 0
      let operation: SyncOperation
      if remaining == 0 {
        try db.execute(
          sql: "DELETE FROM focus_schedule WHERE date = ?1", arguments: [date])
        operation = .delete
      } else {
        operation = .upsert
      }
      targets.append(
        .relatedEntity(
          entityType: .focusSchedule, entityId: date, operation: operation,
          knownVersionFloor: try canonicalHlc(
            row["version"], entityType: .focusSchedule, entityId: date)))
    }
    return targets
  }

  private static func isArchived(_ db: Database, taskId: String) throws -> Bool {
    try String.fetchOne(
      db,
      sql: "SELECT archived_at FROM tasks WHERE id = ?1 AND archived_at IS NOT NULL",
      arguments: [taskId]) != nil
  }

  private static func isDeleted(_ db: Database, taskId: String) throws -> Bool {
    try Tombstone.getTombstone(
      db, entityType: EntityName.task, entityId: taskId) != nil
  }

  static func isContradictedStableSuccessor(
    _ db: Database, taskId: String
  ) throws -> Bool {
    guard let child = try TaskSyncRow.load(db, id: taskId),
      child.status == StatusName.cancelled,
      let parentId = child.spawnedFrom,
      let groupId = child.recurrenceGroupId,
      TaskRecurrenceSuccessorID.make(
        parentTaskId: parentId, recurrenceGroupId: groupId) == child.id,
      let parent = try TaskSyncRow.load(db, id: parentId)
    else { return false }
    if parent.recurrenceRolloverState == "authorized",
      parent.recurrenceSuccessorId == child.id
    {
      return false
    }
    do {
      return try TaskRolloverPolicy.resolveContradiction(
        decisionVersion: parent.lifecycleVersion,
        childClocks: TaskRolloverRegisterClocks(
          content: child.contentVersion, schedule: child.scheduleVersion,
          lifecycle: child.lifecycleVersion, archive: child.archiveVersion))
        == .cancelStableSuccessor
    } catch {
      throw ApplyError.invalidPayload(
        "task \(taskId) rollover register clocks are invalid: \(error)")
    }
  }

  private static func canonicalHlc(
    _ raw: String, entityType: EntityKind, entityId: String
  ) throws -> Hlc {
    do { return try Hlc.parseCanonical(raw) } catch {
      throw ApplyError.invalidPayload(
        "\(entityType.asString) \(entityId) has a non-canonical version")
    }
  }
}
