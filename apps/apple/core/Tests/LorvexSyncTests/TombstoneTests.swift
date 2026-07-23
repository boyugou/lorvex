import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ordinary delete-ledger CRUD, monotonicity, and trusted compaction.
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

  func testExactDeleteReplayPreservesCloudConfirmation() throws {
    try withDB { db in
      let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: version, deletedAt: "2024-01-01T00:00:00.000Z")
      XCTAssertTrue(
        try Tombstone.confirmCloudPresence(
          db,
          confirmation: .init(
            entityType: EntityName.task, entityId: "task-001", version: version,
            confirmedAt: "2024-01-02T00:00:00.000Z")))

      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: version, deletedAt: "2024-01-03T00:00:00.000Z")

      let row = try XCTUnwrap(
        try Tombstone.getTombstone(db, entityType: EntityName.task, entityId: "task-001"))
      XCTAssertEqual(row.deletedAt, "2024-01-01T00:00:00.000Z")
      XCTAssertEqual(row.cloudConfirmedAt, "2024-01-02T00:00:00.000Z")
    }
  }

  func testNewerDeleteClearsStaleCloudConfirmation() throws {
    try withDB { db in
      let oldVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      let newVersion = "1711234567891_0000_a1b2c3d4a1b2c3d4"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: oldVersion, deletedAt: "2024-01-01T00:00:00.000Z")
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: "task-001", version: oldVersion,
          confirmedAt: "2024-01-02T00:00:00.000Z"))

      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: newVersion, deletedAt: "2024-01-03T00:00:00.000Z")

      let row = try XCTUnwrap(
        try Tombstone.getTombstone(db, entityType: EntityName.task, entityId: "task-001"))
      XCTAssertEqual(row.version, newVersion)
      XCTAssertNil(row.cloudConfirmedAt)
    }
  }

  func testCloudConfirmationRejectsStaleVersion() throws {
    try withDB { db in
      let currentVersion = "1711234567891_0000_a1b2c3d4a1b2c3d4"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-001",
        version: currentVersion, deletedAt: "2024-01-03T00:00:00.000Z")

      XCTAssertFalse(
        try Tombstone.confirmCloudPresence(
          db,
          confirmation: .init(
            entityType: EntityName.task, entityId: "task-001",
            version: "1711234567890_0000_a1b2c3d4a1b2c3d4",
            confirmedAt: "2024-01-04T00:00:00.000Z")))
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: "task-001")?.cloudConfirmedAt)
    }
  }

  // MARK: - trusted compaction

  func testTrustedCompactionRetainsUnconfirmedAndWithinWindowRows() throws {
    try withDB { db in
      let oldVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      let recentVersion = "1711234567891_0000_a1b2c3d4a1b2c3d4"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-unconfirmed",
        version: oldVersion, deletedAt: "2020-01-01T00:00:00.000Z")
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-recent",
        version: recentVersion, deletedAt: "2020-01-01T00:00:00.000Z")
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: "task-recent", version: recentVersion,
          confirmedAt: "2026-01-01T00:00:00.000Z"))

      XCTAssertEqual(
        try Tombstone.compactCloudConfirmed(db, through: "2025-01-01T00:00:00.000Z"), 0)
      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.task, entityId: "task-unconfirmed"))
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-recent"))
    }
  }

  func testTrustedCompactionDeletesOnlyExactOldDeleteIntent() throws {
    try withDB { db in
      let oldVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      let newerVersion = "1711234567891_0000_a1b2c3d4a1b2c3d4"
      let exactID = "01966a3f-7c8b-7d4e-8f3a-000000000101"
      let newerID = "01966a3f-7c8b-7d4e-8f3a-000000000102"
      for entityID in [exactID, newerID] {
        try Tombstone.createTombstone(
          db, entityType: EntityName.task, entityId: entityID,
          version: oldVersion, deletedAt: "2020-01-01T00:00:00.000Z")
        _ = try Tombstone.confirmCloudPresence(
          db,
          confirmation: .init(
            entityType: EntityName.task, entityId: entityID, version: oldVersion,
            confirmedAt: "2024-01-01T00:00:00.000Z"))
      }
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(
        db,
        SyncEnvelope(
          entityType: .task, entityId: exactID, operation: .delete,
          version: try Hlc.parse(oldVersion), payloadSchemaVersion: 1,
          payload: "{}", deviceId: "device-001"))
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(
        db,
        SyncEnvelope(
          entityType: .task, entityId: newerID, operation: .delete,
          version: try Hlc.parse(newerVersion), payloadSchemaVersion: 1,
          payload: "{}", deviceId: "device-001"))

      XCTAssertEqual(
        try Tombstone.compactCloudConfirmed(db, through: "2025-01-01T00:00:00.000Z"), 2)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?",
          arguments: [exactID]), 0)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT version FROM sync_outbox WHERE entity_id = ?",
          arguments: [newerID]), newerVersion)
    }
  }

  func testTrustedCompactionRetainsPermanentRedirectTargetDeathAndOutboxIntent() throws {
    try withDB { db in
      let targetID = "01966a3f-7c8b-7d4e-8f3a-000000000201"
      let sourceID = "01966a3f-7c8b-7d4e-8f3a-000000000202"
      let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      for id in [targetID, sourceID] {
        try Tombstone.createTombstone(
          db, entityType: EntityName.tag, entityId: id, version: version,
          deletedAt: "2020-01-01T00:00:00.000Z")
        _ = try Tombstone.confirmCloudPresence(
          db,
          confirmation: .init(
            entityType: EntityName.tag, entityId: id, version: version,
            confirmedAt: "2024-01-01T00:00:00.000Z"))
      }
      try db.execute(
        sql: """
          INSERT INTO sync_entity_redirects
              (source_type, source_id, target_id, version, created_at)
          VALUES ('tag', ?, ?, ?, '2024-01-01T00:00:00.000Z')
          """,
        arguments: [sourceID, targetID, version])
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(
        db,
        SyncEnvelope(
          entityType: .tag, entityId: targetID, operation: .delete,
          version: try Hlc.parse(version), payloadSchemaVersion: 1,
          payload: "{}", deviceId: "device-001"))

      XCTAssertEqual(
        try Tombstone.compactCloudConfirmed(
          db, through: "2025-01-01T00:00:00.000Z"),
        1, "the unreferenced source death may compact; its target death may not")
      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.tag, entityId: targetID))
      XCTAssertFalse(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.tag, entityId: sourceID))
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'tag' AND entity_id = ?",
          arguments: [targetID]),
        1, "the retained target death must keep its matching outbound intent")
    }
  }

  func testTrustedCutoffUsesOnlyBoundAccountServerTime() throws {
    try withDB { db in
      let account = "tombstone-account"
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: account, boundAt: "2026-01-01T00:00:00.000Z")
      let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-old",
        version: version, deletedAt: "2020-01-01T00:00:00.000Z")

      XCTAssertNil(
        try Tombstone.trustedCompactionCutoff(
          db, accountIdentifier: account, recoveryDays: 365),
        "an ancient local deleted_at is not trusted aging evidence")

      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: "task-old", version: version,
          confirmedAt: "2025-01-01T00:00:00.000Z"))
      try Tombstone.observeTrustedServerTime(
        db, accountIdentifier: account, serverTime: "2026-01-01T00:00:00.000Z")
      XCTAssertEqual(
        try Tombstone.trustedCompactionCutoff(
          db, accountIdentifier: account, recoveryDays: 365),
        "2025-01-01T00:00:00.000Z")
      XCTAssertThrowsError(
        try Tombstone.observeTrustedServerTime(
          db, accountIdentifier: "different-account",
          serverTime: "2027-01-01T00:00:00.000Z")) { error in
          XCTAssertEqual(error as? TombstoneConfirmationError, .accountBoundaryMismatch)
        }
    }
  }

  func testTrustedCutoffDoesNotRotateForRedirectTargetDeathAlone() throws {
    try withDB { db in
      let account = "redirect-target-only-account"
      let targetID = "01966a3f-7c8b-7d4e-8f3a-000000000301"
      let sourceID = "01966a3f-7c8b-7d4e-8f3a-000000000302"
      let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: account, boundAt: "2026-01-01T00:00:00.000Z")
      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: targetID, version: version,
        deletedAt: "2020-01-01T00:00:00.000Z")
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.tag, entityId: targetID, version: version,
          confirmedAt: "2024-01-01T00:00:00.000Z"))
      try db.execute(
        sql: """
          INSERT INTO sync_entity_redirects
              (source_type, source_id, target_id, version, created_at)
          VALUES ('tag', ?, ?, ?, '2024-01-01T00:00:00.000Z')
          """,
        arguments: [sourceID, targetID, version])
      try Tombstone.observeTrustedServerTime(
        db, accountIdentifier: account,
        serverTime: "2026-01-01T00:00:00.000Z")

      XCTAssertNil(
        try Tombstone.trustedCompactionCutoff(
          db, accountIdentifier: account, recoveryDays: 365),
        "an uncollectable alias target must not trigger an empty generation rotation")
    }
  }

  // MARK: - gc_watermark

  /// Ordinary maintenance has no authority to collect a delete marker; only a
  /// server-confirmed generation transition may do so.
  func testGcRetainsRecentAndAncientTombstones() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-recent",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-03-15T00:00:00.000Z")
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-ancient",
        version: "1711234567891_0000_a1b2c3d4a1b2c3d4", deletedAt: "2020-01-01T00:00:00.000Z")
      XCTAssertEqual(try Tombstone.gcTombstonesWatermark(db), 0)
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-recent"))
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-ancient"))
    }
  }

  /// Device wall-clock age alone never collects the ledger.
  func testGcRetainsAgedTombstones() throws {
    try withDB { db in
      let twoHundredDaysAgo = try String.fetchOne(
        db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-200 days')")!
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-200d",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deletedAt: twoHundredDaysAgo)
      let thirtyDaysAgo = try String.fetchOne(
        db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-30 days')")!
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-30d",
        version: "1711234567891_0000_a1b2c3d4a1b2c3d4", deletedAt: thirtyDaysAgo)
      XCTAssertEqual(try Tombstone.gcTombstonesWatermark(db), 0)
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-200d"))
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-30d"))
    }
  }

  /// Direct regression pin that an ancient local timestamp cannot impersonate
  /// CloudKit confirmation or a completed generation boundary.
  func testGcTombstonesWatermarkRetainsWithoutCloudAuthority() throws {
    try withDB { db in
      let ancient = try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-400 days')"))
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-permanent",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deletedAt: ancient)
      XCTAssertEqual(try Tombstone.gcTombstonesWatermark(db), 0)
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-permanent"),
        "ordinary local maintenance cannot reap a tombstone")
    }
  }
}
