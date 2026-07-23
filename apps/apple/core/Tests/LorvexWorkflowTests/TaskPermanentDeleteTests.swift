import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Tests for `permanent_delete_task`. The Rust source carries no
/// `#[test]` cases; the parity surface is the typed contract:
///
/// - `NotFound` when the task id has no row.
/// - `Validation` (#2363 message) when the task is not yet archived.
/// - On success: the row is gone (FK cascades plus the explicit
///   `current_focus_items` / `focus_schedule_blocks` /
///   `task_dependencies` deletes), child / edge tombstone payloads
///   land on `deleteSyncs`, focus parent dates surface on
///   `focusParentDates`, and the synthetic task tombstone is appended
///   to `deleteSyncs` with the pre-delete payload.
final class TaskPermanentDeleteTests: XCTestCase {
  /// HLC handle that emits monotonically advancing stamps anchored at
  /// a far-future physical-ms so the produced versions sort STRICTLY
  /// ABOVE the seeded archive version (`9999999999999_aaaa_…`) and
  /// LWW gates always accept the next write.
  private final class HighSeedHlcHandle: HlcStateHandle, @unchecked Sendable {
    private var counter: UInt64 = 0
    func generate() -> Hlc {
      defer { counter += 1 }
      return try! Hlc(
        physicalMs: 1_700_000_000_000 + counter,
        counter: 0,
        deviceSuffix: "ffffffffffffffff")
    }
  }
  private func makeSession() -> HlcSession { HlcSession(handle: HighSeedHlcHandle()) }

  private func freshStore() throws -> LorvexStore {
    let s = try WorkflowTestSupport.freshStore()
    try s.writer.write { db in
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('inbox', 'Inbox', '0000000000000_0000_0000000000000aaa', "
          + "        '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')")
    }
    return s
  }

  /// Seed an archived task using one monotonic HLC session so the
  /// archive's version sorts strictly above the create's version,
  /// and the subsequent permanent-delete stamp drawn from the same
  /// session sorts above the archive.
  private func seedArchivedTask(
    _ store: LorvexStore, session: HlcSession, id: String = "task-perm-1"
  ) throws -> TaskId {
    let r = try store.writer.write { db in
      try TaskCreate.createTask(
        db, hlc: session,
        input: CreateTaskInput(
          id: id,
          task: TaskCreateInput(title: "Trash me", listId: .set("inbox")),
          includeAdvice: false))
    }
    try store.writer.write { db in
      try TaskArchive.archiveTaskOp(
        db, taskId: r.taskId,
        version: session.nextVersionString(),
        now: "2026-05-01T00:00:00Z")
    }
    return r.taskId
  }

  private func seedRecurrencePair(
    _ store: LorvexStore,
    parentId: String,
    archiveParent: Bool
  ) throws -> (parent: TaskId, successor: TaskId) {
    let successorId = TaskRecurrenceSuccessorID.make(
      parentTaskId: parentId, recurrenceGroupId: "group-\(parentId)")
    let parentVersion = "1600000000000_0000_aaaaaaaaaaaaaaa1"
    let successorVersion = "1600000000001_0000_aaaaaaaaaaaaaaa2"
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "recurrence_group_id, canonical_occurrence_date, completed_at, archived_at, "
          + "schedule_version, lifecycle_version, recurrence_rollover_state, "
          + "recurrence_successor_id, version, created_at, updated_at) "
          + "VALUES (?1, 'Parent', 'completed', 'inbox', '2026-05-01', "
          + "'{\"FREQ\":\"DAILY\"}', ?2, '2026-05-01', "
          + "'2026-05-01T10:00:00Z', ?3, ?4, ?4, 'authorized', ?5, ?4, "
          + "'2026-04-01T00:00:00Z', '2026-05-01T10:00:00Z')",
        arguments: [
          parentId, "group-\(parentId)",
          archiveParent ? "2026-05-02T00:00:00Z" : nil,
          parentVersion, successorId,
        ])
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, due_date, recurrence, "
          + "spawned_from, spawned_from_version, recurrence_group_id, "
          + "canonical_occurrence_date, archived_at, schedule_version, "
          + "lifecycle_version, version, created_at, updated_at) "
          + "VALUES (?1, 'Successor', 'open', 'inbox', '2026-05-02', "
          + "'{\"FREQ\":\"DAILY\"}', ?2, ?3, ?4, '2026-05-02', ?5, "
          + "?6, ?6, ?6, '2026-05-01T10:00:00Z', '2026-05-01T10:00:00Z')",
        arguments: [
          successorId, parentId, parentVersion, "group-\(parentId)",
          archiveParent ? nil : "2026-05-02T00:00:00Z", successorVersion,
        ])
    }
    return (TaskId(trusted: parentId), TaskId(trusted: successorId))
  }

  func testRejectsUnarchivedTask() throws {
    let store = try freshStore()
    let session = makeSession()
    let r = try store.writer.write { db in
      try TaskCreate.createTask(
        db, hlc: session,
        input: CreateTaskInput(
          id: "task-perm-live",
          task: TaskCreateInput(title: "Live", listId: .set("inbox")),
          includeAdvice: false))
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskPermanentDelete.permanentDeleteTask(
          db, hlc: session,
          input: TaskPermanentDelete.PermanentDeleteTaskInput(taskId: r.taskId))
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertTrue(
        m.hasPrefix("task must be archived via archive_task"),
        "got: \(m)")
      XCTAssertTrue(m.contains("issue #2363"), "must cite #2363; got: \(m)")
    }
  }

  func testNotFoundForMissingRow() throws {
    let store = try freshStore()
    let session = makeSession()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskPermanentDelete.permanentDeleteTask(
          db, hlc: session,
          input: TaskPermanentDelete.PermanentDeleteTaskInput(
            taskId: TaskId(trusted: "no-such-id")))
      }
    ) { e in
      guard case StoreError.notFound(let entity, let id) = e else {
        XCTFail("expected notFound, got \(e)"); return
      }
      XCTAssertEqual(entity, "task")
      XCTAssertEqual(id, "no-such-id")
    }
  }

  func testDeletesArchivedTaskAndReturnsTombstonePayload() throws {
    let store = try freshStore()
    let session = makeSession()
    let id = try seedArchivedTask(store, session: session)
    let result = try store.writer.write { db in
      try TaskPermanentDelete.permanentDeleteTask(
        db, hlc: session,
        input: TaskPermanentDelete.PermanentDeleteTaskInput(taskId: id))
    }
    XCTAssertTrue(result.deleted)
    XCTAssertEqual(result.taskId, id.rawValue)
    XCTAssertEqual(result.title, "Trash me")
    XCTAssertEqual(result.summary, "Permanently deleted task 'Trash me'")

    // Row is gone.
    let exists: Int64? = try store.writer.read { db in
      try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?",
        arguments: [id.rawValue])
    }
    XCTAssertEqual(exists, 0)

    // The synthetic task tombstone landed on deleteSyncs with the
    // pre-delete payload.
    let taskTombstone = result.deleteSyncs.first(where: {
      $0.entityType == "task" && $0.entityId == id.rawValue
    })
    XCTAssertNotNil(taskTombstone, "task tombstone payload must be emitted")

    // Payload shape: { id, deleted: true, previous: <before> }.
    guard case .object(let map) = result.payload else {
      XCTFail("payload must be an object"); return
    }
    XCTAssertEqual(map["id"], .string(id.rawValue))
    XCTAssertEqual(map["deleted"], .bool(true))
    XCTAssertNotNil(map["previous"])
  }

  func testCollectsFocusParentDates() throws {
    let store = try freshStore()
    let session = makeSession()
    let id = try seedArchivedTask(store, session: session)
    // Seed a current_focus parent + current_focus_items row.
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO current_focus (date, version, created_at, updated_at) "
          + "VALUES (?, ?, ?, ?)",
        arguments: [
          "2026-05-01",
          "0000000000000_0000_0000000000000bbb",
          "2026-04-29T00:00:00Z", "2026-04-29T00:00:00Z",
        ])
      try db.execute(
        sql:
          "INSERT INTO current_focus_items (date, position, task_id) "
          + "VALUES (?, 0, ?)",
        arguments: ["2026-05-01", id.rawValue])
    }
    let result = try store.writer.write { db in
      try TaskPermanentDelete.permanentDeleteTask(
        db, hlc: session,
        input: TaskPermanentDelete.PermanentDeleteTaskInput(taskId: id))
    }
    XCTAssertEqual(result.focusParentDates.currentFocus, ["2026-05-01"])
    // current_focus_items row is gone (explicit DELETE).
    let count: Int64? = try store.writer.read { db in
      try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE task_id = ?",
        arguments: [id.rawValue])
    }
    XCTAssertEqual(count, 0)
  }

  func testDeletingHistoricalParentPromotesSurvivingSuccessorToRoot() throws {
    let store = try freshStore()
    let session = makeSession()
    let pair = try seedRecurrencePair(
      store, parentId: "delete-parent", archiveParent: true)

    let result = try store.writer.write { db in
      try TaskPermanentDelete.permanentDeleteTask(
        db, hlc: session,
        input: TaskPermanentDelete.PermanentDeleteTaskInput(taskId: pair.parent))
    }

    XCTAssertEqual(result.rerootedTaskIds, [pair.successor.asString])
    let successor = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT spawned_from, spawned_from_version, schedule_version, version "
          + "FROM tasks WHERE id = ?1",
        arguments: [pair.successor.asString])
    }
    XCTAssertNil(successor?[0] as String?)
    XCTAssertNil(successor?[1] as String?)
    XCTAssertEqual(successor?[2] as String?, successor?[3] as String?)
  }

  func testDeletingAuthorizedSuccessorEndsSurvivingPredecessor() throws {
    let store = try freshStore()
    let session = makeSession()
    let pair = try seedRecurrencePair(
      store, parentId: "delete-successor", archiveParent: false)

    let result = try store.writer.write { db in
      try TaskPermanentDelete.permanentDeleteTask(
        db, hlc: session,
        input: TaskPermanentDelete.PermanentDeleteTaskInput(taskId: pair.successor))
    }

    XCTAssertEqual(result.rerootedTaskIds, [pair.parent.asString])
    let predecessor = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT recurrence_rollover_state, recurrence_successor_id, "
          + "lifecycle_version, version FROM tasks WHERE id = ?1",
        arguments: [pair.parent.asString])
    }
    XCTAssertEqual(predecessor?[0] as String?, "ended")
    XCTAssertNil(predecessor?[1] as String?)
    XCTAssertEqual(predecessor?[2] as String?, predecessor?[3] as String?)
  }
}
