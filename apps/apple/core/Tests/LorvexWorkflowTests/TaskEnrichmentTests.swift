import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity port of `lorvex_workflow::task_enrichment` tests.
final class TaskEnrichmentTests: XCTestCase {
  private static let testVersion = "0000000000001_0000_7e57000000000001"
  private static let testTs = "2026-04-04T00:00:00Z"

  private func seedTask(_ writer: any DatabaseWriter, id: String) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, version, created_at, updated_at) "
          + "VALUES (?1, 'Test', 'open', ?2, ?3, ?3)",
        arguments: [id, Self.testVersion, Self.testTs])
    }
  }

  private func parse(_ d: String) -> IsoDate.YMD? {
    switch IsoDate.parseIsoDate(d) {
    case .success(let ymd): return ymd
    case .failure: return nil
    }
  }

  func testEmptyInputIsNoop() throws {
    let store = try WorkflowTestSupport.freshStore()
    let map = try store.writer.read { db in
      try TaskEnrichment.computeEnrichments(db, dates: [], today: "2026-04-04")
    }
    XCTAssertTrue(map.isEmpty)
  }

  func testLatenessPastPlanned() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "t1")
    let map = try store.writer.read { db in
      try TaskEnrichment.computeEnrichments(
        db,
        dates: [
          .init(taskId: "t1", plannedDate: parse("2026-04-01"), dueDate: nil)
        ],
        today: "2026-04-04")
    }
    XCTAssertEqual(map["t1"]?.lateness, .pastPlanned)
  }

  func testLatenessNoDatesOmitsEntry() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "t1")
    let map = try store.writer.read { db in
      try TaskEnrichment.computeEnrichments(
        db,
        dates: [.init(taskId: "t1", plannedDate: nil, dueDate: nil)],
        today: "2026-04-04")
    }
    XCTAssertNil(map["t1"]?.lateness)
  }

  func testInvalidTodayIsValidationError() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "t1")
    XCTAssertThrowsError(
      try store.writer.read { db in
        _ = try TaskEnrichment.computeEnrichments(
          db,
          dates: [.init(taskId: "t1", plannedDate: nil, dueDate: nil)],
          today: "bad-date")
      }
    ) { error in
      guard case let StoreError.validation(msg) = error else {
        XCTFail("expected validation error, got \(error)")
        return
      }
      XCTAssertTrue(msg.contains("invalid today date"))
    }
  }

  func testNoTagsReturnsNoEntry() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "t1")
    let map = try store.writer.read { db in
      try TaskEnrichment.computeEnrichments(
        db,
        dates: [.init(taskId: "t1", plannedDate: nil, dueDate: nil)],
        today: "2026-04-04")
    }
    XCTAssertNil(map["t1"]?.tags)
  }

  func testTagsReturnsDisplayNames() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "t1")
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) "
          + "VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
        arguments: ["tag1", "Work", "work", Self.testVersion, Self.testTs])
      try db.execute(
        sql:
          "INSERT INTO task_tags (task_id, tag_id, version, created_at) "
          + "VALUES (?1, ?2, ?3, ?4)",
        arguments: ["t1", "tag1", Self.testVersion, Self.testTs])
    }
    let map = try store.writer.read { db in
      try TaskEnrichment.computeEnrichments(
        db,
        dates: [.init(taskId: "t1", plannedDate: nil, dueDate: nil)],
        today: "2026-04-04")
    }
    XCTAssertEqual(map["t1"]?.tags, ["Work"])
  }

  func testDependsOnReturnsDependencyIds() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "t1")
    try seedTask(store.writer, id: "t2")
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES (?1, ?2, ?3, ?4)",
        arguments: ["t1", "t2", Self.testVersion, Self.testTs])
    }
    let map = try store.writer.read { db in
      try TaskEnrichment.computeEnrichments(
        db,
        dates: [.init(taskId: "t1", plannedDate: nil, dueDate: nil)],
        today: "2026-04-04")
    }
    XCTAssertEqual(map["t1"]?.dependsOn, ["t2"])
  }

  func testChecklistItemsReturnsOrderedItems() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "t1")
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_checklist_items "
          + "(id, task_id, position, text, version, created_at, updated_at) "
          + "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
        arguments: ["ci1", "t1", 0, "First item", Self.testVersion, Self.testTs])
      try db.execute(
        sql:
          "INSERT INTO task_checklist_items "
          + "(id, task_id, position, text, version, created_at, updated_at) "
          + "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
        arguments: ["ci2", "t1", 1, "Second item", Self.testVersion, Self.testTs])
    }
    let map = try store.writer.read { db in
      try TaskEnrichment.computeEnrichments(
        db,
        dates: [.init(taskId: "t1", plannedDate: nil, dueDate: nil)],
        today: "2026-04-04")
    }
    let items = try XCTUnwrap(map["t1"]?.checklistItems)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[0].text, "First item")
    XCTAssertEqual(items[1].text, "Second item")
  }
}
