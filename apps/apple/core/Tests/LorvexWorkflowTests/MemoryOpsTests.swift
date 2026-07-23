import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexWorkflow

/// Covers the last-write-wins KV upsert / rename / delete semantics of
/// ``MemoryOps``.
final class MemoryOpsTests: XCTestCase {
  func testUpsertCreatesMemory() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      let result = try XCTUnwrap(
        try MemoryOps.upsertMemoryEntry(
          db, key: "user_profile", content: "likes coffee", version: "0000000000001_0000_0000000000000001",
          now: "2026-03-27T10:00:00Z"))
      XCTAssertEqual(result.memoryKey, "user_profile")

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: "SELECT content, version, updated_at FROM memories WHERE key = 'user_profile'"))
      XCTAssertEqual(row[0] as String, "likes coffee")
      XCTAssertEqual(row[1] as String, "0000000000001_0000_0000000000000001")
      XCTAssertEqual(row[2] as String, "2026-03-27T10:00:00Z")
    }
  }

  func testUpsertUpdatesExisting() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      let first = try XCTUnwrap(
        try MemoryOps.upsertMemoryEntry(
          db, key: "user_profile", content: "likes coffee", version: "0000000000001_0000_0000000000000001",
          now: "2026-03-27T10:00:00Z"))
      let second = try XCTUnwrap(
        try MemoryOps.upsertMemoryEntry(
          db, key: "user_profile", content: "likes tea now", version: "0000000000002_0000_0000000000000002",
          now: "2026-03-27T11:00:00Z"))
      let content = try String.fetchOne(
        db, sql: "SELECT content FROM memories WHERE key = 'user_profile'")
      XCTAssertEqual(content, "likes tea now")
      // Editing an existing key MUST keep the same opaque id — a churning id
      // would rewrite the CloudKit entity_id per edit and break LWW convergence.
      XCTAssertEqual(second.memoryId, first.memoryId)
      let storedId = try String.fetchOne(
        db, sql: "SELECT id FROM memories WHERE key = 'user_profile'")
      XCTAssertEqual(storedId, first.memoryId)
    }
  }

  func testDeleteRemoves() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      let created = try XCTUnwrap(
        try MemoryOps.upsertMemoryEntry(
          db, key: "user_profile", content: "some content", version: "0000000000001_0000_0000000000000001",
          now: "2026-03-27T10:00:00Z"))
      let del = try XCTUnwrap(
        try MemoryOps.deleteMemoryEntry(db, key: "user_profile", version: "0000000000002_0000_0000000000000002"))
      XCTAssertEqual(del.memoryKey, "user_profile")
      // The delete envelope routes on the same opaque id the create minted.
      XCTAssertEqual(del.memoryId, created.memoryId)
      XCTAssertEqual(
        del.preDeletePayload,
        .object([
          "id": .string(created.memoryId),
          "key": .string("user_profile"),
          "content": .string("some content"),
          "version": .string("0000000000001_0000_0000000000000001"),
          "updated_at": .string("2026-03-27T10:00:00Z"),
        ]))

      let count = try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM memories WHERE key = 'user_profile'")
      XCTAssertEqual(count, 0)
    }
  }

  func testDeleteReturnsNoneWhenKeyMissing() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      let result = try MemoryOps.deleteMemoryEntry(db, key: "never_existed", version: "0000000000001_0000_0000000000000001")
      XCTAssertNil(result)
    }
  }

  func testUpsertRejectsStaleVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      _ = try XCTUnwrap(
        try MemoryOps.upsertMemoryEntry(
          db, key: "user_profile", content: "newer remote write", version: "0000000000002_0000_0000000000000002",
          now: "2026-03-27T11:00:00Z"))

      let result = try MemoryOps.upsertMemoryEntry(
        db, key: "user_profile", content: "stale local clobber", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-26T00:00:00Z")
      XCTAssertNil(result)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT content, version FROM memories WHERE key = 'user_profile'"))
      XCTAssertEqual(row[0] as String, "newer remote write")
      XCTAssertEqual(row[1] as String, "0000000000002_0000_0000000000000002")
    }
  }

  /// A delete the LWW gate refuses (the stored version dominates the incoming
  /// stamp — a future-stamped row) throws ``StoreError/staleVersion`` rather than
  /// returning nil, so the write-surface retry can advance the clock and let the
  /// explicit local delete supersede the row (SYNC17-HIGH-2). The row stays
  /// untouched on the refusal.
  func testDeleteRejectsStaleVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      _ = try XCTUnwrap(
        try MemoryOps.upsertMemoryEntry(
          db, key: "user_profile", content: "peer wrote v5", version: "0000000000005_0000_0000000000000005",
          now: "2026-03-27T15:00:00Z"))

      XCTAssertThrowsError(
        try MemoryOps.deleteMemoryEntry(db, key: "user_profile", version: "0000000000003_0000_0000000000000003")
      ) { error in
        guard case StoreError.staleVersion = error else {
          return XCTFail("a refused delete must throw staleVersion, got \(error)")
        }
      }

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT content, version FROM memories WHERE key = 'user_profile'"))
      XCTAssertEqual(row[0] as String, "peer wrote v5")
      XCTAssertEqual(row[1] as String, "0000000000005_0000_0000000000000005")
    }
  }

  func testRenamePreservesId() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      let created = try XCTUnwrap(
        try MemoryOps.upsertMemoryEntry(
          db, key: "old_key", content: "body one", version: "0000000000001_0000_0000000000000001",
          now: "2026-03-27T10:00:00Z"))
      _ = try MemoryOps.upsertMemoryEntry(
        db, key: "old_key", content: "body two", version: "0000000000002_0000_0000000000000002",
        now: "2026-03-27T10:05:00Z")

      let renamed = try XCTUnwrap(
        try MemoryOps.renameMemoryEntry(
          db, oldKey: "old_key", newKey: "new_key", content: nil, version: "0000000000003_0000_0000000000000003",
          now: "2026-03-27T11:00:00Z"))

      // Same opaque id — one in-place record edit, not a create + tombstone.
      XCTAssertEqual(renamed.memoryId, created.memoryId)
      XCTAssertEqual(renamed.memoryKey, "new_key")

      // The row moved to new_key with its content preserved (content: nil).
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT key, content FROM memories WHERE id = ?", arguments: [created.memoryId]))
      XCTAssertEqual(row[0] as String, "new_key")
      XCTAssertEqual(row[1] as String, "body two")
      XCTAssertNil(try String.fetchOne(db, sql: "SELECT id FROM memories WHERE key = 'old_key'"))
    }
  }

  func testRenameReplacesContentWhenProvided() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      _ = try MemoryOps.upsertMemoryEntry(
        db, key: "k", content: "old body", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T10:00:00Z")
      _ = try XCTUnwrap(
        try MemoryOps.renameMemoryEntry(
          db, oldKey: "k", newKey: "k2", content: "new body", version: "0000000000002_0000_0000000000000002",
          now: "2026-03-27T11:00:00Z"))
      let content = try String.fetchOne(db, sql: "SELECT content FROM memories WHERE key = 'k2'")
      XCTAssertEqual(content, "new body")
    }
  }

  func testRenameOfMissingKeyReturnsNil() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      let result = try MemoryOps.renameMemoryEntry(
        db, oldKey: "never_existed", newKey: "x", content: nil, version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T10:00:00Z")
      XCTAssertNil(result)
    }
  }

  func testRenameRejectsStaleVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      _ = try MemoryOps.upsertMemoryEntry(
        db, key: "k", content: "c", version: "0000000000005_0000_0000000000000005",
        now: "2026-03-27T10:00:00Z")
      // A rename stamped OLDER than the row's version is a future-stamped-row
      // refusal → staleVersion (mirrors delete), so the write-surface retries.
      XCTAssertThrowsError(
        try MemoryOps.renameMemoryEntry(
          db, oldKey: "k", newKey: "k2", content: nil, version: "0000000000001_0000_0000000000000001",
          now: "2026-03-27T09:00:00Z"))
    }
  }
}
