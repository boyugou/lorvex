import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// Renaming a memory key is a single atomic, id-preserving core operation — one
/// in-place record edit whose sync-routing identity (the opaque `memories.id`)
/// never changes — not the old upsert-under-a-new-key + delete-old-key pair, which
/// minted a second record, tombstoned the first, and could leave both present on a
/// crash between the two writes.
final class SwiftLorvexCoreServiceMemoryRenameTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  func testRenameIsOneInPlaceRecordEditNotACreatePlusTombstone() async throws {
    let service = try makeService()
    _ = try await service.upsertMemory(key: "profile", content: "likes coffee")
    let originalId = try service.read { db in
      try String.fetchOne(db, sql: "SELECT id FROM memories WHERE key = 'profile'")
    }

    let renamed = try await service.renameMemory(
      oldKey: "profile", newKey: "user_profile", content: nil)
    XCTAssertEqual(renamed.key, "user_profile")

    // The row kept its opaque id (in-place edit) and the old key is gone.
    let (newId, oldGone, content) = try service.read { db in
      (
        try String.fetchOne(db, sql: "SELECT id FROM memories WHERE key = 'user_profile'"),
        try String.fetchOne(db, sql: "SELECT id FROM memories WHERE key = 'profile'") == nil,
        try String.fetchOne(db, sql: "SELECT content FROM memories WHERE key = 'user_profile'")
      )
    }
    XCTAssertEqual(newId, originalId, "rename preserves the opaque memory id")
    XCTAssertTrue(oldGone, "the old key no longer resolves to a row")
    XCTAssertEqual(content, "likes coffee", "content is carried forward when not replaced")

    let pending = try service.pendingOutbound()
    // No memory tombstone — the whole point vs the old upsert-new + delete-old.
    let memoryDeletes = pending.filter {
      $0.envelope.entityType == .memory && $0.envelope.operation == .delete
    }
    XCTAssertTrue(memoryDeletes.isEmpty, "an atomic rename must not tombstone any memory record")
    // Every memory upsert routes on the preserved id — never a freshly-minted one.
    let memoryUpserts = pending.filter {
      $0.envelope.entityType == .memory && $0.envelope.operation == .upsert
    }
    XCTAssertFalse(memoryUpserts.isEmpty, "the rename enqueues the memory record upsert")
    XCTAssertTrue(
      memoryUpserts.allSatisfy { $0.envelope.entityId == originalId },
      "the memory envelope routes on the preserved opaque id, not a new record")

    // Exactly one 'rename' changelog row — not a separate upsert + delete pair.
    let renameRows = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE operation = 'rename'")
        ?? 0
    }
    XCTAssertEqual(renameRows, 1)
  }

  func testRenameOntoExistingDifferentKeyIsRejected() async throws {
    let service = try makeService()
    _ = try await service.upsertMemory(key: "a", content: "aaa")
    _ = try await service.upsertMemory(key: "b", content: "bbb")
    do {
      _ = try await service.renameMemory(oldKey: "a", newKey: "b", content: nil)
      XCTFail("rename onto an existing different key must be rejected")
    } catch let LorvexCoreError.conflict(message) {
      XCTAssertTrue(message.contains("already exists"), "got: \(message)")
    }
    // Both entries survive untouched.
    let (aExists, bContent) = try service.read { db in
      (
        try String.fetchOne(db, sql: "SELECT id FROM memories WHERE key = 'a'") != nil,
        try String.fetchOne(db, sql: "SELECT content FROM memories WHERE key = 'b'")
      )
    }
    XCTAssertTrue(aExists, "the source memory is untouched on a rejected rename")
    XCTAssertEqual(bContent, "bbb", "the target memory is untouched on a rejected rename")
  }

  func testRenameOfMissingMemoryThrowsNotFound() async throws {
    let service = try makeService()
    do {
      _ = try await service.renameMemory(oldKey: "ghost", newKey: "x", content: nil)
      XCTFail("renaming a non-existent memory must throw")
    } catch let LorvexCoreError.notFound(entity, id) {
      // A name-keyed lookup miss is a typed `.notFound` (MCP wire code
      // `not_found`), carrying the human key as `id`.
      XCTAssertEqual(entity, .memory)
      XCTAssertEqual(id, "ghost")
      XCTAssertEqual(
        LorvexCoreError.notFound(entity: entity, id: id).errorDescription,
        "Memory 'ghost' not found.")
    }
  }
}
