import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// A plain data struct representing a row from `task_checklist_items`.
/// Adapters convert this into their own representation (e.g. a typed task DTO
/// or a JSON value).
public struct ChecklistItemData: Sendable, Equatable {
  public let id: String
  public let taskId: String
  public let position: Int64
  public let text: String
  public let completedAt: String?
  public let version: String
  public let createdAt: String
  public let updatedAt: String

  public init(
    id: String, taskId: String, position: Int64, text: String,
    completedAt: String?, version: String, createdAt: String, updatedAt: String
  ) {
    self.id = id
    self.taskId = taskId
    self.position = position
    self.text = text
    self.completedAt = completedAt
    self.version = version
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// Derived fields computed for a single task during a batch enrichment pass.
/// Each adapter folds these back into its own task representation.
public struct Enrichment: Sendable, Equatable {
  public var tags: [String]?
  public var dependsOn: [String]?
  public var checklistItems: [ChecklistItemData]?
  public var lateness: TaskLateness?

  public init(
    tags: [String]? = nil, dependsOn: [String]? = nil,
    checklistItems: [ChecklistItemData]? = nil, lateness: TaskLateness? = nil
  ) {
    self.tags = tags
    self.dependsOn = dependsOn
    self.checklistItems = checklistItems
    self.lateness = lateness
  }
}

/// Shared task enrichment pipeline.
public enum TaskEnrichment {
  /// One entry in the batch: `(taskId, plannedDate, dueDate)`.
  public struct DateEntry: Sendable {
    public let taskId: String
    public let plannedDate: IsoDate.YMD?
    public let dueDate: IsoDate.YMD?
    public init(taskId: String, plannedDate: IsoDate.YMD?, dueDate: IsoDate.YMD?) {
      self.taskId = taskId
      self.plannedDate = plannedDate
      self.dueDate = dueDate
    }
  }

  /// Compute every enrichment (tags, deps, checklist items, lateness) for the
  /// supplied tasks in one batch pass per derived field. The return map is
  /// keyed on `taskId`; absent keys mean "no enrichments applied"
  /// (default-zeroed ``Enrichment``).
  public static func computeEnrichments(
    _ db: Database, dates: [DateEntry], today: String
  ) throws -> [String: Enrichment] {
    var out: [String: Enrichment] = [:]
    out.reserveCapacity(dates.count)
    if dates.isEmpty { return out }

    let taskIds = dates.map(\.taskId)

    let todayDate: IsoDate.YMD
    switch IsoDate.parseIsoDate(today) {
    case .success(let ymd): todayDate = ymd
    case .failure(let error):
      throw StoreError.validation(
        "invalid today date '\(today)' for lateness enrichment: \(error.description)")
    }

    for entry in dates {
      if let lateness = Query.deriveOpenTaskLateness(
        plannedDate: entry.plannedDate, dueDate: entry.dueDate, asOfDate: todayDate)
      {
        out[entry.taskId, default: Enrichment()].lateness = lateness
      }
    }

    // Tags: grouped in Swift from an ORDER BY'd scan so the per-task order is
    // deterministic and matches the write-echo read (`findTaskTags`): the
    // order the tags were added, alphabetical (`lookup_key`) within one write
    // (same-transaction edges share `created_at`). An unordered aggregate
    // (`json_group_array`) would surface tags in arbitrary scan order.
    let placeholders = Sql.sqlInPlaceholders(taskIds.count, 0)
    let tagArgs = StatementArguments(taskIds)
    let tagSql =
      "SELECT tt.task_id, t.display_name "
      + "FROM task_tags tt JOIN tags t ON t.id = tt.tag_id "
      + "WHERE tt.task_id IN (\(placeholders)) "
      + "ORDER BY tt.created_at ASC, t.lookup_key ASC"
    for row in try Row.fetchAll(db, sql: tagSql, arguments: tagArgs) {
      let tid: String = row[0]
      let name: String = row[1]
      out[tid, default: Enrichment()].tags = (out[tid]?.tags ?? []) + [name]
    }

    // depends_on
    let depsSql =
      "SELECT task_id, json_group_array(depends_on_task_id) as deps "
      + "FROM task_dependencies WHERE task_id IN (\(placeholders)) "
      + "GROUP BY task_id"
    for row in try Row.fetchAll(db, sql: depsSql, arguments: StatementArguments(taskIds)) {
      let tid: String = row[0]
      let json: String = row[1]
      let parsed = try decodeJsonStringArray(json)
      out[tid, default: Enrichment()].dependsOn = parsed
    }

    // Checklist items
    let checklistSql =
      "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at "
      + "FROM task_checklist_items WHERE task_id IN (\(placeholders)) "
      + "ORDER BY task_id ASC, position ASC, created_at ASC, id ASC"
    for row in try Row.fetchAll(db, sql: checklistSql, arguments: StatementArguments(taskIds)) {
      let item = ChecklistItemData(
        id: row[0], taskId: row[1], position: row[2], text: row[3],
        completedAt: row[4], version: row[5], createdAt: row[6], updatedAt: row[7])
      let key = item.taskId
      var current = out[key] ?? Enrichment()
      if current.checklistItems == nil {
        current.checklistItems = []
      }
      current.checklistItems?.append(item)
      out[key] = current
    }

    return out
  }

  /// SQLite's `json_group_array` returns a JSON array of strings. Decode it
  /// using `JSONValue`'s canonical parser; surface a serialization error on
  /// any structural deviation so the contract matches decoding a JSON string
  /// array.
  static func decodeJsonStringArray(_ raw: String) throws -> [String] {
    guard let parsed = JSONValue.parse(raw) else {
      throw StoreError.serialization("invalid json_group_array output: \(raw)")
    }
    guard case .array(let elems) = parsed else {
      throw StoreError.serialization("expected json array, got: \(raw)")
    }
    var out: [String] = []
    out.reserveCapacity(elems.count)
    for elem in elems {
      guard case .string(let s) = elem else {
        throw StoreError.serialization("expected json array of strings, got: \(raw)")
      }
      out.append(s)
    }
    return out
  }
}
