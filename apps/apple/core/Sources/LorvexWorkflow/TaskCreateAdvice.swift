import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Task-intake advice generator.
///
/// Inspects a freshly-loaded enriched task row and emits lightweight nudges
/// (missing estimate, missing planned date, likely-duplicate title) the
/// assistant surfaces back to the user. Pure read-only — no schema mutations.
public enum TaskCreateAdvice {
  public static func buildTaskIntakeAdvice(
    _ db: Database, task: JSONValue
  ) throws -> [JSONValue] {
    guard case let .object(fields) = task else { return [] }
    guard case let .string(taskId) = fields["id"] ?? .null else { return [] }
    let title: String
    if case let .string(t) = fields["title"] ?? .null { title = t } else { title = "task" }
    let status: String
    if case let .string(s) = fields["status"] ?? .null { status = s } else { status = StatusName.open }

    var advice: [JSONValue] = []

    let estimateMinutes: Int64
    switch fields["estimated_minutes"] ?? .null {
    case .int(let v): estimateMinutes = v
    case .uint(let v) where v <= UInt64(Int64.max): estimateMinutes = Int64(v)
    default: estimateMinutes = 0
    }
    if status == StatusName.open && estimateMinutes <= 0 {
      advice.append(.object([
        "code": .string("missing_estimate"),
        "severity": .string("medium"),
        "message": .string(
          "Add an estimate if you have a confident rough time cost."),
      ]))
    }
    let plannedDateMissing: Bool
    if case .string = fields["planned_date"] ?? .null {
      plannedDateMissing = false
    } else {
      plannedDateMissing = true
    }
    if status == StatusName.open && plannedDateMissing {
      advice.append(.object([
        "code": .string("missing_planned_date"),
        "severity": .string("medium"),
        "message": .string(
          "Set a planned_date when you know which day you intend to work on this."),
      ]))
    }

    // Likely-duplicate-title lookup: same lowercased title, different id,
    // not archived, status in (open, someday). Limit 3.
    let sql =
      "SELECT id, title, status, list_id "
      + "FROM tasks "
      + "WHERE LOWER(title) = ?1 "
      + "  AND id != ?2 "
      + "  AND archived_at IS NULL "
      + "  AND status IN (\(StatusName.activeStatusSqlList)) "
      + "ORDER BY created_at DESC, id ASC "
      + "LIMIT ?3"
    let rows = try Row.fetchAll(
      db, sql: sql,
      arguments: [
        title.lowercased(), taskId, 3,
      ])
    var duplicates: [JSONValue] = []
    for row in rows {
      let id: String = row[0]
      let dupTitle: String = row[1]
      let dupStatus: String = row[2]
      let listId: String? = row[3]
      duplicates.append(.object([
        "id": .string(id),
        "title": .string(dupTitle),
        "status": .string(dupStatus),
        "list_id": listId.map(JSONValue.string) ?? .null,
      ]))
    }
    if !duplicates.isEmpty {
      advice.append(.object([
        "code": .string("likely_duplicate_title"),
        "severity": .string("low"),
        "message": .string(
          "A task with the same title is already active."),
        "related_tasks": .array(duplicates),
      ]))
    }
    return advice
  }
}
