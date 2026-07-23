import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `repositories/task/dependencies/graph/tests.rs`.
final class TaskRepoDependencyGraphTests: XCTestCase {

  private func insertTask(_ db: Database, _ id: String, _ title: String, _ status: String) throws {
    try TaskRepo.Write.createTask(
      db,
      params: TaskCreateParams(
        id: id, title: title, status: status,
        version: "0000000000000_0000_a0a0a0a0a0a0a0a0",
        now: "2026-03-27T00:00:00Z"))
  }

  private func insertTaskInList(
    _ db: Database, _ id: String, _ title: String, _ status: String, _ listId: String
  ) throws {
    try TaskRepo.Write.createTask(
      db,
      params: TaskCreateParams(
        id: id, title: title, status: status,
        version: "0000000000000_0000_a0a0a0a0a0a0a0a0",
        now: "2026-03-27T00:00:00Z", listId: listId))
  }

  private func addDep(_ db: Database, _ taskId: String, _ dependsOn: String) throws {
    try db.execute(
      sql: """
        INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) \
        VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-27T00:00:00Z')
        """,
      arguments: [taskId, dependsOn])
  }

  private func insertList(_ db: Database, _ id: String, _ name: String) throws {
    try db.execute(
      sql: """
        INSERT INTO lists (id, name, version, created_at, updated_at) \
        VALUES (?1, ?2, '0000000000000_0000_0000000000000000', \
                '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
        """,
      arguments: [id, name])
  }

  // ── task_id + list_id intersection semantics ──────────────────

  func testCenteredPlusListScopeIncludesCrossListNeighborsWhenCenterIsInList() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.DependencyGraph.Result in
      try self.insertList(db, "list-a", "List A")
      try self.insertList(db, "list-b", "List B")
      try self.insertTaskInList(db, "center", "Center", "open", "list-a")
      try self.insertTaskInList(db, "same-list", "Same list dep", "open", "list-a")
      try self.insertTaskInList(db, "other-list", "Other list dep", "open", "list-b")
      try self.addDep(db, "center", "same-list")
      try self.addDep(db, "center", "other-list")
      return try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(
          taskId: "center", listId: "list-a", includeInactive: false,
          limitNodes: 50, limitEdges: 50))
    }
    XCTAssertEqual(result.edges.count, 2, "cross-list blockers should stay visible")
    XCTAssertEqual(Set(result.edges.map(\.dependsOnTaskId)), ["same-list", "other-list"])

    let nodeIds = Set(result.nodes.map { $0.id })
    XCTAssertTrue(nodeIds.contains("center"))
    XCTAssertTrue(nodeIds.contains("same-list"))
    XCTAssertTrue(nodeIds.contains("other-list"), "cross-list blocker should be visible")
  }

  func testCenteredNotInSpecifiedListReturnsEmptyGraph() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.DependencyGraph.Result in
      try self.insertList(db, "list-a", "List A")
      try self.insertList(db, "list-b", "List B")
      try self.insertTaskInList(db, "t1", "Task in list B", "open", "list-b")
      return try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(
          taskId: "t1", listId: "list-a", includeInactive: false,
          limitNodes: 50, limitEdges: 50))
    }
    XCTAssertTrue(result.nodes.isEmpty, "center not in list should yield empty graph")
    XCTAssertTrue(result.edges.isEmpty)
  }

  // ── inactive center task filtering ──────────────────

  func testCenteredInactiveTaskExcludedByDefault() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.DependencyGraph.Result in
      try self.insertTask(db, "t1", "Completed task", "completed")
      return try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(
          taskId: "t1", includeInactive: false, limitNodes: 50, limitEdges: 50))
    }
    XCTAssertTrue(result.nodes.isEmpty, "completed task should be excluded")
    XCTAssertTrue(result.edges.isEmpty)
  }

  func testCenteredInactiveTaskIncludedWhenRequested() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.DependencyGraph.Result in
      try self.insertTask(db, "t1", "Completed task", "completed")
      return try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(
          taskId: "t1", includeInactive: true, limitNodes: 50, limitEdges: 50))
    }
    XCTAssertEqual(result.nodes.count, 1)
    XCTAssertEqual(result.nodes[0].id, "t1")
  }

  func testArchivedTasksAreExcludedEvenWhenInactiveTasksAreIncluded() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "visible", "Visible", "open")
      try self.insertTask(db, "archived", "Archived", "open")
      try self.addDep(db, "visible", "archived")
      try db.execute(
        sql: "UPDATE tasks SET archived_at = '2026-04-25T12:00:00.000Z' WHERE id = 'archived'")
    }
    try store.writer.read { db in
      let graph = try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(
          includeInactive: true, limitNodes: 20, limitEdges: 20))
      XCTAssertTrue(graph.nodes.isEmpty)
      XCTAssertTrue(graph.edges.isEmpty)

      let centeredArchived = try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(
          taskId: "archived", includeInactive: true, limitNodes: 20, limitEdges: 20))
      XCTAssertTrue(centeredArchived.nodes.isEmpty)
    }
  }

  // ── center node pinning under small node cap ──────────────────

  func testCenteredTaskPinnedUnderSmallNodeCap() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.DependencyGraph.Result in
      try self.insertTask(db, "center", "Center task", "open")
      for i in 0..<5 {
        let id = "n\(i)"
        try self.insertTask(db, id, "Neighbour \(i)", "open")
        try self.addDep(db, "center", id)
      }
      return try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(
          taskId: "center", includeInactive: false, limitNodes: 2, limitEdges: 100))
    }
    let nodeIds = result.nodes.map { $0.id }
    XCTAssertTrue(nodeIds.contains("center"), "center node must be pinned; got: \(nodeIds)")
    XCTAssertEqual(result.nodes.count, 2)
    XCTAssertTrue(result.truncated, "graph should be marked as truncated")
  }

  // ── Determinism: center-first + nodes-ordered derived arrays ──

  func testCenteredGraphCenterIsFirstNode() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.DependencyGraph.Result in
      try self.insertTask(db, "center", "Center", "open")
      try self.insertTask(db, "a_neighbor", "A Neighbor", "open")
      try self.addDep(db, "center", "a_neighbor")
      return try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(
          taskId: "center", limitNodes: 50, limitEdges: 50))
    }
    XCTAssertEqual(result.nodes[0].id, "center")
  }

  func testBlockedAndLeafBlockersFollowNodesOrder() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "a", "Task A", "open")
      try self.insertTask(db, "b", "Task B", "open")
      try self.insertTask(db, "c", "Task C", "open")
      try self.addDep(db, "a", "b")
      try self.addDep(db, "b", "c")
    }
    try store.writer.read { db in
      let result = try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(limitNodes: 50, limitEdges: 50))
      XCTAssertEqual(result.blocked.count, 2)
      XCTAssertTrue(result.leafBlockers.contains("c"))
      XCTAssertTrue(result.roots.contains("c"))

      let result2 = try TaskRepo.DependencyGraph.getDependencyGraph(
        db,
        params: TaskRepo.DependencyGraph.Params(limitNodes: 50, limitEdges: 50))
      XCTAssertEqual(result.roots, result2.roots)
      XCTAssertEqual(result.blocked, result2.blocked)
      XCTAssertEqual(result.leafBlockers, result2.leafBlockers)
    }
  }
}
