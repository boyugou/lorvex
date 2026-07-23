import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Storage-level policy coverage for the frontier-based audit-retention model.
/// Retention physically removes local full-content copies; it never creates a
/// sync tombstone or delete envelope.
final class RetentionGcTests: XCTestCase {
  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func uuid(_ n: Int) -> String {
    "\(String(format: "%08x", n))-0000-7000-8000-000000000000"
  }

  private func insertEntry(
    _ db: Database, id: String, daysAgo: Int, epoch: Int64 = 0,
    account: String? = nil
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO ai_changelog (
          id, timestamp, operation, entity_type, summary, initiated_by,
          retention_epoch, retention_account_identifier
        ) VALUES (
          ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?),
          'create', 'task', 'test summary', 'ai', ?, ?
        )
        """,
      arguments: [id, "-\(daysAgo) days", epoch, account])
  }

  func testDaysPolicyAdvancesCutoffAndPrunesOnlyExpiredRows() throws {
    try withDB { db in
      let recent = self.uuid(1)
      let old = self.uuid(2)
      try self.insertEntry(db, id: recent, daysAgo: 5)
      try self.insertEntry(db, id: old, daysAgo: 100)
      try AuditRetentionFrontier.adoptPolicyForCurrentScope(
        db, policy: .days(30),
        policyVersion: "6000000000000_0001_a1b2c3d4a1b2c3d4")

      XCTAssertEqual(try AuditRetention.gcChangelog(db), 1)
      XCTAssertEqual(
        try String.fetchAll(db, sql: "SELECT id FROM ai_changelog ORDER BY id"),
        [recent])
      let cutoff = try String.fetchOne(
        db,
        sql: """
          SELECT unbound_frontier_cutoff_timestamp
          FROM audit_retention_binding WHERE singleton = 1
          """)
      XCTAssertFalse(try XCTUnwrap(cutoff).isEmpty)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND operation = ?
            """,
          arguments: [EntityName.aiChangelog, SyncNaming.opDelete]),
        0)
      XCTAssertFalse(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.aiChangelog, entityId: old))
    }
  }

  func testOffPolicyPurgesRowsAndCascadesEntityRegistry() throws {
    try withDB { db in
      let id = self.uuid(3)
      try AuditRetentionFrontier.adoptPolicyForCurrentScope(
        db, policy: .off,
        policyVersion: "6000000000000_0002_a1b2c3d4a1b2c3d4")
      try self.insertEntry(db, id: id, daysAgo: 0, epoch: 1)
      try db.execute(
        sql: "INSERT INTO ai_changelog_entities (changelog_id, entity_id) VALUES (?, ?)",
        arguments: [id, "task-1"])

      XCTAssertEqual(try AuditRetention.gcChangelog(db), 1)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog"), 0)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog_entities"), 0)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_retention_purge_queue"), 0,
        "cloud-unseen local rows require no remote delete")
    }
  }

  func testMaximumEntrySafeguardUsesTimestampAndIdTotalOrder() throws {
    try withDB { db in
      let over = 2
      let total = Int(SyncNaming.auditMaxEntriesSafeguard) + over
      for index in 0..<total {
        try db.execute(
          sql: """
            INSERT INTO ai_changelog (
              id, timestamp, operation, entity_type, summary, initiated_by
            ) VALUES (?, '2026-01-01T00:00:00.000Z', 'create', 'task', 'same time', 'ai')
            """,
          arguments: [self.uuid(index)])
      }

      XCTAssertEqual(try AuditRetention.gcChangelog(db), UInt64(over))
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog"),
        Int(SyncNaming.auditMaxEntriesSafeguard))
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT unbound_frontier_cutoff_entity_id
            FROM audit_retention_binding WHERE singleton = 1
            """),
        self.uuid(over))
      XCTAssertEqual(try AuditRetention.gcChangelog(db), 0)
    }
  }

  func testUnboundCanonicalAndDeviceLocalStreamsHaveIndependentBudgetsAndFrontiers() throws {
    try withDB { db in
      let canonicalCount = 9_000
      let localCount = 2_000
      for index in 0..<canonicalCount {
        try db.execute(
          sql: """
            INSERT INTO ai_changelog (
              id, timestamp, operation, entity_type, summary, initiated_by
            ) VALUES (?, '2026-01-01T00:00:00.000Z', 'create', 'task', 'canonical', 'ai')
            """,
          arguments: [self.uuid(index)])
      }
      for index in canonicalCount..<(canonicalCount + localCount) {
        try db.execute(
          sql: """
            INSERT INTO ai_changelog (
              id, timestamp, operation, entity_type, summary, initiated_by
            ) VALUES (?, '2026-01-01T00:00:00.000Z', ?, 'task', 'local only', 'system')
            """,
          arguments: [self.uuid(index), SyncNaming.localAuditCoalescedDeleteDropped])
      }

      XCTAssertEqual(try AuditRetention.gcChangelog(db), 0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM ai_changelog
            WHERE operation != ?
            """,
          arguments: [SyncNaming.localAuditCoalescedDeleteDropped]),
        canonicalCount)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM ai_changelog
            WHERE operation = ?
            """,
          arguments: [SyncNaming.localAuditCoalescedDeleteDropped]),
        localCount)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT unbound_frontier_cutoff_timestamp
            FROM audit_retention_binding WHERE singleton = 1
            """),
        "")

      let activation = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: "icloud-account-a", zoneName: "LorvexData-e1-budget-test")
      XCTAssertEqual(activation.state.frontier, .initial)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM ai_changelog
            WHERE retention_account_identifier = 'icloud-account-a'
            """),
        canonicalCount)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM ai_changelog
            WHERE retention_account_identifier IS NULL AND operation = ?
            """,
          arguments: [SyncNaming.localAuditCoalescedDeleteDropped]),
        localCount)
    }
  }
}
