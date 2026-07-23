import GRDB
import XCTest

@testable import LorvexStore

final class SchemaNumericInvariantTests: XCTestCase {
  func testTaskEstimateMustBeAbsentOrOneTo1440Minutes() throws {
    let store = try TestSupport.freshStore()
    for invalid in [0, 1_441] {
      XCTAssertThrowsError(
        try store.writer.write { db in
          try db.execute(
            sql: """
              INSERT INTO tasks (
                id, title, status, list_id, estimated_minutes,
                version, created_at, updated_at
              ) VALUES (?, 'Task', 'open', 'inbox', ?,
                        '0000000000000_0000_a0a0a0a0a0a0a0a0',
                        '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
              """,
            arguments: ["task-\(invalid)", invalid])
        })
    }

    XCTAssertNoThrow(
      try store.writer.write { db in
        try db.execute(
          sql: """
            INSERT INTO tasks (
              id, title, status, list_id, estimated_minutes,
              version, created_at, updated_at
            ) VALUES ('task-valid', 'Task', 'open', 'inbox', 1440,
                      '0000000000000_0000_a0a0a0a0a0a0a0a0',
                      '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
            """)
      })
  }

  func testSyncedOrderingPositionsCannotBeNegative() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (
            id, title, status, list_id, version, created_at, updated_at
          ) VALUES ('task-position', 'Task', 'open', 'inbox',
                    '0000000000000_0000_a0a0a0a0a0a0a0a0',
                    '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
          """)
    }

    let statements = [
      """
      INSERT INTO lists (
        id, name, version, created_at, updated_at, position
      ) VALUES ('negative-list', 'List',
                '0000000000000_0000_a0a0a0a0a0a0a0a0',
                '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z', -1)
      """,
      """
      INSERT INTO habits (
        id, name, lookup_key, version, created_at, updated_at, position
      ) VALUES ('negative-habit', 'Habit', 'negative-habit',
                '0000000000000_0000_a0a0a0a0a0a0a0a0',
                '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z', -1)
      """,
      """
      INSERT INTO task_checklist_items (
        id, task_id, position, text, version, created_at, updated_at
      ) VALUES ('negative-item', 'task-position', -1, 'Item',
                '0000000000000_0000_a0a0a0a0a0a0a0a0',
                '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
      """,
    ]
    for sql in statements {
      XCTAssertThrowsError(try store.writer.write { db in try db.execute(sql: sql) })
    }
  }
}
