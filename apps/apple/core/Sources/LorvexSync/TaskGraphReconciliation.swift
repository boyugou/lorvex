import GRDB
import LorvexDomain
import LorvexStore

/// Cross-record normalization driven by terminal task lifecycle state.
///
/// Reminders and dependency edges sync independently from their task. These
/// helpers make the task lifecycle decision an absorbing gate for those records
/// and surface every derived mutation through the typed repair funnel.
enum TaskGraphReconciliation {
  static func repairTargetsAfterTaskWrite(
    _ db: Database, taskId: String, applyTs: String
  ) throws -> [TaskGraphRepairTarget] {
    guard
      let status = try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?1", arguments: [taskId]),
      status == StatusName.completed || status == StatusName.cancelled
    else { return [] }

    var targets = try cancelActiveReminders(db, taskId: taskId, applyTs: applyTs)
    if status == StatusName.cancelled {
      targets += try detachDependencies(db, taskId: taskId)
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

  private static func canonicalHlc(
    _ raw: String, entityType: EntityKind, entityId: String
  ) throws -> Hlc {
    do { return try Hlc.parseCanonical(raw) } catch {
      throw ApplyError.invalidPayload(
        "\(entityType.asString) \(entityId) has a non-canonical version")
    }
  }
}
