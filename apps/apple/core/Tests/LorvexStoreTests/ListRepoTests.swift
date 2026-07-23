import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class ListRepoTests: XCTestCase {

  // Tests bypass the trust-boundary parser via `init(trusted:)` because the
  // seeded FK rows use short labels (`l1`, `l2`, …) rather than UUIDs.
  private func lid(_ id: String) -> ListId { ListId(trusted: id) }

  private func insertList(
    _ db: Database, id: String, name: String, color: String? = nil
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO lists (id, name, color, version, created_at, updated_at) \
        VALUES (?, ?, ?, '0000000000000_0000_0000000000000000', \
        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
        """,
      arguments: [id, name, color])
  }

  private func insertTask(
    _ db: Database, id: String, listId: String?, status: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at, completed_at, defer_count) \
        VALUES (?, ?, ?, ?, '0000000000000_0000_0000000000000000', \
        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', \
        CASE WHEN ? = 'completed' THEN '2026-01-01T00:00:00.000Z' END, 0)
        """,
      arguments: [id, "Task \(id)", status, listId, status])
  }

  // MARK: - get_list

  func testGetListById() throws {
    let store = try TestSupport.freshStore()
    let list = try store.writer.write { db -> ListRow? in
      try self.insertList(db, id: "l1", name: "Home", color: "#ff0000")
      return try ListRepo.getList(db, id: self.lid("l1"))
    }
    let unwrapped = try XCTUnwrap(list)
    XCTAssertEqual(unwrapped.id, "l1")
    XCTAssertEqual(unwrapped.name, "Home")
    XCTAssertEqual(unwrapped.color, "#ff0000")
    XCTAssertNil(unwrapped.archivedAt)
    XCTAssertEqual(unwrapped.position, 0)
  }

  func testGetListReturnsNilForMissing() throws {
    let store = try TestSupport.freshStore()
    let list = try store.writer.read { db in
      try ListRepo.getList(db, id: self.lid("nonexistent"))
    }
    XCTAssertNil(list)
  }

  // MARK: - get_all_lists_with_counts

  func testGetAllListsWithCountsReturnsCorrectCounts() throws {
    let store = try TestSupport.freshStore()
    let lists = try store.writer.write { db -> [ListWithCounts] in
      try self.insertList(db, id: "l1", name: "Home")
      try self.insertList(db, id: "l2", name: "Work")
      try self.insertTask(db, id: "t1", listId: "l1", status: "open")
      try self.insertTask(db, id: "t2", listId: "l1", status: "open")
      try self.insertTask(db, id: "t3", listId: "l1", status: "completed")
      try self.insertTask(db, id: "t4", listId: "l1", status: "cancelled")
      try self.insertTask(db, id: "t5", listId: "l2", status: "open")
      return try ListRepo.getAllListsWithCounts(db)
    }
    XCTAssertEqual(lists.count, 3)
    let home = try XCTUnwrap(lists.first { $0.list.name == "Home" })
    XCTAssertEqual(home.openCount, 2)
    XCTAssertEqual(home.completedCount, 1)
    XCTAssertEqual(home.cancelledCount, 1)
    XCTAssertEqual(home.totalCount, 4)
    let work = try XCTUnwrap(lists.first { $0.list.name == "Work" })
    XCTAssertEqual(work.openCount, 1)
    XCTAssertEqual(work.completedCount, 0)
    XCTAssertEqual(work.cancelledCount, 0)
    XCTAssertEqual(work.totalCount, 1)
  }

  func testGetAllListsWithCountsEmptyList() throws {
    let store = try TestSupport.freshStore()
    let lists = try store.writer.write { db -> [ListWithCounts] in
      try self.insertList(db, id: "l1", name: "Empty")
      return try ListRepo.getAllListsWithCounts(db)
    }
    XCTAssertEqual(lists.count, 2)
    let empty = try XCTUnwrap(lists.first { $0.list.id == "l1" })
    XCTAssertEqual(empty.openCount, 0)
    XCTAssertEqual(empty.completedCount, 0)
    XCTAssertEqual(empty.cancelledCount, 0)
    XCTAssertEqual(empty.totalCount, 0)
  }

  // MARK: - list-as-project progress

  func testProgressFractionExcludesCancelledFromDenominator() throws {
    // Home: 2 open, 3 completed, 5 cancelled → progress 3/5 (0.6),
    // because cancelled tasks don't count toward project completion.
    let store = try TestSupport.freshStore()
    let lists = try store.writer.write { db -> [ListWithCounts] in
      try self.insertList(db, id: "l1", name: "Home")
      for i in 1...2 { try self.insertTask(db, id: "o\(i)", listId: "l1", status: "open") }
      for i in 1...3 { try self.insertTask(db, id: "c\(i)", listId: "l1", status: "completed") }
      for i in 1...5 { try self.insertTask(db, id: "x\(i)", listId: "l1", status: "cancelled") }
      return try ListRepo.getAllListsWithCounts(db)
    }
    let home = try XCTUnwrap(lists.first { $0.list.name == "Home" })
    XCTAssertEqual(home.openCount, 2)
    XCTAssertEqual(home.completedCount, 3)
    XCTAssertEqual(home.cancelledCount, 5)
    XCTAssertEqual(home.totalCount, 10)
    // Denominator = totalCount - cancelledCount = 10 - 5 = 5; fraction = 3/5.
    let denom = Int(home.totalCount - home.cancelledCount)
    XCTAssertEqual(denom, 5)
    XCTAssertEqual(Double(home.completedCount) / Double(denom), 0.6, accuracy: 1e-9)
  }

  func testProgressIsAllCompleteWhenEveryTaskDone() throws {
    let store = try TestSupport.freshStore()
    let lists = try store.writer.write { db -> [ListWithCounts] in
      try self.insertList(db, id: "l1", name: "Wrapped")
      for i in 1...4 { try self.insertTask(db, id: "c\(i)", listId: "l1", status: "completed") }
      return try ListRepo.getAllListsWithCounts(db)
    }
    let wrapped = try XCTUnwrap(lists.first { $0.list.name == "Wrapped" })
    XCTAssertEqual(wrapped.openCount, 0)
    XCTAssertEqual(wrapped.completedCount, 4)
    XCTAssertEqual(wrapped.cancelledCount, 0)
    XCTAssertEqual(wrapped.totalCount, 4)
  }

  func testProgressDenominatorIsZeroWhenAllCancelled() throws {
    // 5 cancelled, 0 elsewhere → denominator is 0; UI hides the bar.
    let store = try TestSupport.freshStore()
    let lists = try store.writer.write { db -> [ListWithCounts] in
      try self.insertList(db, id: "l1", name: "Dropped")
      for i in 1...5 { try self.insertTask(db, id: "x\(i)", listId: "l1", status: "cancelled") }
      return try ListRepo.getAllListsWithCounts(db)
    }
    let dropped = try XCTUnwrap(lists.first { $0.list.name == "Dropped" })
    XCTAssertEqual(dropped.cancelledCount, 5)
    XCTAssertEqual(dropped.totalCount, 5)
    XCTAssertEqual(Int(dropped.totalCount - dropped.cancelledCount), 0)
  }

  // MARK: - field mapping

  func testListRowMapsAllFields() throws {
    let store = try TestSupport.freshStore()
    let list = try store.writer.write { db -> ListRow? in
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, color, icon, description, ai_notes, version, created_at, updated_at, archived_at, position) \
          VALUES ('l1', 'Full List', '#00ff00', 'star', 'A description', 'AI notes here', \
          '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', '2026-01-02T00:00:00.000Z',
          '2026-01-03T00:00:00.000Z', 7)
          """)
      return try ListRepo.getList(db, id: self.lid("l1"))
    }
    let unwrapped = try XCTUnwrap(list)
    XCTAssertEqual(unwrapped.id, "l1")
    XCTAssertEqual(unwrapped.name, "Full List")
    XCTAssertEqual(unwrapped.color, "#00ff00")
    XCTAssertEqual(unwrapped.icon, "star")
    XCTAssertEqual(unwrapped.description, "A description")
    XCTAssertEqual(unwrapped.aiNotes, "AI notes here")
    XCTAssertEqual(unwrapped.createdAt.asString, "2026-01-01T00:00:00.000Z")
    XCTAssertEqual(unwrapped.updatedAt.asString, "2026-01-02T00:00:00.000Z")
    XCTAssertEqual(unwrapped.archivedAt, "2026-01-03T00:00:00.000Z")
    XCTAssertEqual(unwrapped.position, 7)
  }

  // MARK: - create_list

  func testCreateListReturnsInsertedRow() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db in
      try ListRepo.createList(
        db, id: self.lid("l1"), name: "New List", color: "#aabb00",
        icon: "folder", description: "My desc",
        version: "0000000000000_0000_0000000000000000")
    }
    XCTAssertEqual(row.id, "l1")
    XCTAssertEqual(row.name, "New List")
    XCTAssertEqual(row.color, "#aabb00")
    XCTAssertEqual(row.icon, "folder")
    XCTAssertEqual(row.description, "My desc")
    XCTAssertNil(row.aiNotes)
    XCTAssertNil(row.archivedAt)
    XCTAssertEqual(row.position, 0)
    XCTAssertFalse(row.createdAt.asString.isEmpty)
    XCTAssertEqual(row.createdAt, row.updatedAt)
  }

  func testCreateListMinimalFields() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db in
      try ListRepo.createList(
        db, id: self.lid("l1"), name: "Minimal",
        version: "0000000000000_0000_0000000000000000")
    }
    XCTAssertEqual(row.name, "Minimal")
    XCTAssertNil(row.color)
    XCTAssertNil(row.icon)
    XCTAssertNil(row.description)
  }

  // MARK: - upsert_list_for_import

  func testUpsertListForImportInsertsAtSuppliedId() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db in
      try ListRepo.upsertListForImport(
        db,
        params: ListCreateParams(
          id: self.lid("imported-list"), name: "Imported", color: "#112233",
          icon: "tray", description: "Restored",
          version: "0000000000000_0000_0000000000000001"),
        now: "2026-02-02T00:00:00.000Z")
    }
    XCTAssertEqual(row.id, "imported-list")
    XCTAssertEqual(row.name, "Imported")
    XCTAssertEqual(row.color, "#112233")
    XCTAssertEqual(row.description, "Restored")
  }

  func testUpsertListForImportIsIdempotentById() throws {
    let store = try TestSupport.freshStore()
    let (countAfterFirst, countAfterSecond, second) = try store.writer.write {
      db -> (Int64, Int64, ListRow) in
      _ = try ListRepo.upsertListForImport(
        db,
        params: ListCreateParams(
          id: self.lid("imported-list"), name: "First", description: "v1",
          version: "0000000000000_0000_0000000000000001"),
        now: "2026-02-02T00:00:00.000Z")
      let afterFirst = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM lists") ?? 0
      // Re-import the same id with changed content: overwrites in place, no dup.
      let row = try ListRepo.upsertListForImport(
        db,
        params: ListCreateParams(
          id: self.lid("imported-list"), name: "Second", description: "v2",
          version: "0000000000000_0000_0000000000000002"),
        now: "2026-03-03T00:00:00.000Z")
      let afterSecond = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM lists") ?? 0
      return (afterFirst, afterSecond, row)
    }
    XCTAssertEqual(countAfterFirst, countAfterSecond)
    XCTAssertEqual(second.name, "Second")
    XCTAssertEqual(second.description, "v2")
    XCTAssertEqual(second.version, "0000000000000_0000_0000000000000002")
    // created_at preserved from the first import; updated_at advanced.
    XCTAssertEqual(second.createdAt.asString, "2026-02-02T00:00:00.000Z")
    XCTAssertEqual(second.updatedAt.asString, "2026-03-03T00:00:00.000Z")
  }

  func testUpsertListForImportRejectsStaleVersionAgainstNewerLocalRow() throws {
    // A peer stamped this row with a future/high HLC; a later import carrying a
    // strictly-lower version must NOT clobber it (the LWW gate protects a known
    // id from a stale-version overwrite that would then replicate fleet-wide).
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try ListRepo.upsertListForImport(
        db,
        params: ListCreateParams(
          id: self.lid("imported-list"), name: "Peer wins", description: "keep me",
          version: "0000000000009_0000_0000000000000000"),
        now: "2026-05-05T00:00:00.000Z")

      XCTAssertThrowsError(
        try ListRepo.upsertListForImport(
          db,
          params: ListCreateParams(
            id: self.lid("imported-list"), name: "Stale clobber", description: "overwrite",
            version: "0000000000001_0000_0000000000000000"),
          now: "2026-05-06T00:00:00.000Z")
      ) { error in
        guard case StoreError.staleVersion = error else {
          return XCTFail("expected staleVersion, got \(error)")
        }
      }

      let row = try XCTUnwrap(try ListRepo.getList(db, id: self.lid("imported-list")))
      XCTAssertEqual(row.name, "Peer wins")
      XCTAssertEqual(row.description, "keep me")
      XCTAssertEqual(row.version, "0000000000009_0000_0000000000000000")
    }
  }

  // MARK: - update_list

  func testUpdateListSingleField() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try ListRepo.createList(
        db, id: self.lid("l1"), name: "Before",
        version: "0000000000000_0000_0000000000000000")
      try ListRepo.updateList(
        db,
        params: ListUpdateParams(
          id: self.lid("l1"), name: "After",
          now: "2026-03-27T00:00:00.000Z", version: "0000000000002_0000_0000000000000002"))
    }
    let row = try store.writer.read { db in
      try ListRepo.getList(db, id: self.lid("l1"))
    }
    XCTAssertEqual(try XCTUnwrap(row).name, "After")
  }

  func testUpdateListNoFieldsIsNoop() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try ListRepo.createList(
        db, id: self.lid("l1"), name: "Same", color: "#ff0000",
        version: "0000000000000_0000_0000000000000000")
      try ListRepo.updateList(
        db,
        params: ListUpdateParams(
          id: self.lid("l1"), now: "2026-03-27T00:00:00.000Z", version: "0000000000002_0000_0000000000000002"))
    }
  }

  func testUpdateListDelegatesToPatched() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try ListRepo.createList(
        db, id: self.lid("l1"), name: "Before", version: "0000000000001_0000_0000000000000001")
      try ListRepo.updateList(
        db,
        params: ListUpdateParams(
          id: self.lid("l1"), name: "After",
          now: "2026-03-27T12:00:00.000Z", version: "0000000000002_0000_0000000000000002"))
    }
    let row = try store.writer.read { db in
      try ListRepo.getList(db, id: self.lid("l1"))
    }
    let r = try XCTUnwrap(row)
    XCTAssertEqual(r.name, "After")
    XCTAssertEqual(r.version, "0000000000002_0000_0000000000000002")
  }

  // MARK: - delete_list

  func testDeleteListReturnsOneOnSuccess() throws {
    let store = try TestSupport.freshStore()
    let deleted = try store.writer.write { db -> Int in
      _ = try ListRepo.createList(
        db, id: self.lid("l1"), name: "Doomed",
        version: "0000000000000_0000_0000000000000000")
      return try ListRepo.deleteList(db, id: self.lid("l1"))
    }
    XCTAssertEqual(deleted, 1)
    let missing = try store.writer.read { db in
      try ListRepo.getList(db, id: self.lid("l1"))
    }
    XCTAssertNil(missing)
  }

  func testDeleteListReturnsZeroForMissing() throws {
    let store = try TestSupport.freshStore()
    let deleted = try store.writer.write { db -> Int in
      try ListRepo.deleteList(db, id: self.lid("nonexistent"))
    }
    XCTAssertEqual(deleted, 0)
  }

  // MARK: - update_list_patched

  func testUpdateListPatchedSetsNullableFields() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try ListRepo.createListWithAiNotes(
        db,
        params: ListCreateParams(
          id: self.lid("l1"), name: "Test", color: "#ff0000",
          icon: "star", description: "desc", aiNotes: "ai",
          version: "0000000000000_0000_0000000000000000"))
      let patch = ListUpdatePatch(
        color: .clear, icon: .clear, description: .set("new desc"))
      try ListRepo.updateListPatched(
        db, id: self.lid("l1"), patch: patch, version: "0000000000002_0000_0000000000000002",
        now: "2026-03-27T00:00:00.000Z")
    }
    let row = try store.writer.read { db in
      try ListRepo.getList(db, id: self.lid("l1"))
    }
    let r = try XCTUnwrap(row)
    XCTAssertNil(r.color)
    XCTAssertNil(r.icon)
    XCTAssertEqual(r.description, "new desc")
    XCTAssertEqual(r.aiNotes, "ai")
    XCTAssertEqual(r.name, "Test")
  }

  func testUpdateListPatchedEmptyPatchIsNoop() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try ListRepo.createList(
        db, id: self.lid("l1"), name: "Test",
        version: "0000000000000_0000_0000000000000000")
      try ListRepo.updateListPatched(
        db, id: self.lid("l1"), patch: ListUpdatePatch(),
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T00:00:00.000Z")
    }
  }

  func testUpdateListPatchedUpdatesName() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try ListRepo.createList(
        db, id: self.lid("l1"), name: "Before",
        version: "0000000000000_0000_0000000000000000")
      try ListRepo.updateListPatched(
        db, id: self.lid("l1"),
        patch: ListUpdatePatch(name: "After"),
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T00:00:00.000Z")
    }
    let row = try store.writer.read { db in
      try ListRepo.getList(db, id: self.lid("l1"))
    }
    XCTAssertEqual(try XCTUnwrap(row).name, "After")
  }

  func testUpdateListPatchedBumpsVersion() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try ListRepo.createList(
        db, id: self.lid("l1"), name: "Test", version: "0000000000001_0000_0000000000000001")
      try ListRepo.updateListPatched(
        db, id: self.lid("l1"),
        patch: ListUpdatePatch(name: "Updated"),
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T12:00:00.000Z")
    }
    let row = try store.writer.read { db in
      try ListRepo.getList(db, id: self.lid("l1"))
    }
    let r = try XCTUnwrap(row)
    XCTAssertEqual(r.version, "0000000000002_0000_0000000000000002")
    XCTAssertEqual(r.name, "Updated")
  }
}
