import GRDB
import LorvexDomain
import LorvexStore
import XCTest

/// `TaskRepo.Read.blockedTaskIDs(_:among:)` answers for every task on a day
/// surface in one query. As a join from the active tasks it probed the
/// dependency index once per listed id (about 440 ms for 3,000 tasks in a release
/// build, with no dependencies at all), which put a visible wait into every task
/// mutation on a large store. Walking the listed tasks' dependency rows keeps it
/// linear.
final class BlockedTaskIDsScaleTests: XCTestCase {
  func testBlockedTaskIDsStaysFastAndCorrectAmongThousandsOfTasks() throws {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "schema/schema.sql")
    let store = try LorvexStore.openInMemory(
      schemaSQL: try String(contentsOf: schemaURL, encoding: .utf8))
    let version = "1711234570000_0000_dec0000400000004"
    let ids = (0..<3000).map { String(format: "00000000-0000-7000-8000-%012d", $0) }
    try store.writer.write { db in
      for id in ids {
        try db.execute(
          sql: """
            INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at, defer_count)
            VALUES (?, 'T', 'open', 'inbox', ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0)
            """, arguments: [id, version])
      }
      // Task 1 waits on the open task 0, and task 2 on a finished one.
      try db.execute(sql: "UPDATE tasks SET status = 'completed', completed_at = '2026-04-02T00:00:00.000Z' WHERE id = ?", arguments: [ids[3]])
      for (task, blocker) in [(ids[1], ids[0]), (ids[2], ids[3])] {
        try db.execute(
          sql: """
            INSERT INTO task_dependencies (task_id, depends_on_task_id, created_at, version)
            VALUES (?, ?, '2026-04-01T00:00:00.000Z', ?)
            """, arguments: [task, blocker, version])
      }
    }

    let start = Date()
    let blocked = try store.writer.read { db in
      try TaskRepo.Read.blockedTaskIDs(db, among: ids)
    }
    let elapsed = Date().timeIntervalSince(start)

    XCTAssertEqual(blocked, [ids[1]], "only the task waiting on an active task is blocked")
    XCTAssertLessThan(elapsed, 0.25, "blockedTaskIDs took \(elapsed) s for 3,000 tasks")
  }
}
