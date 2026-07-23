import Foundation
import GRDB
import LorvexDomain

extension TaskRepo {
  /// Builds a subgraph of tasks linked through `task_dependencies`, with
  /// computed annotations (roots, blocked, leaf_blockers).
  public enum DependencyGraph {

    /// A node in the dependency graph. `dueDate` / `plannedDate` are typed
    /// ``LorvexDate`` (`YYYY-MM-DD`).
    public struct GraphNode: Sendable, Equatable {
      public let id: String
      public let title: String
      public let status: String
      public let priority: Int64?
      public let dueDate: LorvexDate?
      public let plannedDate: LorvexDate?
      public let listId: String
    }

    public struct GraphEdge: Sendable, Equatable {
      public let taskId: String
      public let dependsOnTaskId: String
    }

    /// Parameters for scoping and capping the dependency graph query.
    public struct Params: Sendable, Equatable {
      /// Center the graph on this task (shows its direct neighbourhood).
      public var taskId: String?
      /// Scope nodes to a specific list.
      public var listId: String?
      /// Include completed/cancelled tasks in the graph.
      public var includeInactive: Bool
      /// Maximum number of nodes to return.
      public var limitNodes: UInt32
      /// Maximum number of edges to return.
      public var limitEdges: UInt32

      public init(
        taskId: String? = nil,
        listId: String? = nil,
        includeInactive: Bool = false,
        limitNodes: UInt32 = 0,
        limitEdges: UInt32 = 0
      ) {
        self.taskId = taskId
        self.listId = listId
        self.includeInactive = includeInactive
        self.limitNodes = limitNodes
        self.limitEdges = limitEdges
      }
    }

    /// The computed dependency graph result.
    public struct Result: Sendable, Equatable {
      public let nodes: [GraphNode]
      public let edges: [GraphEdge]
      /// Tasks with no incoming dependencies (nothing they depend on).
      public let roots: [String]
      /// Tasks whose dependencies include unmet (open/someday) tasks.
      public let blocked: [String]
      /// Tasks that block others but are not themselves blocked.
      public let leafBlockers: [String]
      public let truncated: Bool
    }

    static func nodeFromRow(_ row: Row) throws -> GraphNode {
      let dueRaw: String? = row[4]
      let plannedRaw: String? = row[5]
      return GraphNode(
        id: row[0],
        title: row[1],
        status: row[2],
        priority: row[3],
        dueDate: try TaskRepo.parseOptionalDate(dueRaw, column: "due_date"),
        plannedDate: try TaskRepo.parseOptionalDate(plannedRaw, column: "planned_date"),
        listId: row[6])
    }

    /// `active = "open or someday"` filter fragment for the edge SQL, or the
    /// archived-only filter when `includeInactive` is true.
    private static func activeFilter(_ includeInactive: Bool) -> String {
      let base = " AND t1.archived_at IS NULL AND t2.archived_at IS NULL"
      if includeInactive {
        return base
      }
      return base
        + " AND t1.status IN (\(StatusName.activeStatusSqlList))"
        + " AND t2.status IN (\(StatusName.activeStatusSqlList))"
    }

    /// Edge SQL for the requested shape. Eight variants: 4 scope branches
    /// (`task_id` × `list_id`) × 2 `include_inactive` toggles. Centered
    /// queries split the OR-predicate into a `UNION ALL` of two single-index
    /// legs.
    private static func edgesSql(
      hasTaskId: Bool, hasListId: Bool, includeInactive: Bool
    ) -> String {
      let active = activeFilter(includeInactive)
      switch (hasTaskId, hasListId) {
      case (true, true):
        return """
          SELECT td.task_id, td.depends_on_task_id \
          FROM task_dependencies td \
          JOIN tasks t1 ON td.task_id = t1.id \
          JOIN tasks t2 ON td.depends_on_task_id = t2.id \
          WHERE td.task_id = :center_id\(active) \
            AND EXISTS (SELECT 1 FROM tasks tc WHERE tc.id = :center_id AND tc.list_id = :list_id AND tc.archived_at IS NULL) \
          UNION ALL \
          SELECT td.task_id, td.depends_on_task_id \
          FROM task_dependencies td \
          JOIN tasks t1 ON td.task_id = t1.id \
          JOIN tasks t2 ON td.depends_on_task_id = t2.id \
          WHERE td.depends_on_task_id = :center_id\(active) \
            AND EXISTS (SELECT 1 FROM tasks tc WHERE tc.id = :center_id AND tc.list_id = :list_id AND tc.archived_at IS NULL) \
          ORDER BY 1 ASC, 2 ASC \
          LIMIT :edge_fetch_limit
          """
      case (true, false):
        return """
          SELECT td.task_id, td.depends_on_task_id \
          FROM task_dependencies td \
          JOIN tasks t1 ON td.task_id = t1.id \
          JOIN tasks t2 ON td.depends_on_task_id = t2.id \
          WHERE td.task_id = :center_id\(active) \
          UNION ALL \
          SELECT td.task_id, td.depends_on_task_id \
          FROM task_dependencies td \
          JOIN tasks t1 ON td.task_id = t1.id \
          JOIN tasks t2 ON td.depends_on_task_id = t2.id \
          WHERE td.depends_on_task_id = :center_id\(active) \
          ORDER BY 1 ASC, 2 ASC \
          LIMIT :edge_fetch_limit
          """
      case (false, true):
        return """
          SELECT td.task_id, td.depends_on_task_id \
          FROM task_dependencies td \
          JOIN tasks t1 ON td.task_id = t1.id \
          JOIN tasks t2 ON td.depends_on_task_id = t2.id \
          WHERE (t1.list_id = :list_id OR t2.list_id = :list_id)\(active) \
          ORDER BY td.task_id ASC, td.depends_on_task_id ASC \
          LIMIT :edge_fetch_limit
          """
      case (false, false):
        return """
          SELECT td.task_id, td.depends_on_task_id \
          FROM task_dependencies td \
          JOIN tasks t1 ON td.task_id = t1.id \
          JOIN tasks t2 ON td.depends_on_task_id = t2.id \
          WHERE 1=1\(active) \
          ORDER BY td.task_id ASC, td.depends_on_task_id ASC \
          LIMIT :edge_fetch_limit
          """
      }
    }

    /// Single-row SELECT used when the center task has no edges in the
    /// requested scope. Both filters are bound as predicates so the
    /// statement is shape-stable across `(list_id present?, include_inactive?)`.
    private static func centerNodeSql() -> String {
      """
      SELECT t.id, t.title, t.status, t.priority, t.due_date, t.planned_date, t.list_id \
      FROM tasks t \
      WHERE t.id = ?1 \
        AND t.archived_at IS NULL \
        AND (?2 IS NULL OR t.list_id = ?2) \
        AND (?3 = 1 OR t.status IN (\(StatusName.activeStatusSqlList)))
      """
    }

    /// Build and return a dependency graph, scoped first then capped.
    ///
    /// Strategy: build the scoped edge set in SQL with LIMIT, fetch only the
    /// nodes the retained edges reference, apply the node cap (priority-ranked,
    /// center pinned to position 0 via a leading CASE), then compute
    /// `roots` / `blocked` / `leafBlockers` by iterating `nodes` in their
    /// SQL-determined order so the output is deterministic.
    public static func getDependencyGraph(
      _ db: Database, params: Params
    ) throws -> Result {
      let limitNodes = Int(max(params.limitNodes, 1))
      let limitEdges = Int(max(params.limitEdges, 1))
      let edgeFetchLimit = Int64(limitEdges + 1)

      // Step 1: scoped edge fetch.
      let sql = edgesSql(
        hasTaskId: params.taskId != nil,
        hasListId: params.listId != nil,
        includeInactive: params.includeInactive)

      var edgeArgs: [String: any DatabaseValueConvertible] = [
        "edge_fetch_limit": edgeFetchLimit
      ]
      if let cid = params.taskId { edgeArgs["center_id"] = cid }
      if let lid = params.listId { edgeArgs["list_id"] = lid }

      let rawEdges: [(String, String)] = try Row.fetchAll(
        db, sql: sql, arguments: StatementArguments(edgeArgs)
      ).map { (($0[0] as String), ($0[1] as String)) }

      // Center with zero edges: single-node graph (when the center passes
      // the active/inactive + list filter).
      if rawEdges.isEmpty {
        if let centerId = params.taskId {
          let includeFlag: Int64 = params.includeInactive ? 1 : 0
          let listArg: DatabaseValue =
            params.listId.map { $0.databaseValue } ?? .null
          let row = try Row.fetchOne(
            db,
            sql: centerNodeSql(),
            arguments: [centerId, listArg, includeFlag])
          if let row {
            let node = try nodeFromRow(row)
            return Result(
              nodes: [node], edges: [], roots: [node.id],
              blocked: [], leafBlockers: [], truncated: false)
          }
        }
        return Result(
          nodes: [], edges: [], roots: [], blocked: [], leafBlockers: [],
          truncated: false)
      }

      // Step 2: detect edge truncation and cap.
      let edgesTruncated = rawEdges.count > limitEdges
      let cappedEdges: [GraphEdge] = rawEdges.prefix(limitEdges).map {
        GraphEdge(taskId: $0.0, dependsOnTaskId: $0.1)
      }

      // Collect unique node ids from capped edges.
      var nodeIds = Set<String>()
      for e in cappedEdges {
        nodeIds.insert(e.taskId)
        nodeIds.insert(e.dependsOnTaskId)
      }

      // Center may have been truncated out of the capped edges; append it so
      // the SQL CASE has something to match.
      var nodeIdList = Array(nodeIds)
      if let cid = params.taskId, !nodeIds.contains(cid) {
        nodeIdList.append(cid)
      }
      let nodesTruncated = nodeIdList.count > limitNodes

      // Step 3: node cap + fetch. The JSON-array param + json_each keeps the
      // statement fixed-shape; SQL ORDER BY (center-first, then
      // priority_effective) determines the final node order.
      let idListJson: String
      do {
        let data = try JSONEncoder().encode(nodeIdList)
        idListJson = String(decoding: data, as: UTF8.self)
      } catch {
        throw StoreError.serialization("dependency-graph node id list: \(error)")
      }
      let centerArg: DatabaseValue = params.taskId.map { $0.databaseValue } ?? .null
      let nodes: [GraphNode] = try Row.fetchAll(
        db,
        sql: """
          SELECT t.id, t.title, t.status, t.priority, t.due_date, t.planned_date, t.list_id \
          FROM tasks t \
          JOIN json_each(?1) AS j ON t.id = j.value \
          ORDER BY \
              CASE WHEN ?2 IS NOT NULL AND t.id = ?2 THEN 0 ELSE 1 END ASC, \
              t.priority_effective ASC, \
              t.created_at DESC, \
              t.id ASC \
          LIMIT ?3
          """,
        arguments: [idListJson, centerArg, Int64(limitNodes)]
      ).map(nodeFromRow)

      let fetchedIds = Set(nodes.map { $0.id })

      // Re-filter edges to only reference fetched nodes (node cap may have
      // dropped some).
      let edges = cappedEdges.filter {
        fetchedIds.contains($0.taskId) && fetchedIds.contains($0.dependsOnTaskId)
      }

      // Step 4: annotations.
      var dependedOn = Set<String>()
      var hasDeps = Set<String>()
      for e in edges {
        hasDeps.insert(e.taskId)
        dependedOn.insert(e.dependsOnTaskId)
      }

      let roots = nodes.filter { !hasDeps.contains($0.id) }.map { $0.id }

      var nodeStatus = [String: String]()
      for n in nodes { nodeStatus[n.id] = n.status }

      var blockedSet = Set<String>()
      for e in edges {
        if let status = nodeStatus[e.dependsOnTaskId],
          status == StatusName.open || status == StatusName.inProgress
            || status == StatusName.someday
        {
          blockedSet.insert(e.taskId)
        }
      }

      let blocked = nodes.filter { blockedSet.contains($0.id) }.map { $0.id }
      let leafBlockers = nodes
        .filter { dependedOn.contains($0.id) && !hasDeps.contains($0.id) }
        .map { $0.id }

      return Result(
        nodes: nodes,
        edges: edges,
        roots: roots,
        blocked: blocked,
        leafBlockers: leafBlockers,
        truncated: nodesTruncated || edgesTruncated)
    }
  }
}
