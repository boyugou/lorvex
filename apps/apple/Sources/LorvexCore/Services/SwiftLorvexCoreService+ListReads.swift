import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func loadLists() async throws -> ListCatalogSnapshot {
    try read { db in
      let rows = try ListRepo.getAllListsWithCounts(db)
      return ListCatalogSnapshot(lists: rows.map(SwiftLorvexListDeserializers.list))
    }
  }

  /// The archived lists (and their task counts) for the archived-lists view.
  /// Disjoint from ``loadLists()``, which returns only active lists.
  public func loadArchivedLists() async throws -> ListCatalogSnapshot {
    try read { db in
      let rows = try ListRepo.getListsWithCountsPage(db, limit: nil, scope: .archived).rows
      return ListCatalogSnapshot(lists: rows.map(SwiftLorvexListDeserializers.list))
    }
  }

  public func loadListDetail(id: LorvexList.ID, limit: Int, offset: Int) async throws
    -> ListDetailSnapshot
  {
    try read { db in
      guard let listRow = try ListRepo.getList(db, id: ListId(trusted: id)) else {
        throw LorvexCoreError.notFound(entity: .list, id: id)
      }
      let clampedLimit = min(max(1, limit), 500)
      // Bound offset so the UInt32 narrowing can't trap on a hostile value.
      let clampedOffset = min(max(0, offset), Int(UInt32.max))
      // The list-detail task list shows the working set, so a started
      // (in_progress) task in the list stays visible alongside open work.
      let query = TaskRepo.ListTasksQuery(
        listId: id,
        status: .actionable,
        limit: UInt32(clampedLimit),
        offset: UInt32(clampedOffset))
      let result = try TaskRepo.Read.listTasks(db, query: query)
      let tasks = try Self.enrich(db, rows: result.rows)
      let meta = Self.pagination(
        returned: tasks.count, totalMatching: Int(result.totalMatching),
        limit: clampedLimit, offset: clampedOffset)
      let counts = try Self.listCounts(db, id: id)
      return ListDetailSnapshot(
        list: SwiftLorvexListDeserializers.list(
          listRow,
          openCount: counts.open,
          completedCount: counts.completed,
          cancelledCount: counts.cancelled,
          totalCount: counts.total),
        tasks: tasks,
        totalMatching: Int(result.totalMatching),
        returned: meta.returned,
        limit: clampedLimit,
        offset: clampedOffset,
        nextOffset: meta.nextOffset,
        truncated: meta.truncated)
    }
  }

  public func getList(id: LorvexList.ID) async throws -> LorvexList {
    try read { db in
      guard let listRow = try ListRepo.getList(db, id: ListId(trusted: id)) else {
        throw LorvexCoreError.notFound(entity: .list, id: id)
      }
      let counts = try Self.listCounts(db, id: id)
      return SwiftLorvexListDeserializers.list(
        listRow, openCount: counts.open, totalCount: counts.total)
    }
  }

  public func getListHealthSnapshot() async throws -> ListHealthSnapshot {
    try read { db in
      let today = try WorkflowTimezone.todayYmdForConn(db)
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT l.id, l.name, l.color, l.icon,
            (SELECT COUNT(*) FROM tasks t WHERE t.list_id = l.id
               AND t.status IN (\(StatusName.actionableStatusSqlList))
               AND t.archived_at IS NULL) AS open_count,
            (SELECT COUNT(*) FROM tasks t WHERE t.list_id = l.id
               AND t.status IN (\(StatusName.actionableStatusSqlList))
               AND t.archived_at IS NULL AND t.due_date IS NOT NULL AND t.due_date < ?1) AS overdue_count,
            (SELECT COUNT(*) FROM tasks t WHERE t.list_id = l.id
               AND t.status IN (\(StatusName.actionableStatusSqlList))
               AND t.archived_at IS NULL AND t.due_date = ?1) AS due_today_count
          FROM lists l
          WHERE l.archived_at IS NULL
          ORDER BY open_count DESC, l.created_at ASC, l.id ASC
          """,
        arguments: [today])
      let entries = rows.map { row in
        ListHealthEntry(
          id: row["id"],
          name: row["name"],
          color: row["color"],
          icon: row["icon"],
          openCount: Int(row["open_count"] as Int64),
          overdueOpenCount: Int(row["overdue_count"] as Int64),
          dueTodayOpenCount: Int(row["due_today_count"] as Int64))
      }
      return ListHealthSnapshot(date: today, totalLists: entries.count, lists: entries)
    }
  }

  static func listCounts(
    _ db: Database,
    id: LorvexList.ID
  ) throws -> (open: Int, completed: Int, cancelled: Int, total: Int) {
    // `open` counts the actionable working set (open + in_progress) so a started
    // task keeps counting as active work — matching the list-detail task list
    // and the sidebar `open_count`. `completed` / `cancelled` stay exact.
    let openCount = try Int64.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM tasks WHERE list_id = ? "
        + "AND status IN (\(StatusName.actionableStatusSqlList)) AND archived_at IS NULL",
      arguments: [id]) ?? 0
    let completedCount = try Self.countTasks(db, listID: id, status: "completed")
    let cancelledCount = try Self.countTasks(db, listID: id, status: "cancelled")
    let totalCount = try Int64.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM tasks WHERE list_id = ? AND archived_at IS NULL",
      arguments: [id]) ?? 0
    return (
      open: Int(openCount),
      completed: Int(completedCount),
      cancelled: Int(cancelledCount),
      total: Int(totalCount)
    )
  }

  private static func countTasks(
    _ db: Database,
    listID: LorvexList.ID,
    status: String
  ) throws -> Int64 {
    try Int64.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM tasks WHERE list_id = ? AND status = ? AND archived_at IS NULL",
      arguments: [listID, status]) ?? 0
  }
}
