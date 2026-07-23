import Foundation
import GRDB
import XCTest

@testable import LorvexStore

/// H6: on the production path (`schemaChecksum != nil`) a versioned database is
/// verified against its recorded baseline checksum and then handed straight to
/// the numbered-migration ladder — the frozen baseline is NEVER replayed. These
/// tests pin that: a database a destructive migration has altered out-of-band
/// reopens cleanly, without the baseline resurrecting the dropped object or
/// quarantining the healthy file, while a fresh database still gets the full
/// baseline plus its stamped bookkeeping row.
final class SchemaBaselineNoReplayTests: XCTestCase {

  /// The core H6 guard. A shipped destructive migration drops the indexes over
  /// `tasks.planned_date` and then the `planned_date` column.
  /// Replaying the baseline on the next open would re-run
  /// `CREATE INDEX IF NOT EXISTS idx_tasks_planned_date ON tasks(planned_date)`
  /// and fail with `no such column: planned_date` → `SQLITE_ERROR` → the healthy
  /// DB gets quarantined into an empty app. Proving the reopen is clean proves
  /// the baseline replay is gone.
  func testVersionedDatabaseWithDroppedColumnReopensWithoutBaselineReplayOrQuarantine() throws {
    let dir = Self.makeTempDir("lorvex-noreplay")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()
    let checksum = MigrationSqlChecksum.hexDigest(sql)

    // A fresh, versioned production database (v1 bookkeeping row stamped).
    let first = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: checksum)
    XCTAssertNil(first.recovery)

    // Simulate a shipped destructive migration's effect: drop the dependent
    // index, then the column it indexed. The bookkeeping row stays at v1 (the
    // ladder is empty here), so the reopen takes the verify-and-stop path.
    try first.writer.write { db in
      try db.execute(sql: "DROP INDEX idx_tasks_action_date_actionable")
      try db.execute(sql: "DROP INDEX idx_tasks_planned_date")
      try db.execute(sql: "ALTER TABLE tasks DROP COLUMN planned_date")
    }
    try first.writer.close()

    // Reopen with the SAME checksum: the baseline is not replayed, so neither
    // the column nor its index is resurrected, and nothing is quarantined.
    let reopened = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: checksum)
    XCTAssertNil(
      reopened.recovery,
      "a versioned DB must reopen without quarantine — the baseline must not be replayed")

    let columns = try reopened.writer.read { db in
      try Row.fetchAll(db, sql: "PRAGMA table_info(tasks)").map { $0["name"] as String }
    }
    XCTAssertFalse(
      columns.contains("planned_date"),
      "the baseline must not be replayed — a resurrected planned_date would prove it was")

    let indexExists = try reopened.writer.read { db in
      try Bool.fetchOne(
        db,
        sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='index' AND name=?)",
        arguments: ["idx_tasks_planned_date"]) ?? false
    }
    XCTAssertFalse(
      indexExists, "the baseline's CREATE INDEX must not have re-run on the versioned reopen")

    let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertFalse(
      siblings.contains { $0.contains("incompatible-") },
      "no quarantine sidecar must be written for a clean versioned reopen")
  }

  /// The fresh-open path is unchanged: a brand-new production database applies
  /// the full baseline (all core tables plus the `sync_outbox` index a
  /// destructive migration could later drop) and stamps the version-1 row.
  func testFreshDatabaseAppliesFullSchemaAndStampsBookkeepingRow() throws {
    let dir = Self.makeTempDir("lorvex-fresh-baseline")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()
    let checksum = MigrationSqlChecksum.hexDigest(sql)

    let store = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: checksum)
    XCTAssertNil(store.recovery, "a clean fresh open must not report a recovery")

    let entries = try SchemaIntrospection.dump(store)
    let tables = Set(entries.filter { $0.type == "table" }.map(\.name))
    for expected in [
      "tasks", "lists", "calendar_events", "habits", "memories", "ai_changelog", "sync_outbox",
    ] {
      XCTAssertTrue(tables.contains(expected), "fresh schema missing table: \(expected)")
    }
    XCTAssertTrue(
      entries.contains { $0.type == "index" && $0.name == "idx_tasks_planned_date" },
      "a fresh open must materialize the full baseline, including task indexes")
    XCTAssertTrue(
      entries.contains { $0.type == "index" && $0.name == "idx_sync_outbox_pending" },
      "a fresh open must materialize the active outbox partial index")
    XCTAssertTrue(
      entries.contains { $0.type == "index" && $0.name == "idx_sync_outbox_authoritative_gc" },
      "a fresh open must materialize the authoritative-fence retention index")
    XCTAssertFalse(
      entries.contains { $0.type == "index" && $0.name == "idx_tasks_archived_at" },
      "archived tasks have no catalog or age-cutoff scan that earns a dedicated index")

    let row = try store.writer.read { db in
      try Row.fetchOne(db, sql: "SELECT version, name, checksum FROM schema_migrations")
    }
    XCTAssertEqual(row?["version"], 1)
    XCTAssertEqual(row?["name"], "schema")
    XCTAssertEqual(row?["checksum"], checksum)
  }

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
