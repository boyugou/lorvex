import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// The `inbox` list is the schema-designated canonical fallback for orphaned
/// tasks and is reseeded by `schema.sql` on every open, so deleting it corrupts
/// the reseed contract: the local reseed resurrects Inbox UNDER a strictly-newer
/// tombstone while peers keep it deleted. `deleteList` must refuse to delete
/// `inbox` at the workflow layer regardless of task count.
final class SwiftLorvexCoreServiceInboxDeleteGuardTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  func testDeleteInboxListIsRefusedEvenWithZeroTasks() async throws {
    let service = try makeService()
    // A second list so the "last list must exist" guard is not what blocks the
    // delete — the workspace has zero tasks, which the schema trigger permits.
    _ = try await service.createList(
      name: "Work", description: nil, color: nil, icon: nil, aiNotes: nil)

    do {
      try await service.deleteList(id: "inbox")
      XCTFail("deleting the inbox list must throw")
    } catch {
      // expected
    }

    let inboxStillExists = try service.read { db in
      try Bool.fetchOne(db, sql: "SELECT 1 FROM lists WHERE id = 'inbox'") ?? false
    }
    XCTAssertTrue(inboxStillExists, "the inbox list must survive a delete attempt")
  }

  func testDeleteNormalEmptyListStillWorks() async throws {
    let service = try makeService()
    let list = try await service.createList(
      name: "Scratch", description: nil, color: nil, icon: nil, aiNotes: nil)

    try await service.deleteList(id: list.id)

    let (deletedGone, inboxKept) = try service.read { db in
      (
        try Bool.fetchOne(db, sql: "SELECT 1 FROM lists WHERE id = ?", arguments: [list.id]) ?? false,
        try Bool.fetchOne(db, sql: "SELECT 1 FROM lists WHERE id = 'inbox'") ?? false
      )
    }
    XCTAssertFalse(deletedGone, "a normal empty list is deleted")
    XCTAssertTrue(inboxKept, "the inbox list is untouched")
  }
}
