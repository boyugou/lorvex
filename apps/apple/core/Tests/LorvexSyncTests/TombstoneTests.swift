import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Delete-ledger CRUD and monotonicity, and the permanence of tombstones under
/// the retention sweeps.
final class TombstoneTests: XCTestCase {

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  // MARK: - basic

  func testCreateAndGetTombstone() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-03-23T12:00:00.000Z")
      let ts = try XCTUnwrap(try Tombstone.getTombstone(db, entityType: EntityName.task, entityId: "task-001"))
      XCTAssertEqual(ts.entityType, EntityName.task)
      XCTAssertEqual(ts.entityId, "task-001")
      XCTAssertEqual(ts.version, "1711234567890_0000_a1b2c3d4a1b2c3d4")
      XCTAssertEqual(ts.deletedAt, "2026-03-23T12:00:00.000Z")
    }
  }

  func testGetTombstoneReturnsNilForMissing() throws {
    try withDB { db in
      XCTAssertNil(try Tombstone.getTombstone(db, entityType: EntityName.task, entityId: "nonexistent"))
    }
  }

  func testIsTombstonedTrue() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-03-23T12:00:00.000Z")
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-001"))
    }
  }

  func testIsTombstonedFalse() throws {
    try withDB { db in
      XCTAssertFalse(try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-001"))
    }
  }

  func testReplaceOnReTombstone() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-03-23T12:00:00.000Z")
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: "1711234567999_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-03-23T13:00:00.000Z")
      let ts = try XCTUnwrap(try Tombstone.getTombstone(db, entityType: EntityName.task, entityId: "task-001"))
      XCTAssertEqual(ts.version, "1711234567999_0000_a1b2c3d4a1b2c3d4")
      XCTAssertEqual(ts.deletedAt, "2026-03-23T13:00:00.000Z")
      let count = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.task, "task-001"])
      XCTAssertEqual(count, 1)
    }
  }

  func testRemoveTombstoneSuccess() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-03-23T12:00:00.000Z")
      XCTAssertTrue(try Tombstone.removeTombstone(db, entityType: EntityName.task, entityId: "task-001"))
      XCTAssertFalse(try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-001"))
    }
  }

  func testRemoveTombstoneReturnsFalseForMissing() throws {
    try withDB { db in
      XCTAssertFalse(try Tombstone.removeTombstone(db, entityType: EntityName.task, entityId: "nonexistent"))
    }
  }

  func testTombstonesForDifferentEntityTypesAreIndependent() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "shared-id",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-03-23T12:00:00.000Z")
      try Tombstone.createTombstone(
        db, entityType: EntityName.list, entityId: "shared-id",
        version: "1711234567891_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-03-23T13:00:00.000Z")
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "shared-id"))
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.list, entityId: "shared-id"))
      let taskTs = try XCTUnwrap(try Tombstone.getTombstone(db, entityType: EntityName.task, entityId: "shared-id"))
      let listTs = try XCTUnwrap(try Tombstone.getTombstone(db, entityType: EntityName.list, entityId: "shared-id"))
      XCTAssertEqual(taskTs.version, "1711234567890_0000_a1b2c3d4a1b2c3d4")
      XCTAssertEqual(listTs.version, "1711234567891_0000_a1b2c3d4a1b2c3d4")
    }
  }

  // MARK: - monotonicity

  func testTombstoneMonotonicityOldDoesNotOverwriteNew() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: "task", entityId: "t1", version: "1711234567899_0000_a1b2c3d4a1b2c3d4",
        deletedAt: "2026-03-25T00:00:00Z")
      try Tombstone.createTombstone(
        db, entityType: "task", entityId: "t1", version: "1711234567800_0000_a1b2c3d4a1b2c3d4",
        deletedAt: "2026-03-20T00:00:00Z")
      let ts = try XCTUnwrap(try Tombstone.getTombstone(db, entityType: "task", entityId: "t1"))
      XCTAssertEqual(ts.version, "1711234567899_0000_a1b2c3d4a1b2c3d4")
    }
  }

  func testTombstoneMonotonicityNewerOverwritesOld() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: "task", entityId: "t1", version: "1711234567800_0000_a1b2c3d4a1b2c3d4",
        deletedAt: "2026-03-20T00:00:00Z")
      try Tombstone.createTombstone(
        db, entityType: "task", entityId: "t1", version: "1711234567899_0000_a1b2c3d4a1b2c3d4",
        deletedAt: "2026-03-25T00:00:00Z")
      let ts = try XCTUnwrap(try Tombstone.getTombstone(db, entityType: "task", entityId: "t1"))
      XCTAssertEqual(ts.version, "1711234567899_0000_a1b2c3d4a1b2c3d4")
    }
  }

  /// Replaying the exact delete (same version) keeps the original `deleted_at`.
  func testExactDeleteReplayKeepsOriginalDeletedAt() throws {
    try withDB { db in
      let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: version, deletedAt: "2024-01-01T00:00:00.000Z")
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: version, deletedAt: "2024-01-03T00:00:00.000Z")

      let row = try XCTUnwrap(
        try Tombstone.getTombstone(db, entityType: EntityName.task, entityId: "task-001"))
      XCTAssertEqual(row.version, version)
      XCTAssertEqual(row.deletedAt, "2024-01-01T00:00:00.000Z")
    }
  }

  // MARK: - permanence

  /// Tombstones are kept indefinitely: neither sweep reaps one, whatever its
  /// age, because nothing proves that every device has seen the delete.
  func testRetentionSweepsKeepTombstonesOfEveryAge() throws {
    try withDB { db in
      let ages = ["-1 days", "-30 days", "-200 days", "-400 days"]
      for (index, age) in ages.enumerated() {
        let deletedAt = try XCTUnwrap(
          String.fetchOne(
            db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)", arguments: [age]))
        try Tombstone.createTombstone(
          db, entityType: EntityName.task, entityId: "task-\(index)",
          version: "171123456789\(index)_0000_a1b2c3d4a1b2c3d4", deletedAt: deletedAt)
      }
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-ancient",
        version: "1711234567899_0000_a1b2c3d4a1b2c3d4", deletedAt: "2020-01-01T00:00:00.000Z")

      SyncRetention.runPostApplyGC(db, syncedAt: "2026-04-01T00:00:00.000Z")
      SyncRetention.runLocalMaintenanceGC(
        db, syncedAt: "2026-04-01T00:00:00.000Z", includeActiveOutboxCap: true)

      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 5)
      for id in (0..<ages.count).map({ "task-\($0)" }) + ["task-ancient"] {
        XCTAssertTrue(
          try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: id),
          "\(id) must survive every retention sweep")
      }
    }
  }
}
