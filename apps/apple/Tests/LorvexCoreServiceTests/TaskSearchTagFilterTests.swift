import GRDB
import LorvexDomain
import LorvexStore
import XCTest

/// A task that carries two of the tags a search filters on is one result, counted
/// once. The full-text path used to join the tag table, which returned it once per
/// matching tag and counted it twice.
final class TaskSearchTagFilterTests: XCTestCase {
  func testATaskWithTwoFilteredTagsIsOneResultAndCountedOnce() throws {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "schema/schema.sql")
    let store = try LorvexStore.openInMemory(
      schemaSQL: try String(contentsOf: schemaURL, encoding: .utf8))
    let version = "1711234570000_0000_dec0000400000004"
    try store.writer.write { db in
      for (id, name) in [("t-a", "alpha"), ("t-b", "beta")] {
        try db.execute(
          sql: "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) VALUES (?, ?, ?, ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
          arguments: [id, name, name, version])
      }
      for (index, title) in ["Quarterly report", "Report review"].enumerated() {
        try db.execute(
          sql: """
            INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at, defer_count)
            VALUES (?, ?, 'open', 'inbox', ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0)
            """, arguments: ["task-\(index)", title, version])
      }
      // task-0 carries both tags, task-1 only the first.
      for (task, tag) in [("task-0", "t-a"), ("task-0", "t-b"), ("task-1", "t-a")] {
        try db.execute(
          sql: "INSERT INTO task_tags (task_id, tag_id, created_at, version) VALUES (?, ?, '2026-04-01T00:00:00.000Z', ?)",
          arguments: [task, tag, version])
      }
    }

    let result = try store.writer.read { db in
      try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: SearchPredicate(query: "report", tagFilter: ["t-a", "t-b"]),
        page: Pagination(limit: 20, offset: 0))
    }

    XCTAssertEqual(result.rows.count, 2, "each task once")
    XCTAssertEqual(Set(result.rows.map(\.core.id)).count, 2)
    XCTAssertEqual(result.totalMatching, 2, "counted once each")
  }
}
