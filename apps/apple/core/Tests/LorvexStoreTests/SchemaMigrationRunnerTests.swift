import Foundation
import GRDB
import XCTest

@testable import LorvexStore

/// The versioned-migration ladder (versions 2+) on top of the consolidated
/// version-1 schema: upgrade-in-place for existing databases, downgrade refusal
/// without quarantine, frozen-migration checksum verification, and
/// non-quarantining failure for a broken shipped migration.
final class SchemaMigrationRunnerTests: XCTestCase {
  private func loadSchema() throws -> String {
    var path = (#filePath as NSString).deletingLastPathComponent
    for _ in 0..<5 { path = (path as NSString).deletingLastPathComponent }
    return try String(
      contentsOfFile: (path as NSString).appendingPathComponent("schema/schema.sql"),
      encoding: .utf8)
  }

  private func tempDatabaseURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-migrations-\(UUID().uuidString)")
      .appendingPathComponent("db.sqlite")
  }

  private let v2 = LorvexStore.SchemaMigration(
    version: 2, name: "add_widgets",
    sql: "CREATE TABLE IF NOT EXISTS widgets (id TEXT PRIMARY KEY, name TEXT NOT NULL) STRICT;")

  /// The canonical normalized digest the Apple ladder records and
  /// `schema/migrations/checksums.lock` pins.
  private func checksum(_ sql: String) -> String {
    MigrationSqlChecksum.hexDigest(sql)
  }

  /// The current shipping configuration: an empty ladder on a baseline-schema
  /// database is a no-op that leaves exactly the version-1 bookkeeping row.
  func testEmptyLadderOnBaselineDatabaseRecordsOnlyVersionOne() throws {
    let url = tempDatabaseURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let schema = try loadSchema()
    let schemaChecksum = checksum(schema)

    let store = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [])
    XCTAssertNil(store.recovery)
    try store.writer.read { db in
      let rows = try Row.fetchAll(
        db, sql: "SELECT version, name, checksum FROM schema_migrations ORDER BY version")
      XCTAssertEqual(rows.count, 1)
      XCTAssertEqual(rows.first?["version"] as Int?, 1)
      XCTAssertEqual(rows.first?["name"] as String?, "schema")
      XCTAssertEqual(rows.first?["checksum"] as String?, schemaChecksum)
    }
    try store.writer.close()

    // Reopening with the same empty ladder stays a no-op.
    let reopened = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [])
    XCTAssertNil(reopened.recovery)
    try reopened.writer.read { db in
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_migrations"), 1)
    }
    try reopened.writer.close()
  }

  /// The recorded ladder checksum is the canonical normalized digest, not the
  /// raw-byte digest, and a comment-only variant verifies clean.
  func testRecordedChecksumIsCanonicalNormalizedDigest() throws {
    // Comment-bearing SQL, so the normalized digest provably differs from the
    // raw-byte digest.
    let commented = LorvexStore.SchemaMigration(
      version: 2, name: "add_widgets",
      sql: """
        -- widgets: a leading comment block
        \(v2.sql)  -- trailing inline comment
        """)
    XCTAssertNotEqual(
      MigrationSqlChecksum.hexDigest(commented.sql),
      Sha256Checksum.hexDigest(Data(commented.sql.utf8)))

    let schema = try loadSchema()
    let store = try LorvexStore.openInMemory(schemaSQL: schema, migrations: [commented])
    try store.writer.read { db in
      let recorded = try String.fetchOne(
        db, sql: "SELECT checksum FROM schema_migrations WHERE version = 2")
      XCTAssertEqual(recorded, MigrationSqlChecksum.hexDigest(commented.sql))
      XCTAssertNotEqual(recorded, Sha256Checksum.hexDigest(Data(commented.sql.utf8)))
    }

    // A comment-reflowed copy of the frozen migration is the SAME migration:
    // it must pass the frozen-checksum verification, not quarantine. The
    // comment-free original is one such copy.
    XCTAssertEqual(
      MigrationSqlChecksum.hexDigest(commented.sql), MigrationSqlChecksum.hexDigest(v2.sql))
    try store.writer.writeWithoutTransaction { db in
      try SchemaMigrationRunner.run(db, migrations: [v2])
    }
  }

  /// Renumbered/reordered frozen migrations (the SQL of two shipped versions
  /// swapped) are rejected as a checksum mismatch — the ladder's history is
  /// immutable, not just its contents.
  func testSwappedVersionsOfAppliedMigrationsAreRejected() throws {
    let v3 = LorvexStore.SchemaMigration(
      version: 3, name: "add_gadgets",
      sql: "CREATE TABLE IF NOT EXISTS gadgets (id TEXT PRIMARY KEY) STRICT;")
    let schema = try loadSchema()
    let store = try LorvexStore.openInMemory(schemaSQL: schema, migrations: [v2, v3])

    let swapped = [
      LorvexStore.SchemaMigration(version: 2, name: v3.name, sql: v3.sql),
      LorvexStore.SchemaMigration(version: 3, name: v2.name, sql: v2.sql),
    ]
    try store.writer.writeWithoutTransaction { db in
      XCTAssertThrowsError(try SchemaMigrationRunner.run(db, migrations: swapped)) { error in
        XCTAssertTrue(error is LorvexStore.SchemaMismatch, "got \(error)")
      }
    }
  }

  /// A released migration's name is part of its frozen identity. Keeping the
  /// same version and SQL cannot make a renamed migration acceptable.
  func testRenamedAppliedMigrationIsRejectedEvenWhenChecksumMatches() throws {
    let schema = try loadSchema()
    let store = try LorvexStore.openInMemory(schemaSQL: schema, migrations: [v2])
    let renamed = LorvexStore.SchemaMigration(
      version: v2.version, name: "renamed_widgets", sql: v2.sql)

    XCTAssertEqual(checksum(renamed.sql), checksum(v2.sql))
    try store.writer.writeWithoutTransaction { db in
      XCTAssertThrowsError(try SchemaMigrationRunner.run(db, migrations: [renamed])) { error in
        guard let mismatch = error as? LorvexStore.SchemaMismatch else {
          return XCTFail("expected SchemaMismatch, got \(error)")
        }
        XCTAssertEqual(mismatch.kind, .checksumMismatch)
      }
    }
  }

  func testRecordedHistoryGapIsRejectedBeforeAnOlderMigrationCanRun() throws {
    let v3 = LorvexStore.SchemaMigration(
      version: 3, name: "add_gadgets",
      sql: "CREATE TABLE IF NOT EXISTS gadgets (id TEXT PRIMARY KEY) STRICT;")
    let store = try LorvexStore.openInMemory(
      schemaSQL: try loadSchema(), migrations: [v2, v3])
    try store.writer.writeWithoutTransaction { db in
      try db.execute(
        sql: "INSERT INTO schema_migrations (version, name, checksum) VALUES (1, 'schema', 'test')")
      try db.execute(sql: "DELETE FROM schema_migrations WHERE version = 2")

      XCTAssertThrowsError(
        try SchemaMigrationRunner.run(db, migrations: [v2, v3])
      ) { error in
        guard let mismatch = error as? LorvexStore.SchemaMismatch else {
          return XCTFail("expected SchemaMismatch, got \(error)")
        }
        XCTAssertEqual(mismatch.kind, .checksumMismatch)
        XCTAssertTrue(mismatch.recorded.contains("versions=1,3"))
      }
      XCTAssertNil(
        try Int.fetchOne(
          db, sql: "SELECT version FROM schema_migrations WHERE version = 2"))
    }
  }

  func testBaselineNameIsVerifiedAlongsideItsChecksum() throws {
    let url = tempDatabaseURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let schema = try loadSchema()
    let schemaChecksum = checksum(schema)
    let first = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum)
    try first.writer.write { db in
      try db.execute(
        sql: "UPDATE schema_migrations SET name = 'renamed' WHERE version = 1")
    }
    try first.writer.close()

    XCTAssertThrowsError(
      try LorvexStore.open(
        at: url, schemaSQL: schema, schemaChecksum: schemaChecksum)
    ) { error in
      guard let mismatch = error as? LorvexStore.SchemaMismatch else {
        return XCTFail("expected SchemaMismatch, got \(error)")
      }
      XCTAssertEqual(mismatch.kind, .checksumMismatch)
      XCTAssertTrue(mismatch.recorded.contains("name=renamed"))
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }

  func testFreshDatabaseAppliesRegisteredMigration() throws {
    let store = try LorvexStore.openInMemory(schemaSQL: try loadSchema(), migrations: [v2])
    try store.writer.read { db in
      XCTAssertTrue(try db.tableExists("widgets"))
      let row = try Row.fetchOne(
        db, sql: "SELECT name, checksum FROM schema_migrations WHERE version = 2")
      XCTAssertEqual(row?["name"] as String?, "add_widgets")
      XCTAssertEqual(row?["checksum"] as String?, checksum(v2.sql))
    }
  }

  /// The P-06 scenario: an existing version-1 database opens under a build that
  /// ships a version-2 migration — upgraded in place, data intact, no
  /// quarantine.
  func testExistingDatabaseUpgradesInPlaceKeepingData() throws {
    let url = tempDatabaseURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let schema = try loadSchema()
    let schemaChecksum = checksum(schema)

    let v1Store = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [])
    try v1Store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at)
          VALUES ('t1', 'Keep me', 'open', 'inbox', '1711234567890_0000_a1b2c3d4a1b2c3d4',
                  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """)
    }
    try v1Store.writer.close()

    let upgraded = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [v2])
    XCTAssertNil(upgraded.recovery, "an upgrade must not quarantine")
    try upgraded.writer.read { db in
      XCTAssertTrue(try db.tableExists("widgets"))
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = 't1'"), "Keep me")
    }
    try upgraded.writer.close()
  }

  /// A database written by a NEWER build refuses to open — and is NOT
  /// quarantined: the file stays in place for the upgraded Lorvex to use.
  func testNewerDatabaseRefusesToOpenWithoutQuarantine() throws {
    let url = tempDatabaseURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let schema = try loadSchema()
    let schemaChecksum = checksum(schema)

    let newer = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [v2])
    try newer.writer.close()

    XCTAssertThrowsError(
      try LorvexStore.open(
        at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [])
    ) { error in
      guard let downgrade = error as? LorvexStore.SchemaDowngrade else {
        return XCTFail("expected SchemaDowngrade, got \(error)")
      }
      XCTAssertEqual(downgrade.binaryMaxVersion, 1)
      XCTAssertEqual(downgrade.dbMaxVersion, 2)
    }
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: url.path),
      "a newer database must never be quarantined")
  }

  /// An edited frozen migration (recorded checksum differs from the registered
  /// SQL) is genuine drift and raises a checksum-mismatch ``SchemaMismatch`` —
  /// which the open path fails closed on (re-throws), never quarantines.
  func testEditedFrozenMigrationIsASchemaMismatch() throws {
    let schema = try loadSchema()
    let store = try LorvexStore.openInMemory(schemaSQL: schema, migrations: [v2])
    let edited = LorvexStore.SchemaMigration(
      version: 2, name: "add_widgets",
      sql: "CREATE TABLE IF NOT EXISTS widgets (id TEXT PRIMARY KEY) STRICT;")
    try store.writer.writeWithoutTransaction { db in
      XCTAssertThrowsError(try SchemaMigrationRunner.run(db, migrations: [edited])) { error in
        guard let mismatch = error as? LorvexStore.SchemaMismatch else {
          return XCTFail("got \(error)")
        }
        XCTAssertEqual(mismatch.kind, .checksumMismatch)
      }
    }
  }

  /// A broken shipped migration fails the open WITHOUT quarantining the user's
  /// healthy database, and leaves no half-applied DDL or bookkeeping row.
  func testBrokenMigrationFailsWithoutQuarantineOrPartialApply() throws {
    let url = tempDatabaseURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let schema = try loadSchema()
    let schemaChecksum = checksum(schema)

    let v1Store = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [])
    try v1Store.writer.close()

    let broken = LorvexStore.SchemaMigration(
      version: 2, name: "broken",
      sql: "CREATE TABLE IF NOT EXISTS widgets (id TEXT PRIMARY KEY) STRICT; SYNTAX ERROR;")
    XCTAssertThrowsError(
      try LorvexStore.open(
        at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [broken])
    ) { error in
      XCTAssertTrue(error is LorvexStore.SchemaMigrationFailed, "got \(error)")
    }
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: url.path),
      "a broken migration must never quarantine a healthy database")

    // The rollback left neither the DDL nor the bookkeeping row behind.
    let reopened = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [])
    try reopened.writer.read { db in
      XCTAssertFalse(try db.tableExists("widgets"))
      XCTAssertNil(
        try Int.fetchOne(db, sql: "SELECT version FROM schema_migrations WHERE version = 2"))
    }
    try reopened.writer.close()
  }

  /// Reopening with the same migration set is a no-op (one bookkeeping row, no
  /// re-execution error from the frozen-migration verify path).
  func testReopenWithSameMigrationsIsIdempotent() throws {
    let url = tempDatabaseURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let schema = try loadSchema()
    let schemaChecksum = checksum(schema)

    let first = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [v2])
    try first.writer.close()
    let second = try LorvexStore.open(
      at: url, schemaSQL: schema, schemaChecksum: schemaChecksum, migrations: [v2])
    XCTAssertNil(second.recovery)
    try second.writer.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM schema_migrations WHERE version = 2"), 1)
    }
    try second.writer.close()
  }
}
