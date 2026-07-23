import Foundation
import GRDB
import XCTest

@testable import LorvexStore

/// The managed-only post-open guarantees: the structural completeness probe
/// (C1) and the idempotent inbox-row ensure (H2). Both fire only when `open` is
/// called with `managed: true`; in-memory / test / dev-injected stores keep the
/// lenient behavior.
final class LorvexStoreManagedCompletenessTests: XCTestCase {

  // MARK: - C1: completeness probe → quarantine

  /// The reproduced defect: a managed database that stamped a matching schema
  /// checksum but whose load-bearing tables are absent (a text-checksum match
  /// does not prove the tables were realized). It must be quarantined and
  /// replaced with a fresh, fully-seeded database rather than reaching normal
  /// operation and failing every write with `no such table`.
  func testStampedButTablelessManagedDatabaseIsQuarantinedAndRecreated() throws {
    let dir = Self.makeTempDir("lorvex-stamped-tableless")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()
    let checksum = "stamped-but-tableless-checksum"

    // A database carrying ONLY the version-1 bookkeeping row (matching the
    // checksum the open will verify) and none of the baseline tables.
    let seed = try DatabaseQueue(path: dbURL.path)
    try seed.writeWithoutTransaction { db in
      try LorvexStore.ensureSchemaMigrationsTable(db)
      try LorvexStore.stampSchemaMigration(db, checksum: checksum)
    }
    try seed.close()

    let store = try LorvexStore.open(
      at: dbURL, schemaSQL: sql, schemaChecksum: checksum, managed: true)

    // It recovered: the stamped-but-incomplete file was set aside (preserved) and
    // a fresh database now lives at the original path.
    let recovery = try XCTUnwrap(
      store.recovery, "a stamped-but-tableless managed database must be quarantined")
    XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.backupURL.path))
    XCTAssertTrue(recovery.backupURL.lastPathComponent.contains("incompatible-"))
    XCTAssertTrue(
      recovery.reason.contains("missing load-bearing tables"),
      "recovery reason should name the completeness failure: \(recovery.reason)")

    // The replacement is fully realized and seeded.
    let tables = try SchemaIntrospection.dump(store).filter { $0.type == "table" }.map(\.name)
    for expected in [
      "lists", "tasks", "error_logs", "sync_checkpoints",
      "sync_cloudkit_account_binding", "sync_cloudkit_authority_witness",
      "sync_cloudkit_generation_descriptor",
      "sync_cloudkit_traversal_progress",
      "sync_cloudkit_traversal_witness", "sync_cloudkit_incremental_cursor",
      "sync_cloudkit_corrupt_record_fences", "preferences",
    ] {
      XCTAssertTrue(tables.contains(expected), "fresh database missing table: \(expected)")
    }
    let inboxCount = try store.writer.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = 'inbox'") ?? -1
    }
    XCTAssertEqual(inboxCount, 1, "the recreated database must seed the inbox list")
  }

  /// The healthy fresh-create path applies the full baseline and seeds BEFORE
  /// the probe runs, so the probe can never fire on it — a clean open must not be
  /// quarantined.
  func testHealthyFreshManagedOpenIsNotQuarantined() throws {
    let dir = Self.makeTempDir("lorvex-fresh-managed")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()

    let store = try LorvexStore.open(
      at: dbURL, schemaSQL: sql, schemaChecksum: "fresh-managed-checksum", managed: true)

    XCTAssertNil(store.recovery, "a healthy fresh managed open must not be quarantined")
    let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertFalse(
      siblings.contains { $0.contains("incompatible-") },
      "a healthy fresh open must not write a quarantine sidecar")
    let inboxCount = try store.writer.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = 'inbox'") ?? -1
    }
    XCTAssertEqual(inboxCount, 1)
  }

  /// The probe is MANAGED-ONLY: the same stamped-but-tableless file opened
  /// WITHOUT `managed: true` (the in-memory / test / dev-injected shape) is not
  /// probed and not quarantined, so the gating cannot leak into non-managed
  /// stores.
  func testProbeDoesNotFireOnNonManagedOpen() throws {
    let dir = Self.makeTempDir("lorvex-nonmanaged-probe")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()
    let checksum = "nonmanaged-stamped-checksum"

    let seed = try DatabaseQueue(path: dbURL.path)
    try seed.writeWithoutTransaction { db in
      try LorvexStore.ensureSchemaMigrationsTable(db)
      try LorvexStore.stampSchemaMigration(db, checksum: checksum)
    }
    try seed.close()

    let store = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: checksum)

    XCTAssertNil(store.recovery, "a non-managed open must not run the completeness probe")
    let tables = try SchemaIntrospection.dump(store).filter { $0.type == "table" }.map(\.name)
    XCTAssertFalse(
      tables.contains("lists"),
      "the probe must not fire (or heal) on a non-managed open: the file stays as-is")
  }

  // MARK: - H2: inbox-row ensure

  /// A managed database whose `inbox` row is absent (e.g. deleted through sync)
  /// gets it re-ensured on the next managed open — independent of baseline
  /// replay, which happens only once at first create — so implicit
  /// `create_task(list_id = 'inbox')` can never hit the `lists` foreign key.
  func testMissingInboxRowIsReEnsuredOnManagedOpen() throws {
    let dir = Self.makeTempDir("lorvex-inbox-ensure")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()
    let checksum = "inbox-ensure-checksum"

    _ = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: checksum, managed: true)

    // Remove the inbox row out-of-band (foreign keys off so the ON DELETE
    // RESTRICT guard does not block the deletion in the test fixture).
    var config = Configuration()
    config.foreignKeysEnabled = false
    let maintenance = try DatabaseQueue(path: dbURL.path, configuration: config)
    try maintenance.write { db in
      try db.execute(sql: "DELETE FROM lists WHERE id = 'inbox'")
    }
    let removed = try maintenance.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = 'inbox'") ?? -1
    }
    XCTAssertEqual(removed, 0, "fixture must have removed the inbox row")
    try maintenance.close()

    // Reopening the managed store re-ensures the canonical inbox row.
    let reopened = try LorvexStore.open(
      at: dbURL, schemaSQL: sql, schemaChecksum: checksum, managed: true)
    XCTAssertNil(reopened.recovery, "an inbox-only gap is not a quarantine condition")
    let inbox = try reopened.writer.read { db in
      try Row.fetchOne(db, sql: "SELECT id, name FROM lists WHERE id = 'inbox'")
    }
    XCTAssertEqual(inbox?["name"], "Inbox", "the inbox row must be re-ensured on managed open")

    // And a task can now be inserted into the default inbox list without hitting
    // the ON DELETE RESTRICT foreign key.
    try reopened.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at)
          VALUES ('t-inbox', 'x', 'open', 'inbox', '1711234567890_0000_a1b2c3d4a1b2c3d4',
                  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """)
    }
    let taskCount = try reopened.writer.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE list_id = 'inbox'") ?? -1
    }
    XCTAssertEqual(taskCount, 1)
  }

  // MARK: - Helpers

  private static func makeTempDir(_ prefix: String) -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private static func loadSchemaSQL() throws -> String {
    var path = (#filePath as NSString).deletingLastPathComponent
    for _ in 0..<5 { path = (path as NSString).deletingLastPathComponent }
    let schemaPath = (path as NSString).appendingPathComponent("schema/schema.sql")
    return try String(contentsOfFile: schemaPath, encoding: .utf8)
  }
}
