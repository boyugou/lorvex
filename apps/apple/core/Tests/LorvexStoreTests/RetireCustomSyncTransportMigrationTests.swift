import Foundation
import GRDB
import XCTest

@testable import LorvexStore

/// Migration `002_retire_custom_sync_transport`: a database created from the
/// version-1 baseline, carrying rows in the retired shapes, is upgraded in place
/// by the ladder. Each test seeds a baseline-only on-disk database, closes it,
/// and reopens the same file with the canonical migrations registered.
final class RetireCustomSyncTransportMigrationTests: XCTestCase {
  private let hlc = "1800000000000_0000_1111222233334444"
  private let timestamp = "2026-07-15T00:00:00.000Z"
  private let policyKey = "ai_changelog_retention_policy"

  private let retiredTables = [
    "sync_cloudkit_account_binding", "sync_cloudkit_authority_witness",
    "sync_cloudkit_generation_descriptor", "sync_cloudkit_traversal_progress",
    "sync_cloudkit_traversal_witness", "sync_cloudkit_incremental_cursor",
    "sync_cloudkit_corrupt_record_fences", "sync_generation_snapshot_staging",
    "sync_generation_snapshot_items", "sync_generation_snapshot_readback_items",
    "sync_generation_snapshot_tombstone_receipts",
    "sync_generation_snapshot_compacted_tombstones", "sync_authoritative_snapshot",
    "sync_authoritative_snapshot_records", "audit_retention_binding",
    "audit_retention_account_state", "audit_retention_candidate_authorization",
    "audit_retention_outbound_authorization", "audit_retention_purge_queue",
    "audit_changelog_cloud_presence",
  ]

  // MARK: - Fixtures

  private struct Fixture {
    let directory: URL
    let databaseURL: URL
    let schema: String
    let schemaChecksum: String
    let migrations: [LorvexStore.SchemaMigration]

    func openBaselineOnly() throws -> LorvexStore {
      try LorvexStore.open(
        at: databaseURL, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [])
    }

    func openWithLadder() throws -> LorvexStore {
      try LorvexStore.open(
        at: databaseURL, schemaSQL: schema, schemaChecksum: schemaChecksum,
        migrations: migrations)
    }
  }

  private func makeFixture() throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-retire-transport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let schema = try TestSupport.loadSchemaSQL()
    return Fixture(
      directory: directory,
      databaseURL: directory.appendingPathComponent("db.sqlite"),
      schema: schema,
      schemaChecksum: MigrationSqlChecksum.hexDigest(schema),
      migrations: try TestSupport.loadSchemaMigrations())
  }

  /// Seed a baseline-only database, close it, and return the reopened
  /// post-ladder store.
  private func migrate(
    _ fixture: Fixture, seed: (Database) throws -> Void
  ) throws -> LorvexStore {
    let baseline = try fixture.openBaselineOnly()
    XCTAssertNil(baseline.recovery)
    try baseline.writer.write { db in
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"), 1,
        "the seed database must sit at the baseline version")
      try seed(db)
    }
    try baseline.writer.close()

    let migrated = try fixture.openWithLadder()
    XCTAssertNil(migrated.recovery, "a healthy upgrade must not quarantine the database")
    return migrated
  }

  private func insertOutboxRow(
    _ db: Database, entityType: String, entityId: String, operation: String = "upsert"
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO sync_outbox
            (entity_type, entity_id, operation, version, payload_schema_version,
             payload, device_id)
        VALUES (?, ?, ?, ?, 1, '{}', 'migration-test-device')
        """,
      arguments: [entityType, entityId, operation, hlc])
  }

  private func tableNames(_ db: Database) throws -> Set<String> {
    Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
  }

  private func columnNames(_ db: Database, _ table: String) throws -> Set<String> {
    Set(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('\(table)')"))
  }

  private func deviceStatePolicy(_ db: Database) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT value FROM device_state WHERE key = ?", arguments: [policyKey])
  }

  // MARK: - Tests

  /// The end-to-end upgrade: retired tables disappear, the audit outbox row is
  /// dropped while the ordinary outbox row keeps its id, the unbound retention
  /// policy moves into `device_state`, the audit row and its entity link
  /// survive, the retired checkpoint keys go, and the database stays
  /// foreign-key consistent.
  func testLadderRetiresTransportStateAndKeepsUserData() throws {
    let fixture = try makeFixture()
    let taskId = "01966a3f-7c8b-7d4e-8f3a-0000000000a1"
    var taskOutboxId: Int64 = 0

    let migrated = try migrate(fixture) { db in
      try self.insertOutboxRow(db, entityType: "ai_changelog", entityId: "audit-outbox-1")
      try self.insertOutboxRow(db, entityType: "task", entityId: taskId)
      taskOutboxId = try XCTUnwrap(
        Int64.fetchOne(
          db, sql: "SELECT id FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [taskId]))

      try db.execute(
        sql: """
          INSERT INTO sync_pending_inbox
              (envelope, reason, envelope_entity_type, envelope_entity_id,
               envelope_version, first_attempted_at, last_attempted_at)
          VALUES ('{}', 'waiting', ?, ?, ?, ?, ?)
          """,
        arguments: ["ai_changelog", "audit-pending-1", self.hlc, self.timestamp, self.timestamp])
      try db.execute(
        sql: """
          INSERT INTO sync_pending_inbox
              (envelope, reason, envelope_entity_type, envelope_entity_id,
               envelope_version, first_attempted_at, last_attempted_at)
          VALUES ('{}', 'waiting', 'task', 'pending-task-1', ?, ?, ?)
          """,
        arguments: [self.hlc, self.timestamp, self.timestamp])

      try db.execute(
        sql: "UPDATE audit_retention_binding SET unbound_policy_value = '30' WHERE singleton = 1")

      try db.execute(
        sql: """
          INSERT INTO ai_changelog
              (id, timestamp, operation, entity_type, summary, initiated_by,
               retention_epoch, retention_account_identifier)
          VALUES ('audit-row-1', ?, 'create', 'task', 'created a task', 'ai', 4, 'icloud-account')
          """,
        arguments: [self.timestamp])
      try db.execute(
        sql: """
          INSERT INTO ai_changelog_entities (changelog_id, entity_id)
          VALUES ('audit-row-1', ?)
          """,
        arguments: [taskId])

      for (key, value) in [
        ("enrolled_zone_epoch.zone-a", "3"),
        ("cloudkit_per_record_fetch_failure_count", "2"),
        ("cloudkit_per_record_fetch_failure_checkpoint", "record-x"),
        // Not retired: a key that only resembles the retired prefix, and an
        // unrelated checkpoint.
        ("enrolledXzoneXepoch.zone-a", "keep-lookalike"),
        ("unrelated_checkpoint", "keep"),
      ] {
        try db.execute(
          sql: "INSERT INTO sync_checkpoints (key, value) VALUES (?, ?)",
          arguments: [key, value])
      }

      try db.execute(
        sql: """
          INSERT INTO sync_tombstones
              (entity_type, entity_id, version, deleted_at, cloud_confirmed_at)
          VALUES ('task', 'dead-task-1', ?, ?, ?)
          """,
        arguments: [self.hlc, self.timestamp, self.timestamp])
    }

    try migrated.writer.read { db in
      // Retired tables are gone; the surviving control tables remain.
      let tables = try self.tableNames(db)
      for table in self.retiredTables {
        XCTAssertFalse(tables.contains(table), "\(table) must be dropped")
      }
      for table in [
        "sync_outbox", "sync_tombstones", "sync_checkpoints", "sync_pending_inbox",
        "ai_changelog", "ai_changelog_entities", "device_state",
      ] {
        XCTAssertTrue(tables.contains(table), "\(table) must survive")
      }

      // The audit outbox row is deleted; the ordinary row keeps its id.
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'ai_changelog'"),
        0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT id FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [taskId]),
        taskOutboxId)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 1)

      // The audit pending-inbox row is deleted; the ordinary one stays.
      XCTAssertEqual(
        try String.fetchAll(
          db, sql: "SELECT envelope_entity_id FROM sync_pending_inbox"),
        ["pending-task-1"])

      // The retention policy moved into device_state as its wire value.
      XCTAssertEqual(try self.deviceStatePolicy(db), "30")
      XCTAssertEqual(AuditRetention.policy(db), .days(30))

      // The audit row and its entity link survive the rebuild.
      let audit = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT id, timestamp, operation, entity_type, summary, initiated_by
            FROM ai_changelog WHERE id = 'audit-row-1'
            """))
      XCTAssertEqual(audit["summary"] as String, "created a task")
      XCTAssertEqual(audit["timestamp"] as String, self.timestamp)
      XCTAssertEqual(
        try String.fetchAll(
          db, sql: "SELECT entity_id FROM ai_changelog_entities WHERE changelog_id = 'audit-row-1'"),
        [taskId])

      // Retired checkpoint keys are deleted; lookalikes and others stay.
      let checkpoints = try String.fetchAll(db, sql: "SELECT key FROM sync_checkpoints")
      XCTAssertFalse(checkpoints.contains("enrolled_zone_epoch.zone-a"))
      XCTAssertFalse(checkpoints.contains("cloudkit_per_record_fetch_failure_count"))
      XCTAssertFalse(checkpoints.contains("cloudkit_per_record_fetch_failure_checkpoint"))
      XCTAssertTrue(checkpoints.contains("enrolledXzoneXepoch.zone-a"))
      XCTAssertTrue(checkpoints.contains("unrelated_checkpoint"))

      // The tombstone survives without its cloud-confirmation stamp.
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_id = 'dead-task-1'"),
        1)

      // Retired columns are gone.
      let outboxColumns = try self.columnNames(db, "sync_outbox")
      XCTAssertFalse(outboxColumns.contains("authoritative_session_token"))
      XCTAssertFalse(outboxColumns.contains("future_record_resolution"))
      let auditColumns = try self.columnNames(db, "ai_changelog")
      XCTAssertFalse(auditColumns.contains("retention_epoch"))
      XCTAssertFalse(auditColumns.contains("retention_account_identifier"))
      XCTAssertFalse(try self.columnNames(db, "sync_tombstones").contains("cloud_confirmed_at"))

      // The database is structurally consistent.
      XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
      XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
    }
  }

  /// The ladder records the migration under its canonical name and digest, and
  /// reopening the upgraded database with the same ladder changes nothing.
  func testLadderIsRecordedAndReopeningIsANoOp() throws {
    let fixture = try makeFixture()
    let migration = try XCTUnwrap(fixture.migrations.first { $0.version == 2 })
    XCTAssertEqual(migration.name, "retire_custom_sync_transport")

    let migrated = try migrate(fixture) { db in
      try self.insertOutboxRow(db, entityType: "task", entityId: "task-noop")
    }
    try migrated.writer.read { db in
      let rows = try Row.fetchAll(
        db, sql: "SELECT version, name, checksum FROM schema_migrations ORDER BY version")
      XCTAssertEqual(rows.map { $0["version"] as Int }, [1, 2, 3])
      XCTAssertEqual(rows[0]["checksum"] as String, fixture.schemaChecksum)
      XCTAssertEqual(rows[1]["name"] as String, "retire_custom_sync_transport")
      XCTAssertEqual(
        rows[1]["checksum"] as String, MigrationSqlChecksum.hexDigest(migration.sql))
    }
    try migrated.writer.close()

    let reopened = try fixture.openWithLadder()
    XCTAssertNil(reopened.recovery)
    try reopened.writer.read { db in
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_migrations"), 3)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 1)
    }
  }

  /// When an account was bound, its own policy wins over the unbound
  /// candidate.
  func testBoundAccountPolicyWinsOverTheUnboundCandidate() throws {
    let fixture = try makeFixture()
    let migrated = try migrate(fixture) { db in
      try db.execute(
        sql: "UPDATE audit_retention_binding SET unbound_policy_value = '7' WHERE singleton = 1")
      try db.execute(
        sql: """
          INSERT INTO audit_retention_account_state (account_identifier, policy_value)
          VALUES ('icloud-account-a', '"off"')
          """)
      try db.execute(
        sql: """
          UPDATE audit_retention_binding
          SET ever_bound = 1, active_account_identifier = 'icloud-account-a',
              active_zone_name = 'LorvexZone'
          WHERE singleton = 1
          """)
    }
    try migrated.writer.read { db in
      XCTAssertEqual(try self.deviceStatePolicy(db), "\"off\"")
      XCTAssertEqual(AuditRetention.policy(db), .off)
    }
  }

  /// `maximum` is the absent-row default, so an upgrade that finds it stores
  /// nothing, and an existing unrelated `device_state` row is untouched.
  func testMaximumPolicyIsNotStored() throws {
    let fixture = try makeFixture()
    let migrated = try migrate(fixture) { db in
      try db.execute(sql: "INSERT INTO device_state (key, value) VALUES ('unrelated', '\"keep\"')")
    }
    try migrated.writer.read { db in
      XCTAssertNil(try self.deviceStatePolicy(db))
      XCTAssertEqual(AuditRetention.policy(db), .maximum)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT value FROM device_state WHERE key = 'unrelated'"),
        "\"keep\"")
    }
  }

  /// The rebuilt outbox continues its AUTOINCREMENT sequence from the old
  /// high-water mark, including ids of rows already removed, so an outbox id is
  /// never reused.
  func testOutboxIdsAreNeverReusedAcrossTheRebuild() throws {
    let fixture = try makeFixture()
    let migrated = try migrate(fixture) { db in
      for index in 1...3 {
        try self.insertOutboxRow(db, entityType: "task", entityId: "task-seq-\(index)")
      }
      try db.execute(sql: "DELETE FROM sync_outbox WHERE entity_id IN ('task-seq-2', 'task-seq-3')")
    }
    try migrated.writer.write { db in
      try self.insertOutboxRow(db, entityType: "task", entityId: "task-seq-new")
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT id FROM sync_outbox WHERE entity_id = 'task-seq-new'"),
        4, "the next id continues past the highest id ever issued")
    }
  }

  /// The rebuilt outbox enforces the narrowed disposition set and keeps its
  /// one-unsynced-row-per-entity guarantee.
  func testRebuiltOutboxKeepsItsConstraintsAndIndexes() throws {
    let fixture = try makeFixture()
    let migrated = try migrate(fixture) { _ in }
    try migrated.writer.write { db in
      let indexes = Set(
        try String.fetchAll(
          db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'sync_outbox'"))
      for index in [
        "idx_sync_outbox_pending", "idx_sync_outbox_retry_due",
        "idx_sync_outbox_future_hold_identity", "idx_sync_outbox_entity",
        "idx_sync_outbox_unsynced_per_entity", "idx_sync_outbox_synced_at",
      ] {
        XCTAssertTrue(indexes.contains(index), "missing index \(index)")
      }

      try self.insertOutboxRow(db, entityType: "task", entityId: "task-unique")
      XCTAssertThrowsError(
        try self.insertOutboxRow(db, entityType: "task", entityId: "task-unique"),
        "a second unsynced row for one entity violates the unique partial index")
      XCTAssertThrowsError(
        try db.execute(
          sql: "UPDATE sync_outbox SET disposition = 'authoritative_adoption' WHERE entity_id = 'task-unique'"),
        "the retired disposition is no longer storable")

      let changelogIndexes = Set(
        try String.fetchAll(
          db,
          sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'ai_changelog'"))
      XCTAssertTrue(changelogIndexes.contains("idx_changelog_timestamp"))
      XCTAssertTrue(changelogIndexes.contains("idx_changelog_entity"))
      XCTAssertTrue(changelogIndexes.contains("idx_changelog_operation"))
    }
  }
}
