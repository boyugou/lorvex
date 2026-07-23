import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Behavioral coverage for the `task_checklist_item` independent-child applier
/// (`ApplyChild.applyTaskChecklistItemUpsert` / `applyTaskChecklistItemDelete`).
///
/// The sibling `task_reminder` child is exercised by `ApplyChildTests`; both use
/// the same shared `LwwUpsertSpec` + `ApplyLww.lwwGatedDelete` primitives, but a
/// checklist item carries its own `position` (reorder) and `completed_at`
/// (check/uncheck) surface, so its per-row LWW convergence is pinned directly
/// here rather than left to inference from the shared primitive alone: newer
/// version wins, a stale version is refused (no lost update), an equal version is
/// an idempotent no-op (duplicate-envelope safety), `completed_at` follows
/// nullable-or-clear semantics, the `text` sanitizer runs at the apply boundary,
/// deletes are LWW-gated, and the row converges to the same winner regardless of
/// cross-peer arrival order.
final class ApplyChildChecklistItemTests: XCTestCase {

  private let vOld = "1711234567000_0000_dec0000100000001"
  private let vMid = "1711234568000_0000_dec0000100000001"
  private let vNew = "1711234569000_0000_dec0000100000001"
  private let zeroVersion = "0000000000000_0000_0000000000000000"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func insertTask(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, version, created_at, updated_at)
        VALUES (?, 'T', 'open', ?, '', '')
        """,
      arguments: [id, zeroVersion])
  }

  private func payload(
    taskId: String, position: Int, text: String, completedAt: String? = nil
  ) -> String {
    let completed = completedAt.map { "\"\($0)\"" } ?? "null"
    return """
      {"task_id":"\(taskId)","position":\(position),"text":"\(text)","completed_at":\(completed),"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
      """
  }

  private func count(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM task_checklist_items") ?? -1
  }

  private func position(_ db: Database, _ id: String) throws -> Int64? {
    try Int64.fetchOne(
      db, sql: "SELECT position FROM task_checklist_items WHERE id = ?", arguments: [id])
  }

  private func text(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT text FROM task_checklist_items WHERE id = ?", arguments: [id])
  }

  private func completedAt(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT completed_at FROM task_checklist_items WHERE id = ?", arguments: [id])
  }

  private func version(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT version FROM task_checklist_items WHERE id = ?", arguments: [id])
  }

  // MARK: - upsert

  func testChecklistItemUpsertInsertsNewRow() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 0, text: "Buy milk"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.count(db), 1)
      XCTAssertEqual(try self.position(db, "cli-1"), 0)
      XCTAssertEqual(try self.text(db, "cli-1"), "Buy milk")
      XCTAssertNil(try self.completedAt(db, "cli-1"))
      XCTAssertEqual(try self.version(db, "cli-1"), self.vMid)
    }
  }

  func testChecklistItemUpsertNewerVersionUpdatesPositionTextAndCompletion() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 0, text: "old"),
        version: self.vOld, tieBreak: .rejectEqual)
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(
          taskId: "task-1", position: 3, text: "new", completedAt: "2026-02-02T00:00:00Z"),
        version: self.vNew, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.count(db), 1)
      XCTAssertEqual(try self.position(db, "cli-1"), 3)
      XCTAssertEqual(try self.text(db, "cli-1"), "new")
      XCTAssertEqual(try self.completedAt(db, "cli-1"), "2026-02-02T00:00:00Z")
      XCTAssertEqual(try self.version(db, "cli-1"), self.vNew)
    }
  }

  func testChecklistItemStaleUpsertDoesNotOverwriteNewerRow() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 5, text: "winner"),
        version: self.vNew, tieBreak: .rejectEqual)
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 0, text: "stale"),
        version: self.vOld, tieBreak: .rejectEqual)
      XCTAssertEqual(
        try self.text(db, "cli-1"), "winner",
        "stale (V_OLD) upsert MUST NOT overwrite a V_NEW row")
      XCTAssertEqual(try self.position(db, "cli-1"), 5)
      XCTAssertEqual(try self.version(db, "cli-1"), self.vNew)
    }
  }

  func testChecklistItemEqualVersionIsIdempotentNoOp() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 1, text: "first"),
        version: self.vMid, tieBreak: .rejectEqual)
      // The same version re-delivered (a duplicate envelope) carrying different
      // content must be a no-op under .rejectEqual — the double-apply guard.
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 9, text: "second"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.text(db, "cli-1"), "first")
      XCTAssertEqual(try self.position(db, "cli-1"), 1)
    }
  }

  func testChecklistItemCompletionClearedByNewerUncheck() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(
          taskId: "task-1", position: 0, text: "task", completedAt: "2026-02-02T00:00:00Z"),
        version: self.vOld, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.completedAt(db, "cli-1"), "2026-02-02T00:00:00Z")
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 0, text: "task", completedAt: nil),
        version: self.vNew, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.count(db), 1)
      XCTAssertNil(
        try self.completedAt(db, "cli-1"), "a newer uncheck MUST clear completed_at to NULL")
    }
  }

  func testChecklistItemUpsertSanitizesText() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      // A bidi override (U+202E) embedded in the peer's text is stripped by the
      // shared sanitizer at the apply boundary.
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 0, text: "Buy\u{202E}milk"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.text(db, "cli-1"), "Buymilk")
    }
  }

  // MARK: - delete

  func testChecklistItemDeleteRemovesRow() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 0, text: "x"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.count(db), 1)
      try ApplyChild.applyTaskChecklistItemDelete(db, entityId: "cli-1", version: self.vNew)
      XCTAssertEqual(try self.count(db), 0)
    }
  }

  func testChecklistItemStaleDeleteRefusedByInRowLwwGuard() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskChecklistItemUpsert(
        db, entityId: "cli-1",
        payload: self.payload(taskId: "task-1", position: 0, text: "stay"),
        version: self.vNew, tieBreak: .rejectEqual)
      try ApplyChild.applyTaskChecklistItemDelete(db, entityId: "cli-1", version: self.vOld)
      XCTAssertEqual(
        try self.count(db), 1, "stale delete (V_OLD) MUST NOT remove a V_NEW row")
    }
  }

  // MARK: - cross-peer convergence

  func testChecklistItemBothArrivalOrdersConvergeToSameWinner() throws {
    // Peer A applies old-then-new; peer B applies new-then-old. Per-row LWW must
    // converge both peers to the V_NEW content regardless of arrival order.
    func settle(applyOldFirst: Bool) throws -> (text: String?, position: Int64?, version: String?) {
      let store = try SyncTestSupport.freshStore()
      return try store.writer.write { db in
        try self.insertTask(db, "task-1")
        let old = self.payload(taskId: "task-1", position: 0, text: "old")
        let new = self.payload(taskId: "task-1", position: 7, text: "new")
        let ordered: [(String, String)] =
          applyOldFirst ? [(old, self.vOld), (new, self.vNew)] : [(new, self.vNew), (old, self.vOld)]
        for (body, ver) in ordered {
          try ApplyChild.applyTaskChecklistItemUpsert(
            db, entityId: "cli-1", payload: body, version: ver, tieBreak: .rejectEqual)
        }
        return (try self.text(db, "cli-1"), try self.position(db, "cli-1"),
          try self.version(db, "cli-1"))
      }
    }
    let a = try settle(applyOldFirst: true)
    let b = try settle(applyOldFirst: false)
    XCTAssertEqual(a.text, "new")
    XCTAssertEqual(a.position, 7)
    XCTAssertEqual(a.version, self.vNew)
    XCTAssertEqual(a.text, b.text, "both arrival orders MUST converge to the same text")
    XCTAssertEqual(a.position, b.position, "both arrival orders MUST converge to the same position")
    XCTAssertEqual(a.version, b.version, "both arrival orders MUST converge to the same version")
  }
}
