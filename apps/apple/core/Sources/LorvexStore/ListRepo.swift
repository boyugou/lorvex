import Foundation
import GRDB
import LorvexDomain

/// One row from the `lists` table. Field order matches the SELECT column list
/// used throughout this module so positional ``Row`` lookup stays straight.
public struct ListRow: Sendable, Equatable {
  public let id: String
  public let name: String
  public let color: String?
  public let icon: String?
  public let description: String?
  public let aiNotes: String?
  public let createdAt: SyncTimestamp
  public let updatedAt: SyncTimestamp
  public let version: String
  /// Soft-archive timestamp (raw column value); non-nil = the whole list is
  /// archived (hidden from the active catalog, history preserved).
  public let archivedAt: String?
  /// Synced manual display order in the list catalog.
  public let position: Int64
}

/// One list row enriched with per-status task counts. Together these support
/// both the "X open · N total" display and a list-as-project progress
/// bar (`completedCount` over `totalCount - cancelledCount`).
public struct ListWithCounts: Sendable, Equatable {
  public let list: ListRow
  /// Open, non-archived tasks assigned to this list.
  public let openCount: Int64
  /// Completed, non-archived tasks assigned to this list.
  public let completedCount: Int64
  /// Cancelled, non-archived tasks assigned to this list (excluded from the
  /// progress denominator so a cancelled task doesn't drag the project bar).
  public let cancelledCount: Int64
  /// All non-archived tasks assigned to this list, regardless of status.
  public let totalCount: Int64
}

/// A bounded page of ``ListWithCounts`` plus the unbounded match count.
public struct ListsWithCountsPage: Sendable, Equatable {
  public let rows: [ListWithCounts]
  public let totalMatching: Int64
}

/// Inputs to ``ListRepo/createListWithAiNotes(_:params:)``.
public struct ListCreateParams: Sendable {
  public let id: ListId
  public let name: String
  public let color: String?
  public let icon: String?
  public let description: String?
  public let aiNotes: String?
  public let archivedAt: String?
  public let position: Int64
  public let version: String

  public init(
    id: ListId,
    name: String,
    color: String? = nil,
    icon: String? = nil,
    description: String? = nil,
    aiNotes: String? = nil,
    archivedAt: String? = nil,
    position: Int64 = 0,
    version: String
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.icon = icon
    self.description = description
    self.aiNotes = aiNotes
    self.archivedAt = archivedAt
    self.position = position
    self.version = version
  }
}

/// Inputs to ``ListRepo/updateList(_:params:)``. Each `Optional` field
/// participates only when non-`nil`; `nil` means "leave column untouched".
/// For three-state semantics on nullable columns (set / clear / leave),
/// use ``ListUpdatePatch`` directly via ``ListRepo/updateListPatched(_:id:patch:version:now:)``.
public struct ListUpdateParams: Sendable {
  public let id: ListId
  public let name: String?
  public let color: String?
  public let icon: String?
  public let description: String?
  public let aiNotes: String?
  public let now: String
  public let version: String

  public init(
    id: ListId,
    name: String? = nil,
    color: String? = nil,
    icon: String? = nil,
    description: String? = nil,
    aiNotes: String? = nil,
    now: String,
    version: String
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.icon = icon
    self.description = description
    self.aiNotes = aiNotes
    self.now = now
    self.version = version
  }
}

/// Patch struct for ``ListRepo/updateListPatched(_:id:patch:version:now:)``.
///
/// `name` is `Optional<String>` because the column is NOT NULL in the schema;
/// the other four nullable columns use ``Patch`` for explicit three-state
/// PATCH semantics (`unset` skip, `clear` SQL NULL, `set` write value).
public struct ListUpdatePatch: Sendable {
  public var name: String?
  public var color: Patch<String>
  public var icon: Patch<String>
  public var description: Patch<String>
  public var aiNotes: Patch<String>

  public init(
    name: String? = nil,
    color: Patch<String> = .unset,
    icon: Patch<String> = .unset,
    description: Patch<String> = .unset,
    aiNotes: Patch<String> = .unset
  ) {
    self.name = name
    self.color = color
    self.icon = icon
    self.description = description
    self.aiNotes = aiNotes
  }
}

/// `lists`-table read/write operations.
public enum ListRepo {

  // ---------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------

  /// Column list for SELECT/RETURNING queries, in the order ``rowToListRow(_:)``
  /// reads (`position` last, index 10).
  static let listColumns =
    "id, name, color, icon, description, ai_notes, created_at, updated_at, version, archived_at, position"

  /// The subset INSERT statements write, including the synced archive/order
  /// columns so import/export can round-trip them explicitly.
  static let listInsertColumns =
    "id, name, color, icon, description, ai_notes, created_at, updated_at, version, archived_at, position"

  /// Same as ``listColumns``, table-qualified for JOIN-shaped queries.
  static let listColumnsQualified =
    "l.id, l.name, l.color, l.icon, l.description, l.ai_notes, l.created_at, l.updated_at, l.version, l.archived_at, l.position"

  static func rowToListRow(_ row: Row) throws -> ListRow {
    let rawCreated: String = row[6]
    let rawUpdated: String = row[7]
    guard let createdAt = SyncTimestamp.parse(rawCreated) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "lists.created_at is not a canonical sync timestamp: \(rawCreated)")
    }
    guard let updatedAt = SyncTimestamp.parse(rawUpdated) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "lists.updated_at is not a canonical sync timestamp: \(rawUpdated)")
    }
    return ListRow(
      id: row[0],
      name: row[1],
      color: row[2],
      icon: row[3],
      description: row[4],
      aiNotes: row[5],
      createdAt: createdAt,
      updatedAt: updatedAt,
      version: row[8],
      archivedAt: row[9],
      position: row[10])
  }

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  /// Look up one list by id. Returns `nil` if no row matches.
  public static func getList(_ db: Database, id: ListId) throws -> ListRow? {
    let row = try Row.fetchOne(
      db,
      sql: "SELECT \(listColumns) FROM lists WHERE id = ?",
      arguments: [id.rawValue])
    guard let row else { return nil }
    return try rowToListRow(row)
  }

  /// Count every non-archived task still assigned to `listId` (status
  /// independent: open / someday / completed / cancelled all count; only Trash,
  /// `archived_at IS NOT NULL`, is excluded). This is the gate before deleting
  /// a list.
  ///
  /// `delete_list` is a hard delete for genuinely empty lists. A list that still
  /// holds completed/cancelled history is preserved by ARCHIVING the whole list
  /// (``archiveList(_:id:version:now:)``) — which keeps those tasks under the
  /// list's name — rather than deleting it and scattering them to inbox.
  public static func countAssignedTasksInList(
    _ db: Database, listId: ListId
  ) throws -> Int64 {
    try Int64.fetchOne(
      db,
      sql: """
        SELECT COUNT(*) FROM tasks \
        WHERE list_id = ? AND archived_at IS NULL
        """,
      arguments: [listId.rawValue]) ?? 0
  }

  /// Set/clear a whole list's `archived_at` (soft-archive), bumping `version`
  /// and `updated_at`. Returns the updated row, or `nil` if no list matches.
  /// Archiving keeps the list and all its tasks intact (completed history under
  /// the list name); it just hides the list from the active catalog.
  @discardableResult
  public static func setListArchived(
    _ db: Database, id: ListId, archivedAt: String?, version: String, now: String
  ) throws -> ListRow? {
    let row = try Row.fetchOne(
      db,
      sql: """
        UPDATE lists SET archived_at = ?, version = ?, updated_at = ? \
        WHERE id = ? AND ? > lists.version RETURNING \(listColumns)
        """,
      arguments: [archivedAt, version, now, id.rawValue, version])
    if let row { return try rowToListRow(row) }
    // Zero rows: a missing list returns nil (the surface maps it to notFound);
    // an existing row means the LWW gate rejected a stale version. The gate
    // matches the other list/tag writers so a stale archive can't clobber a
    // newer peer write.
    let exists =
      try Bool.fetchOne(
        db, sql: "SELECT 1 FROM lists WHERE id = ?", arguments: [id.rawValue]) != nil
    if exists {
      throw StoreError.staleVersion(entity: EntityKind.list.rawValue, id: id.rawValue)
    }
    return nil
  }

  // ---------------------------------------------------------------------
  // Writes — create
  // ---------------------------------------------------------------------

  /// Create a new list without `ai_notes` and return the inserted row.
  @discardableResult
  public static func createList(
    _ db: Database,
    id: ListId,
    name: String,
    color: String? = nil,
    icon: String? = nil,
    description: String? = nil,
    version: String
  ) throws -> ListRow {
    try createListWithAiNotes(
      db,
      params: ListCreateParams(
        id: id, name: name, color: color, icon: icon, description: description,
        aiNotes: nil, version: version))
  }

  /// Create a new list with an optional `ai_notes` field and return the
  /// inserted row.
  ///
  /// `created_at` / `updated_at` are stamped from ``SyncTimestamp/now()`` in
  /// the canonical millisecond-`Z` form so they sort consistently across
  /// devices regardless of which device wrote the row.
  @discardableResult
  public static func createListWithAiNotes(
    _ db: Database, params: ListCreateParams
  ) throws -> ListRow {
    let now = SyncTimestamp.now().asString
    let row = try Row.fetchOne(
      db,
      sql: """
        INSERT INTO lists (\(listInsertColumns)) \
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
        RETURNING \(listColumns)
        """,
      arguments: [
        params.id.rawValue,
        params.name,
        params.color,
        params.icon,
        params.description,
        params.aiNotes,
        now,  // created_at
        now,  // updated_at
        params.version,
        params.archivedAt,
        params.position,
      ])
    guard let row else {
      throw DatabaseError(
        resultCode: .SQLITE_INTERNAL,
        message: "INSERT INTO lists ... RETURNING produced no row")
    }
    return try rowToListRow(row)
  }

  /// Id-preserving idempotent upsert for data import/restore.
  ///
  /// Inserts the list at the caller-supplied `id`, or overwrites the existing
  /// row's columns when that id is already present (`ON CONFLICT(id) DO
  /// UPDATE`). LWW-gated on `excluded.version > lists.version`, matching the
  /// sibling import upserts (tag / calendar / task-metadata): an import that
  /// loses the gate against a strictly-newer local row throws
  /// ``StoreError/staleVersion(entity:id:)`` so the write-surface retry advances
  /// the clock and re-runs at a dominating version — so a re-import still
  /// overwrites, but an import can never REGRESS a row a peer stamped with a
  /// future HLC. `created_at` is preserved on conflict (the original creation
  /// instant survives a re-import); `name`, the optional columns, archive/order
  /// metadata, `updated_at`, and `version` are rewritten when the gate passes.
  @discardableResult
  public static func upsertListForImport(
    _ db: Database, params: ListCreateParams, now: String
  ) throws -> ListRow {
    try db.execute(
      sql: """
        INSERT INTO lists (\(listInsertColumns)) \
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
        ON CONFLICT(id) DO UPDATE SET \
        name = excluded.name, color = excluded.color, icon = excluded.icon, \
        description = excluded.description, ai_notes = excluded.ai_notes, \
        archived_at = excluded.archived_at, position = excluded.position, \
        updated_at = excluded.updated_at, version = excluded.version \
        WHERE excluded.version > lists.version
        """,
      arguments: [
        params.id.rawValue,
        params.name,
        params.color,
        params.icon,
        params.description,
        params.aiNotes,
        now,  // created_at (kept on conflict)
        now,  // updated_at
        params.version,
        params.archivedAt,
        params.position,
      ])
    if db.changesCount == 0 {
      // The INSERT hit an existing id and the LWW gate refused a stale version.
      throw StoreError.staleVersion(entity: EntityKind.list.rawValue, id: params.id.rawValue)
    }
    guard let row = try getList(db, id: params.id) else {
      throw DatabaseError(
        resultCode: .SQLITE_INTERNAL,
        message: "INSERT INTO lists ... ON CONFLICT produced no row")
    }
    return row
  }

  // ---------------------------------------------------------------------
  // Writes — update
  // ---------------------------------------------------------------------

  /// Update a list; only non-`nil` fields are modified. Delegates to
  /// ``updateListPatched(_:id:patch:version:now:)``.
  public static func updateList(
    _ db: Database, params: ListUpdateParams
  ) throws {
    let patch = ListUpdatePatch(
      name: params.name,
      color: params.color.map { Patch.set($0) } ?? .unset,
      icon: params.icon.map { Patch.set($0) } ?? .unset,
      description: params.description.map { Patch.set($0) } ?? .unset,
      aiNotes: params.aiNotes.map { Patch.set($0) } ?? .unset)
    try updateListPatched(
      db, id: params.id, patch: patch, version: params.version, now: params.now)
  }

  /// Update a list using a typed patch with three-state PATCH semantics.
  ///
  /// LWW-gated: the UPDATE proceeds only if the supplied `version` is
  /// strictly greater than the row's stored `version`. An empty patch
  /// (every column is ``Patch/unset`` and `name` is `nil`) is a successful
  /// no-op and does NOT exercise the LWW gate. Otherwise, when the gate
  /// rejects the write, throws ``StoreError/staleVersion(entity:id:)``.
  ///
  /// `version` and `updated_at` are always written alongside the SET clause
  /// so sync LWW semantics are preserved on every update.
  public static func updateListPatched(
    _ db: Database,
    id: ListId,
    patch: ListUpdatePatch,
    version: String,
    now: String
  ) throws {
    var setClauses: [String] = []
    var arguments: [DatabaseValueConvertible?] = []

    if let name = patch.name {
      setClauses.append("name = ?")
      arguments.append(name)
    }
    if patch.color.isSetOrClear {
      setClauses.append("color = ?")
      arguments.append(patch.color.asBindValue)
    }
    if patch.icon.isSetOrClear {
      setClauses.append("icon = ?")
      arguments.append(patch.icon.asBindValue)
    }
    if patch.description.isSetOrClear {
      setClauses.append("description = ?")
      arguments.append(patch.description.asBindValue)
    }
    if patch.aiNotes.isSetOrClear {
      setClauses.append("ai_notes = ?")
      arguments.append(patch.aiNotes.asBindValue)
    }

    if setClauses.isEmpty {
      // Empty patch is a no-op — do not run the UPDATE, which would always
      // match zero rows and be indistinguishable from a stale-version miss.
      return
    }

    setClauses.append("version = ?")
    arguments.append(version)
    setClauses.append("updated_at = ?")
    arguments.append(now)

    // WHERE arguments: id, then version for the LWW gate.
    arguments.append(id.rawValue)
    arguments.append(version)

    let sql = """
      UPDATE lists SET \(setClauses.joined(separator: ", ")) \
      WHERE id = ? AND ? > lists.version
      """
    try db.execute(sql: sql, arguments: StatementArguments(arguments))
    if db.changesCount == 0 {
      // Disambiguate a missing list from a stale-version LWW rejection so the
      // surface layer's not-found handling stays reachable (same as TagRepo).
      let exists =
        try Bool.fetchOne(
          db, sql: "SELECT 1 FROM lists WHERE id = ?", arguments: [id.rawValue]) != nil
      if !exists {
        throw StoreError.notFound(entity: EntityKind.list.rawValue, id: id.rawValue)
      }
      throw StoreError.staleVersion(entity: EntityKind.list.rawValue, id: id.rawValue)
    }
  }

  // ---------------------------------------------------------------------
  // Writes — delete
  // ---------------------------------------------------------------------

  /// Delete a list unconditionally. Returns the affected-row count
  /// (0 when no matching row existed; otherwise 1).
  @discardableResult
  public static func deleteList(_ db: Database, id: ListId) throws -> Int {
    try db.execute(sql: "DELETE FROM lists WHERE id = ?", arguments: [id.rawValue])
    return db.changesCount
  }

  // ---------------------------------------------------------------------
  // Aggregate reads
  // ---------------------------------------------------------------------

  /// All lists with `(open, total)` task counts, ordered by
  /// `(created_at ASC, id ASC)`. Counts use correlated subqueries so each
  /// one stays index-bound on `(list_id, status)` rather than scanning the
  /// tasks table.
  public static func getAllListsWithCounts(
    _ db: Database
  ) throws -> [ListWithCounts] {
    try getListsWithCountsPage(db, limit: nil).rows
  }

  /// Which lists a counts page covers by archive state. The active catalog
  /// (sidebar, pickers, health) is `.active`; the archived view is `.archived`.
  public enum ListArchiveScope: Sendable {
    case active
    case archived

    var whereClause: String {
      switch self {
      case .active: "WHERE l.archived_at IS NULL"
      case .archived: "WHERE l.archived_at IS NOT NULL"
      }
    }

    var countWhereClause: String {
      switch self {
      case .active: "WHERE archived_at IS NULL"
      case .archived: "WHERE archived_at IS NOT NULL"
      }
    }
  }

  public static func getListsWithCountsPage(
    _ db: Database, limit: Int?, scope: ListArchiveScope = .active
  ) throws -> ListsWithCountsPage {
    let totalMatching =
      try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM lists \(scope.countWhereClause)") ?? 0

    var sql = """
      SELECT \(listColumnsQualified), \
      (SELECT COUNT(*) FROM tasks t \
       WHERE t.list_id = l.id AND t.status IN (\(StatusName.actionableStatusSqlList)) AND t.archived_at IS NULL) AS open_count, \
      (SELECT COUNT(*) FROM tasks t \
       WHERE t.list_id = l.id AND t.status = 'completed' AND t.archived_at IS NULL) AS completed_count, \
      (SELECT COUNT(*) FROM tasks t \
       WHERE t.list_id = l.id AND t.status = 'cancelled' AND t.archived_at IS NULL) AS cancelled_count, \
      (SELECT COUNT(*) FROM tasks t \
       WHERE t.list_id = l.id AND t.archived_at IS NULL) AS total_count \
      FROM lists l \
      \(scope.whereClause) \
      ORDER BY l.position ASC, l.created_at ASC, l.id ASC
      """
    var args: StatementArguments = []
    if let limit {
      sql += " LIMIT ?"
      args = [limit]
    }
    let rows = try Row.fetchAll(db, sql: sql, arguments: args)
    // `position` is column 10 (see listColumns); the four counts follow at 11-14.
    let mapped: [ListWithCounts] = try rows.map { row in
      let list = try rowToListRow(row)
      let openCount: Int64 = row[11]
      let completedCount: Int64 = row[12]
      let cancelledCount: Int64 = row[13]
      let totalCount: Int64 = row[14]
      return ListWithCounts(
        list: list,
        openCount: openCount,
        completedCount: completedCount,
        cancelledCount: cancelledCount,
        totalCount: totalCount)
    }
    return ListsWithCountsPage(rows: mapped, totalMatching: totalMatching)
  }
}
