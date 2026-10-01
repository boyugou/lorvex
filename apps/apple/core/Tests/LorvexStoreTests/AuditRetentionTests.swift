import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Device-local audit retention: the policy stored in `device_state`, the
/// record/no-record decision, and the pruning of `ai_changelog`. The audit
/// trail never leaves the device, so pruning is a plain local delete.
final class AuditRetentionTests: XCTestCase {
  private let policyKey = PreferenceKeys.prefAiChangelogRetentionPolicy

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func uuid(_ n: Int) -> String {
    "\(String(format: "%08x", n))-0000-7000-8000-000000000000"
  }

  private func insertEntry(_ db: Database, id: String, daysAgo: Int) throws {
    try db.execute(
      sql: """
        INSERT INTO ai_changelog (id, timestamp, operation, entity_type, summary, initiated_by)
        VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?),
                'create', 'task', 'test summary', 'ai')
        """,
      arguments: [id, "-\(daysAgo) days"])
  }

  private func storedPolicyValue(_ db: Database) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT value FROM device_state WHERE key = ?", arguments: [policyKey])
  }

  private func changelogIds(_ db: Database) throws -> [String] {
    try String.fetchAll(db, sql: "SELECT id FROM ai_changelog ORDER BY id")
  }

  // MARK: - Stored policy

  func testAbsentRowReadsAsMaximum() throws {
    try withDB { db in
      XCTAssertNil(try self.storedPolicyValue(db))
      XCTAssertEqual(AuditRetention.policy(db), .maximum)
      XCTAssertEqual(ChangelogRetentionPolicy.read(db), .maximum)
    }
  }

  func testSetPolicyStoresTheWireValueAndReadsItBack() throws {
    try withDB { db in
      try AuditRetention.setPolicy(db, .days(30))
      XCTAssertEqual(try self.storedPolicyValue(db), "30")
      XCTAssertEqual(AuditRetention.policy(db), .days(30))
      XCTAssertEqual(ChangelogRetentionPolicy.read(db), .days(30))

      try AuditRetention.setPolicy(db, .off)
      XCTAssertEqual(try self.storedPolicyValue(db), "\"off\"")
      XCTAssertEqual(AuditRetention.policy(db), .off)

      try AuditRetention.setPolicy(db, .days(7))
      XCTAssertEqual(try self.storedPolicyValue(db), "7")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM device_state WHERE key = ?", arguments: [self.policyKey]),
        1, "updating the policy replaces its row rather than adding another")
    }
  }

  func testSetPolicyMaximumRemovesTheStoredRow() throws {
    try withDB { db in
      try AuditRetention.setPolicy(db, .days(30))
      XCTAssertNotNil(try self.storedPolicyValue(db))

      try AuditRetention.setPolicy(db, .maximum)
      XCTAssertNil(try self.storedPolicyValue(db))
      XCTAssertEqual(AuditRetention.policy(db), .maximum)

      // Storing maximum with no row present is a no-op, not an error.
      try AuditRetention.setPolicy(db, .maximum)
      XCTAssertNil(try self.storedPolicyValue(db))
    }
  }

  func testSetPolicyLeavesOtherDeviceStateRowsUntouched() throws {
    try withDB { db in
      try db.execute(
        sql: "INSERT INTO device_state (key, value) VALUES ('unrelated_key', '\"keep\"')")
      try AuditRetention.setPolicy(db, .off)
      try AuditRetention.setPolicy(db, .maximum)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT value FROM device_state WHERE key = 'unrelated_key'"),
        "\"keep\"")
    }
  }

  func testMalformedStoredValueReadsAsMaximumAndNeverPurges() throws {
    try withDB { db in
      let malformed = [
        "", "   ", "not json", "null", "true", "\"forever\"", "0", "-5", "1.5",
        "4294967296", "[30]", "{\"days\":30}",
      ]
      try self.insertEntry(db, id: self.uuid(1), daysAgo: 500)
      for raw in malformed {
        try db.execute(
          sql: """
            INSERT INTO device_state (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
          arguments: [self.policyKey, raw])
        XCTAssertEqual(AuditRetention.policy(db), .maximum, "stored value \(raw.debugDescription)")
        XCTAssertTrue(AuditRetention.recordsAudit(db), "stored value \(raw.debugDescription)")
        XCTAssertEqual(
          try AuditRetention.gcChangelog(db), 0,
          "a malformed stored value must not purge (value \(raw.debugDescription))")
      }
      XCTAssertEqual(try self.changelogIds(db), [self.uuid(1)])
    }
  }

  func testRecordsAuditIsFalseOnlyUnderOff() throws {
    try withDB { db in
      XCTAssertTrue(AuditRetention.recordsAudit(db), "absent row is maximum")

      try AuditRetention.setPolicy(db, .off)
      XCTAssertFalse(AuditRetention.recordsAudit(db))

      try AuditRetention.setPolicy(db, .days(1))
      XCTAssertTrue(AuditRetention.recordsAudit(db))

      try AuditRetention.setPolicy(db, .maximum)
      XCTAssertTrue(AuditRetention.recordsAudit(db))
    }
  }

  // MARK: - gcChangelog

  func testDaysPolicyRemovesOnlyRowsOlderThanTheWindow() throws {
    try withDB { db in
      let fresh = self.uuid(1)
      let nearEdge = self.uuid(2)
      let justExpired = self.uuid(3)
      let old = self.uuid(4)
      try self.insertEntry(db, id: fresh, daysAgo: 0)
      try self.insertEntry(db, id: nearEdge, daysAgo: 29)
      try self.insertEntry(db, id: justExpired, daysAgo: 31)
      try self.insertEntry(db, id: old, daysAgo: 100)
      try db.execute(
        sql: "INSERT INTO ai_changelog_entities (changelog_id, entity_id) VALUES (?, 'task-1')",
        arguments: [old])
      try db.execute(
        sql: "INSERT INTO ai_changelog_entities (changelog_id, entity_id) VALUES (?, 'task-2')",
        arguments: [nearEdge])
      try AuditRetention.setPolicy(db, .days(30))

      XCTAssertEqual(try AuditRetention.gcChangelog(db), 2)
      XCTAssertEqual(try self.changelogIds(db), [fresh, nearEdge].sorted())
      XCTAssertEqual(
        try String.fetchAll(db, sql: "SELECT changelog_id FROM ai_changelog_entities"),
        [nearEdge], "entity links of pruned rows cascade away; kept rows keep theirs")
      XCTAssertEqual(try AuditRetention.gcChangelog(db), 0, "a second pass removes nothing")
    }
  }

  func testDaysPolicyCreatesNoSyncStateForPrunedRows() throws {
    try withDB { db in
      let old = self.uuid(1)
      try self.insertEntry(db, id: old, daysAgo: 100)
      try AuditRetention.setPolicy(db, .days(30))

      XCTAssertEqual(try AuditRetention.gcChangelog(db), 1)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0)
    }
  }

  func testOffPolicyRemovesEveryRowAndCascadesEntityLinks() throws {
    try withDB { db in
      for (index, daysAgo) in [0, 1, 400].enumerated() {
        let id = self.uuid(index)
        try self.insertEntry(db, id: id, daysAgo: daysAgo)
        try db.execute(
          sql: "INSERT INTO ai_changelog_entities (changelog_id, entity_id) VALUES (?, ?)",
          arguments: [id, "task-\(index)"])
      }
      try AuditRetention.setPolicy(db, .off)

      XCTAssertEqual(try AuditRetention.gcChangelog(db), 3)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog"), 0)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog_entities"), 0)
      XCTAssertEqual(try AuditRetention.gcChangelog(db), 0)
    }
  }

  func testMaximumPolicyKeepsEveryRowBelowTheSafeguard() throws {
    try withDB { db in
      try self.insertEntry(db, id: self.uuid(1), daysAgo: 0)
      try self.insertEntry(db, id: self.uuid(2), daysAgo: 3_650)
      XCTAssertEqual(AuditRetention.policy(db), .maximum)

      XCTAssertEqual(try AuditRetention.gcChangelog(db), 0)
      XCTAssertEqual(try self.changelogIds(db), [self.uuid(1), self.uuid(2)])
    }
  }

  func testSafeguardCapKeepsNewestRowsByTimestampThenIdDescending() throws {
    try withDB { db in
      let cap = Int(SyncNaming.auditMaxEntriesSafeguard)
      let over = 2
      // Every row shares one timestamp, so the id alone orders them: the rows
      // with the smallest ids are the oldest and are the ones removed.
      try db.execute(
        sql: """
          WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i + 1 < ?)
          INSERT INTO ai_changelog (id, timestamp, operation, entity_type, summary, initiated_by)
          SELECT printf('%08x-0000-7000-8000-000000000000', i), '2026-01-01T00:00:00.000Z',
                 'create', 'task', 'same time', 'ai'
          FROM n
          """,
        arguments: [cap + over])
      try db.execute(
        sql: "INSERT INTO ai_changelog_entities (changelog_id, entity_id) VALUES (?, 'task-x')",
        arguments: [self.uuid(0)])

      XCTAssertEqual(try AuditRetention.gcChangelog(db), UInt64(over))
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog"), cap)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT MIN(id) FROM ai_changelog"), self.uuid(over))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id IN (?, ?)",
          arguments: [self.uuid(0), self.uuid(1)]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog_entities"), 0,
        "entity links of capped rows cascade away")
      XCTAssertEqual(try AuditRetention.gcChangelog(db), 0)
    }
  }

  func testSafeguardCapOrdersByTimestampBeforeId() throws {
    try withDB { db in
      let cap = Int(SyncNaming.auditMaxEntriesSafeguard)
      let over = 2
      let total = cap + over
      // Row `i` has timestamp `base + i seconds` but the id `total - i`, so the
      // oldest rows carry the largest ids: timestamp order, not id order, picks
      // the survivors.
      try db.execute(
        sql: """
          WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i + 1 < ?)
          INSERT INTO ai_changelog (id, timestamp, operation, entity_type, summary, initiated_by)
          SELECT printf('%08x-0000-7000-8000-000000000000', ? - i),
                 strftime('%Y-%m-%dT%H:%M:%fZ', '2026-01-01T00:00:00', '+' || i || ' seconds'),
                 'create', 'task', 'ordered', 'ai'
          FROM n
          """,
        arguments: [total, total])

      XCTAssertEqual(try AuditRetention.gcChangelog(db), UInt64(over))
      // Rows i = 0 and i = 1 (ids `total` and `total - 1`) are the two oldest.
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id IN (?, ?)",
          arguments: [self.uuid(total), self.uuid(total - 1)]),
        0)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT MAX(id) FROM ai_changelog"),
        self.uuid(total - over))
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog"), cap)
    }
  }

  func testDaysPolicyAlsoAppliesTheSafeguardCap() throws {
    try withDB { db in
      let cap = Int(SyncNaming.auditMaxEntriesSafeguard)
      // All rows are recent, so the window keeps them all and only the cap trims.
      try db.execute(
        sql: """
          WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i + 1 < ?)
          INSERT INTO ai_changelog (id, timestamp, operation, entity_type, summary, initiated_by)
          SELECT printf('%08x-0000-7000-8000-000000000000', i),
                 strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                 'create', 'task', 'recent', 'ai'
          FROM n
          """,
        arguments: [cap + 3])
      try AuditRetention.setPolicy(db, .days(30))

      XCTAssertEqual(try AuditRetention.gcChangelog(db), 3)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog"), cap)
    }
  }
}
