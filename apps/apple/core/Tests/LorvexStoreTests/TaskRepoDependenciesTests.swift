import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `repositories/task/dependencies/write_tests.rs`.
final class TaskRepoDependenciesTests: XCTestCase {

  private func task(_ id: String) -> TaskId { TaskId(trusted: id) }
  private func tasks(_ ids: [String]) -> [TaskId] { ids.map(task) }

  private func insertTask(_ db: Database, _ id: String, _ title: String) throws {
    try TaskRepo.Write.createTask(
      db,
      params: TaskCreateParams(
        id: id, title: title, status: "open", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T00:00:00Z"))
  }

  private func edgeCount(_ db: Database, taskId: String? = nil) throws -> Int64 {
    if let taskId {
      return try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM task_dependencies WHERE task_id = ?",
        arguments: [taskId]) ?? 0
    }
    return try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM task_dependencies") ?? 0
  }

  func testBatchInsertCreatesAllEdges() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "t1", "Task 1")
      try self.insertTask(db, "t2", "Task 2")
      try self.insertTask(db, "t3", "Task 3")
    }
    let count = try TaskRepo.Dependencies.insertDependencyEdgesBatch(
      store.writer, taskId: task("t1"), dependsOnIds: tasks(["t2", "t3"]),
      version: "0000000000001_0000_0000000000000001", now: "2026-03-27T00:00:00Z")
    XCTAssertEqual(count, 2)
    try store.writer.read { db in
      XCTAssertEqual(try self.edgeCount(db, taskId: "t1"), 2)
    }
  }

  func testBatchInsertIgnoresDuplicates() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "t1", "Task 1")
      try self.insertTask(db, "t2", "Task 2")
    }
    _ = try TaskRepo.Dependencies.insertDependencyEdgesBatch(
      store.writer, taskId: task("t1"), dependsOnIds: tasks(["t2"]),
      version: "0000000000001_0000_0000000000000001", now: "2026-03-27T00:00:00Z")
    let count = try TaskRepo.Dependencies.insertDependencyEdgesBatch(
      store.writer, taskId: task("t1"), dependsOnIds: tasks(["t2"]),
      version: "0000000000002_0000_0000000000000002", now: "2026-03-27T01:00:00Z")
    XCTAssertEqual(count, 0)
  }

  func testBatchInsertEmptyIsNoop() throws {
    let store = try TestSupport.freshStore()
    let count = try TaskRepo.Dependencies.insertDependencyEdgesBatch(
      store.writer, taskId: task("t1"), dependsOnIds: [],
      version: "0000000000001_0000_0000000000000001", now: "now")
    XCTAssertEqual(count, 0)
  }

  func testBatchInsertRejectsArchivedEndpoint() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "live", "Alive")
      try self.insertTask(db, "trashed", "Trashed")
      try db.execute(
        sql: "UPDATE tasks SET archived_at = '2026-04-26T00:00:00.000Z' WHERE id = 'trashed'")
    }
    XCTAssertThrowsError(
      try TaskRepo.Dependencies.insertDependencyEdgesBatch(
        store.writer, taskId: task("live"), dependsOnIds: tasks(["trashed"]),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T00:00:00Z")
    ) { error in
      guard case .validation = error as? StoreError else {
        XCTFail("expected validation error, got \(error)")
        return
      }
    }
    try store.writer.read { db in
      XCTAssertEqual(try self.edgeCount(db), 0)
    }
  }

  func testBatchInsertRejectsMissingEndpoint() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "live", "Alive")
    }
    XCTAssertThrowsError(
      try TaskRepo.Dependencies.insertDependencyEdgesBatch(
        store.writer, taskId: task("live"), dependsOnIds: tasks(["does-not-exist"]),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T00:00:00Z")
    ) { error in
      guard case .validation = error as? StoreError else {
        XCTFail("expected validation error, got \(error)")
        return
      }
    }
  }

  func testBatchInsertAllowsCompletedSourceAndTargetHistory() throws {
    for completedIsSource in [true, false] {
      let store = try TestSupport.freshStore()
      try store.writer.write { db in
        try self.insertTask(db, "source", "Source")
        try self.insertTask(db, "target", "Target")
        try db.execute(
          sql: """
            UPDATE tasks
            SET status = 'completed', completed_at = '2026-03-28T00:00:00Z'
            WHERE id = ?
            """,
          arguments: [completedIsSource ? "source" : "target"])
      }

      XCTAssertEqual(
        try TaskRepo.Dependencies.insertDependencyEdgesBatch(
          store.writer, taskId: task("source"), dependsOnIds: tasks(["target"]),
          version: "0000000000002_0000_0000000000000002",
          now: "2026-03-28T00:00:00Z"),
        1)
    }
  }

  func testBatchInsertRejectsCancelledSourceAndTargetEndpoints() throws {
    for cancelledIsSource in [true, false] {
      let store = try TestSupport.freshStore()
      try store.writer.write { db in
        try self.insertTask(db, "source", "Source")
        try self.insertTask(db, "target", "Target")
        try db.execute(
          sql: "UPDATE tasks SET status = 'cancelled' WHERE id = ?",
          arguments: [cancelledIsSource ? "source" : "target"])
      }

      XCTAssertThrowsError(
        try TaskRepo.Dependencies.insertDependencyEdgesBatch(
          store.writer, taskId: task("source"), dependsOnIds: tasks(["target"]),
          version: "0000000000002_0000_0000000000000002",
          now: "2026-03-28T00:00:00Z")
      ) { error in
        guard case .validation(let message) = error as? StoreError else {
          XCTFail("expected validation error, got \(error)")
          return
        }
        XCTAssertTrue(message.contains("cancelled"), "got: \(message)")
      }
      try store.writer.read { db in
        XCTAssertEqual(try self.edgeCount(db), 0)
      }
    }
  }

  func testBatchInsertAllowsSomedayEndpoints() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "source", "Source")
      try self.insertTask(db, "target", "Target")
      try db.execute(
        sql: "UPDATE tasks SET status = 'someday' WHERE id IN ('source', 'target')")
    }

    XCTAssertEqual(
      try TaskRepo.Dependencies.insertDependencyEdgesBatch(
        store.writer, taskId: task("source"), dependsOnIds: tasks(["target"]),
        version: "0000000000002_0000_0000000000000002",
        now: "2026-03-28T00:00:00Z"),
      1)
  }

  func testBatchInsertRejectsSelfDependencyWithValidationError() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "alpha", "Alpha")
    }
    XCTAssertThrowsError(
      try TaskRepo.Dependencies.insertDependencyEdgesBatch(
        store.writer, taskId: task("alpha"), dependsOnIds: tasks(["alpha"]),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T00:00:00Z")
    ) { error in
      guard case .validation(let msg) = error as? StoreError else {
        XCTFail("expected validation error, got \(error)")
        return
      }
      XCTAssertTrue(msg.contains("self-reference"), "got: \(msg)")
    }
    try store.writer.read { db in
      XCTAssertEqual(try self.edgeCount(db), 0)
    }
  }

  func testBatchInsertRejectsMixedBatchWithSelfReference() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "alpha", "Alpha")
      try self.insertTask(db, "beta", "Beta")
    }
    XCTAssertThrowsError(
      try TaskRepo.Dependencies.insertDependencyEdgesBatch(
        store.writer, taskId: task("alpha"), dependsOnIds: tasks(["beta", "alpha"]),
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T00:00:00Z")
    ) { error in
      guard case .validation = error as? StoreError else {
        XCTFail("expected validation error, got \(error)")
        return
      }
    }
    try store.writer.read { db in
      XCTAssertEqual(try self.edgeCount(db), 0, "no partial writes on rejected batch")
    }
  }

  func testSchemaCheckBlocksRawSelfEdgeInsert() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "alpha", "Alpha")
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try db.execute(
          sql: """
            INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) \
            VALUES ('alpha', 'alpha', '0000000000001_0000_0000000000000001', '2026-03-27T00:00:00Z')
            """)
      }
    ) { error in
      XCTAssertTrue(
        "\(error)".lowercased().contains("check"),
        "expected schema-level CHECK failure, got: \(error)")
    }
  }

  func testBatchInsertSingleEdge() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "t1", "Task 1")
      try self.insertTask(db, "t2", "Task 2")
    }
    let count = try TaskRepo.Dependencies.insertDependencyEdgesBatch(
      store.writer, taskId: task("t1"), dependsOnIds: tasks(["t2"]),
      version: "0000000000001_0000_0000000000000001", now: "2026-03-27T00:00:00Z")
    XCTAssertEqual(count, 1)
  }
}
