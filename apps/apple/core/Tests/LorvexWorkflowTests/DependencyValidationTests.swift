import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity port of `lorvex_workflow::dependency_validation` tests.
final class DependencyValidationTests: XCTestCase {
  private func tid(_ s: String) -> TaskId { TaskId(trusted: s) }

  private func insertTask(_ writer: any DatabaseWriter, id: String) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, version, created_at, updated_at) "
          + "VALUES (?1, ?1, 'open', '0000000000000_0000_0000000000000000', "
          + "        datetime('now'), datetime('now'))",
        arguments: [id])
    }
  }

  private func insertDep(_ writer: any DatabaseWriter, taskId: String, dependsOnId: String) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES (?1, ?2, '0000000000000_0000_0000000000000000', datetime('now'))",
        arguments: [taskId, dependsOnId])
    }
  }

  func testAllowsValidDependency() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "a")
    try insertTask(store.writer, id: "b")
    try store.writer.read { db in
      XCTAssertNoThrow(
        try DependencyValidation.validateNoDependencyCycle(
          db, taskId: tid("a"), newDependsOn: ["b"]))
    }
  }

  func testRejectsSelfDependency() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "a")
    try store.writer.read { db in
      XCTAssertThrowsError(
        try DependencyValidation.validateNoDependencyCycle(
          db, taskId: tid("a"), newDependsOn: ["a"])
      ) { error in
        XCTAssertTrue("\(error)".contains("Circular dependency detected"))
      }
    }
  }

  func testRejectsDirectCycle() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "a")
    try insertTask(store.writer, id: "b")
    try insertDep(store.writer, taskId: "b", dependsOnId: "a")
    try store.writer.read { db in
      XCTAssertThrowsError(
        try DependencyValidation.validateNoDependencyCycle(
          db, taskId: tid("a"), newDependsOn: ["b"])
      ) { error in
        XCTAssertTrue("\(error)".contains("Circular dependency detected"))
      }
    }
  }

  func testRejectsTransitiveCycle() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "a")
    try insertTask(store.writer, id: "b")
    try insertTask(store.writer, id: "c")
    try insertDep(store.writer, taskId: "b", dependsOnId: "a")
    try insertDep(store.writer, taskId: "c", dependsOnId: "b")
    try store.writer.read { db in
      XCTAssertThrowsError(
        try DependencyValidation.validateNoDependencyCycle(
          db, taskId: tid("a"), newDependsOn: ["c"])
      ) { error in
        XCTAssertTrue("\(error)".contains("Circular dependency detected"))
      }
    }
  }

  func testAllowsDiamondWithoutCycle() throws {
    let store = try WorkflowTestSupport.freshStore()
    for id in ["d", "b", "c", "a", "e"] { try insertTask(store.writer, id: id) }
    try insertDep(store.writer, taskId: "b", dependsOnId: "d")
    try insertDep(store.writer, taskId: "c", dependsOnId: "d")
    try insertDep(store.writer, taskId: "a", dependsOnId: "b")
    try insertDep(store.writer, taskId: "a", dependsOnId: "c")
    try store.writer.read { db in
      XCTAssertNoThrow(
        try DependencyValidation.validateNoDependencyCycle(
          db, taskId: tid("e"), newDependsOn: ["a"]))
    }
  }
}
