import Foundation
import GRDB
import LorvexDomain

/// Query parameters for ``AiChangelogQueryRepo/listAiChangelog(_:query:)``.
///
/// `limit` is required and must be strictly positive — ``init(limit:)`` traps
/// non-positive values rather than silently producing empty result sets via
/// `LIMIT 0`.
public struct AiChangelogQuery: Sendable, Equatable {
  public let limit: Int
  public let entityType: EntityKind?
  public let operation: String?
  public let entityId: String?
  public let since: String?

  public init(
    limit: Int,
    entityType: EntityKind? = nil,
    operation: String? = nil,
    entityId: String? = nil,
    since: String? = nil
  ) {
    precondition(limit > 0, "AiChangelogQuery.limit must be > 0")
    self.limit = limit
    self.entityType = entityType
    self.operation = operation
    self.entityId = entityId
    self.since = since
  }
}

/// One row returned by ``AiChangelogQueryRepo/listAiChangelog(_:query:)``.
public struct AiChangelogEntry: Sendable, Equatable {
  public let id: String
  public let timestamp: String
  public let operation: String
  public let entityType: EntityKind
  public let entityId: String?
  public let summary: String
  public let mcpTool: String?
  /// Actor that wrote the row (e.g. "assistant"); nil when unrecorded.
  public let initiatedBy: String?
  /// True when the row recorded the entity's state before the change
  /// (`before_json`), the state an undo restores.
  public let hasBefore: Bool
  /// True when the row recorded the entity's state after the change.
  public let hasAfter: Bool
  /// The current title of the task the row is about, for a list that names
  /// the task in its own words; nil for other entity kinds, a batch, or a task
  /// that no longer exists.
  public let entityTitle: String?
}

/// Shared SQL fragments for AI changelog actor filtering.
///
/// `ai_changelog` is the assistant activity surface. Human/user/system/manual
/// rows can exist from imports or diagnostics; assistant-facing reads
/// and retention all agree on the same filter so the row sets stay aligned.
public enum AiChangelogActorFilter {
  static let nonAssistantActorsSql = "'human', 'system', 'user', 'manual'"

  /// Predicate for bare-table queries.
  public static func assistantActorFilterSql() -> String {
    filterSql(for: "initiated_by")
  }

  /// Predicate for an aliased `ai_changelog` table, e.g. `ac.initiated_by`.
  /// Alias must be an ASCII identifier — preconditioned because the alias is
  /// code-owned, never user input.
  public static func assistantActorFilterSql(forAlias alias: String) -> String {
    assertSafeSqlAlias(alias)
    return filterSql(for: "\(alias).initiated_by")
  }

  static func filterSql(for column: String) -> String {
    "(\(column) IS NULL OR \(column) NOT IN (\(nonAssistantActorsSql)))"
  }

  static func assertSafeSqlAlias(_ alias: String) {
    precondition(!alias.isEmpty, "ai_changelog SQL alias must not be empty")
    let scalars = alias.unicodeScalars
    let first = scalars.first!
    precondition(
      first == "_" || (first.isASCII && CharacterSet.letters.contains(first)),
      "ai_changelog SQL alias must start with an ASCII identifier character")
    for s in scalars {
      precondition(
        s == "_" || (s.isASCII && (CharacterSet.letters.contains(s) || CharacterSet.decimalDigits.contains(s))),
        "ai_changelog SQL alias must be an ASCII identifier")
    }
  }
}

/// `ai_changelog`-table read operations.
public enum AiChangelogQueryRepo {

  /// List AI-originated changelog entries matching `query`, newest first.
  ///
  /// When `entityId` is set the query unions two branches: a scalar
  /// `entity_id = ?` match and a `ai_changelog_entities` registry join for
  /// batch operations. Shared filters (entity_type / operation / since /
  /// initiated_by) apply identically to both branches; outer ORDER BY +
  /// LIMIT bound the merged set.
  public static func listAiChangelog(
    _ db: Database, query: AiChangelogQuery
  ) throws -> [AiChangelogEntry] {
    let shared = buildSharedFilterClauses(query)
    if let entityId = query.entityId {
      return try listWithEntityId(db, query: query, entityId: entityId, shared: shared)
    }
    return try listWithoutEntityId(db, query: query, shared: shared)
  }

  // -- shared filter construction -----------------------------------------

  /// The filters every list branch applies, written against the changelog
  /// alias `ac` (each branch joins the task title onto `ac`), with the bound
  /// values in placeholder order.
  struct SharedFilterClauses {
    let aliased: String
    let values: [DatabaseValueConvertible]
  }

  static func buildSharedFilterClauses(_ query: AiChangelogQuery) -> SharedFilterClauses {
    var aliased: [String] = [AiChangelogActorFilter.assistantActorFilterSql(forAlias: "ac")]
    var values: [DatabaseValueConvertible] = []

    if let entityType = query.entityType {
      aliased.append("ac.entity_type = ?")
      values.append(entityType.rawValue)
    }
    if let op = query.operation {
      aliased.append("ac.operation = ?")
      values.append(op)
    }
    if let since = query.since {
      aliased.append("ac.timestamp > ?")
      values.append(since)
    }
    return SharedFilterClauses(aliased: aliased.joined(separator: " AND "), values: values)
  }

  static func listWithEntityId(
    _ db: Database,
    query: AiChangelogQuery,
    entityId: String,
    shared: SharedFilterClauses
  ) throws -> [AiChangelogEntry] {
    let sql = """
      SELECT id, timestamp, operation, entity_type, entity_id, summary, mcp_tool, initiated_by, \
             has_before, has_after, entity_title \
      FROM ( \
         SELECT ac.id, ac.timestamp, ac.operation, ac.entity_type, ac.entity_id, \
                ac.summary, ac.mcp_tool, ac.initiated_by, \
                ac.before_json IS NOT NULL AS has_before, ac.after_json IS NOT NULL AS has_after, \
                t.title AS entity_title \
         FROM ai_changelog ac \
         \(taskTitleJoinSql) \
         WHERE ac.entity_id = ? AND \(shared.aliased) \
         UNION \
         SELECT ac.id, ac.timestamp, ac.operation, ac.entity_type, ac.entity_id, \
                ac.summary, ac.mcp_tool, ac.initiated_by, \
                ac.before_json IS NOT NULL, ac.after_json IS NOT NULL, \
                t.title \
         FROM ai_changelog ac \
         JOIN ai_changelog_entities ace ON ace.changelog_id = ac.id \
         \(taskTitleJoinSql) \
         WHERE ace.entity_id = ? AND \(shared.aliased) \
      ) \
      ORDER BY timestamp DESC, id DESC \
      LIMIT ?
      """
    var args: [DatabaseValueConvertible?] = []
    args.append(entityId)
    args.append(contentsOf: shared.values.map { $0 as DatabaseValueConvertible? })
    args.append(entityId)
    args.append(contentsOf: shared.values.map { $0 as DatabaseValueConvertible? })
    args.append(query.limit)
    return try runChangelogQuery(db, sql: sql, arguments: StatementArguments(args))
  }

  static func listWithoutEntityId(
    _ db: Database,
    query: AiChangelogQuery,
    shared: SharedFilterClauses
  ) throws -> [AiChangelogEntry] {
    let sql = """
      SELECT ac.id, ac.timestamp, ac.operation, ac.entity_type, ac.entity_id, \
             ac.summary, ac.mcp_tool, ac.initiated_by, \
             ac.before_json IS NOT NULL, ac.after_json IS NOT NULL, t.title \
      FROM ai_changelog ac \
      \(taskTitleJoinSql) \
      WHERE \(shared.aliased) \
      ORDER BY ac.timestamp DESC, ac.id DESC \
      LIMIT ?
      """
    var args: [DatabaseValueConvertible?] = shared.values.map { $0 as DatabaseValueConvertible? }
    args.append(query.limit)
    return try runChangelogQuery(db, sql: sql, arguments: StatementArguments(args))
  }

  static func runChangelogQuery(
    _ db: Database, sql: String, arguments: StatementArguments
  ) throws -> [AiChangelogEntry] {
    let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
    return try rows.map(entry(from:))
  }

  /// Joins the task a row is about (alias `t`) onto the changelog (alias
  /// `ac`), so its current title can be selected; other entity kinds and
  /// vanished tasks join nothing.
  static let taskTitleJoinSql =
    "LEFT JOIN tasks t ON ac.entity_type = '\(EntityName.task)' AND t.id = ac.entity_id"

  /// One list row from the shared column order: id, timestamp, operation,
  /// entity_type, entity_id, summary, mcp_tool, initiated_by, has_before,
  /// has_after, entity_title.
  static func entry(from row: Row) throws -> AiChangelogEntry {
    let rawEntityType: String = row[3]
    guard let entityType = EntityKind.parse(rawEntityType) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message:
          "ai_changelog.entity_type contains unknown entity kind \"\(rawEntityType)\"")
    }
    return AiChangelogEntry(
      id: row[0],
      timestamp: row[1],
      operation: row[2],
      entityType: entityType,
      entityId: row[4],
      summary: row[5],
      mcpTool: row[6],
      initiatedBy: row[7],
      hasBefore: row[8],
      hasAfter: row[9],
      entityTitle: row[10])
  }
}
