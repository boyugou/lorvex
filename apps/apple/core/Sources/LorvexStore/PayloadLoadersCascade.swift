import Foundation
import GRDB
import LorvexDomain

extension PayloadLoaders {

  // MARK: - Per-task cascade scanners
  //
  // Each scanner returns `[(entity_id, payload)]` ready for a cascade tombstone
  // loop. `entity_id` is the wire-format identity: bare row id for non-edge
  // entities, composite `<parent>:<other>` for edges.

  public static func loadTaskTagsForTask(_ db: Database, taskId: String) throws -> [(String, JSONValue)] {
    let rows = try Row.fetchAll(
      db, sql: "SELECT \(taskTagSelectColumns) FROM task_tags WHERE task_id = ?1",
      arguments: [taskId])
    return rows.map { row in
      let t: String = row[0]
      let g: String = row[1]
      return ("\(t):\(g)", taskTagPayloadFromRow(row))
    }
  }

  public static func loadTaskCalendarEventLinksForTask(
    _ db: Database, taskId: String
  ) throws -> [(String, JSONValue)] {
    let rows = try Row.fetchAll(
      db,
      sql: "SELECT \(taskCalendarEventLinkSelectColumns) FROM task_calendar_event_links WHERE task_id = ?1",
      arguments: [taskId])
    return rows.map { row in
      let t: String = row[0]
      let e: String = row[1]
      return ("\(t):\(e)", taskCalendarEventLinkPayloadFromRow(row))
    }
  }

  public static func loadTaskDependenciesForTask(
    _ db: Database, taskId: String
  ) throws -> [(String, JSONValue)] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT \(taskDependencySelectColumns) FROM task_dependencies \
        WHERE task_id = ?1 OR depends_on_task_id = ?1 \
        ORDER BY task_id, depends_on_task_id
        """,
      arguments: [taskId])
    return rows.map { row in
      let t: String = row[0]
      let d: String = row[1]
      return ("\(t):\(d)", taskDependencyPayloadFromRow(row))
    }
  }

  public static func loadTaskChecklistItemsForTask(
    _ db: Database, taskId: String
  ) throws -> [(String, JSONValue)] {
    let rows = try Row.fetchAll(
      db, sql: "SELECT \(taskChecklistItemSelectColumns) FROM task_checklist_items WHERE task_id = ?1",
      arguments: [taskId])
    return rows.map { row in (row[0], taskChecklistItemPayloadFromRow(row)) }
  }

  public static func loadTaskRemindersForTask(
    _ db: Database, taskId: String
  ) throws -> [(String, JSONValue)] {
    let rows = try Row.fetchAll(
      db, sql: "SELECT \(taskReminderSelectColumns) FROM task_reminders WHERE task_id = ?1",
      arguments: [taskId])
    return rows.map { row in (row[0], taskReminderPayloadFromRow(row)) }
  }

  /// Batch sibling of ``loadTaskRemindersForTask(_:taskId:)``. Loads every
  /// `task_reminders` row for the supplied task ids in one indexed
  /// `WHERE task_id IN (...)` scan and groups the `(reminderId, payload)`
  /// tuples by their owning `task_id`. Task ids with no reminder rows are
  /// absent from the result map; empty input short-circuits to an empty map.
  ///
  /// Per task, the tuple list preserves the table scan order; callers that
  /// need a stable order (the enrichment pipeline sorts by `reminder_at`)
  /// must apply it themselves, matching the single-task loader's contract.
  public static func loadTaskRemindersForTasks(
    _ db: Database, taskIds: [String]
  ) throws -> [String: [(String, JSONValue)]] {
    if taskIds.isEmpty { return [:] }
    let placeholders = Sql.sqlCsvPlaceholders(taskIds.count)
    let rows = try Row.fetchAll(
      db,
      sql: "SELECT \(taskReminderSelectColumns) FROM task_reminders WHERE task_id IN (\(placeholders))",
      arguments: StatementArguments(taskIds))
    var out: [String: [(String, JSONValue)]] = [:]
    // Column 1 is `task_id` per taskReminderSelectColumns order.
    for row in rows {
      let taskId: String = row[1]
      out[taskId, default: []].append((row[0], taskReminderPayloadFromRow(row)))
    }
    return out
  }
}
