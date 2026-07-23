import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Tests for the leaf store-shaped mutations ported under
/// `lorvex-workflow/src/task_archive.rs`. The Rust source has no
/// `#[test]` cases for these files; the parity surface is the typed
/// contract on each helper:
///
/// - `archive_task_op` / `restore_task_op` — `NotFound` when row
///   missing, `Validation` when already in / not in Trash,
///   `StaleVersion` when the LWW gate rejects.
final class TaskArchiveAndUndoTests: XCTestCase {
  private final class CountingHlcHandle: HlcStateHandle, @unchecked Sendable {
    private var counter: UInt64 = 0
    func generate() -> Hlc {
      defer { counter += 1 }
      return try! Hlc(physicalMs: counter, counter: 0, deviceSuffix: "abcdef0123456789")
    }
  }
  private func makeSession() -> HlcSession { HlcSession(handle: CountingHlcHandle()) }

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

  private func seedTask(_ store: LorvexStore, id: String = "task-archive-1") throws -> TaskId {
    let session = makeSession()
    let r = try store.writer.write { db in
      try TaskCreate.createTask(
        db, hlc: session,
        input: CreateTaskInput(
          id: id,
          task: TaskCreateInput(title: "Archive me", listId: .set("inbox")),
          includeAdvice: false))
    }
    return r.taskId
  }

  // MARK: - archive_task_op

  func testArchiveStampsArchivedAtAndBumpsVersion() throws {
    let store = try freshStore()
    let id = try seedTask(store)
    try store.writer.write { db in
      try TaskArchive.archiveTaskOp(
        db, taskId: id,
        version: "9999913599999_9999_ffffffffffffffff",
        now: "2026-05-01T00:00:00Z")
    }
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT archived_at, version, updated_at FROM tasks WHERE id = ?",
        arguments: [id.rawValue])
      XCTAssertEqual(row?["archived_at"] as String?, "2026-05-01T00:00:00Z")
      XCTAssertEqual(row?["version"] as String?, "9999913599999_9999_ffffffffffffffff")
      XCTAssertEqual(row?["updated_at"] as String?, "2026-05-01T00:00:00Z")
    }
  }

  func testArchiveRejectsAlreadyArchived() throws {
    let store = try freshStore()
    let id = try seedTask(store)
    try store.writer.write { db in
      try TaskArchive.archiveTaskOp(
        db, taskId: id, version: "9999913599999_9999_ffffffffffffffff",
        now: "2026-05-01T00:00:00Z")
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskArchive.archiveTaskOp(
          db, taskId: id, version: "9999913599999_9999_fffffffffffffffe",
          now: "2026-05-02T00:00:00Z")
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(m, "Task '\(id.rawValue)' is already in the Trash")
    }
  }

  func testArchiveNotFoundForMissingRow() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskArchive.archiveTaskOp(
          db, taskId: TaskId(trusted: "missing-id"),
          version: "9999913599999_9999_ffffffffffffffff",
          now: "2026-05-01T00:00:00Z")
      }
    ) { e in
      guard case StoreError.notFound(let entity, let id) = e else {
        XCTFail("expected notFound, got \(e)"); return
      }
      XCTAssertEqual(entity, "task")
      XCTAssertEqual(id, "missing-id")
    }
  }

  func testArchiveStaleVersionRejected() throws {
    let store = try freshStore()
    let id = try seedTask(store)
    // The seed wrote a version like "0000000000000_0000_…"; passing a
    // strictly-smaller version trips the `? > version` gate.
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskArchive.archiveTaskOp(
          db, taskId: id,
          version: "0000000000000_0000_0000000000000000",
          now: "2026-05-01T00:00:00Z")
      }
    ) { e in
      guard case StoreError.staleVersion = e else {
        XCTFail("expected staleVersion, got \(e)"); return
      }
    }
  }

  // MARK: - restore_task_op

  func testRestoreClearsArchivedAt() throws {
    let store = try freshStore()
    let id = try seedTask(store)
    try store.writer.write { db in
      try TaskArchive.archiveTaskOp(
        db, taskId: id, version: "9999913599999_9998_aaaaaaaaaaaaaaaa",
        now: "2026-05-01T00:00:00Z")
      try TaskArchive.restoreTaskOp(
        db, taskId: id, version: "9999913599999_9999_bbbbbbbbbbbbbbbb",
        now: "2026-05-02T00:00:00Z")
    }
    try store.writer.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT archived_at, version FROM tasks WHERE id = ?",
        arguments: [id.rawValue])
      XCTAssertNil(row?["archived_at"] as String?)
      XCTAssertEqual(row?["version"] as String?, "9999913599999_9999_bbbbbbbbbbbbbbbb")
    }
  }

  func testRestoreRejectsNotInTrash() throws {
    let store = try freshStore()
    let id = try seedTask(store)
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskArchive.restoreTaskOp(
          db, taskId: id, version: "9999913599999_9999_ffffffffffffffff",
          now: "2026-05-02T00:00:00Z")
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(m, "Task '\(id.rawValue)' is not in the Trash")
    }
  }

  func testRestoreNotFoundForMissingRow() throws {
    let store = try freshStore()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TaskArchive.restoreTaskOp(
          db, taskId: TaskId(trusted: "missing-id"),
          version: "9999913599999_9999_ffffffffffffffff",
          now: "2026-05-02T00:00:00Z")
      }
    ) { e in
      guard case StoreError.notFound = e else {
        XCTFail("expected notFound, got \(e)"); return
      }
    }
  }
}
