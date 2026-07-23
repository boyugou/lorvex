import Foundation
import GRDB
import XCTest

@testable import LorvexStore

/// Regression: opening an ON-DISK store must apply `schema.sql` even though it
/// begins with `PRAGMA journal_mode = WAL` — SQLite rejects a journal-mode
/// change inside a transaction, and WAL is silently ignored on `:memory:`, so
/// only an on-disk open exercises this path.
final class LorvexStoreOnDiskTests: XCTestCase {
  func testOpenOnDiskAppliesSchemaAndEnablesWAL() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-ondisk-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")

    let sql = try Self.loadSchemaSQL()
    let store = try LorvexStore.open(at: dbURL, schemaSQL: sql)

    let mode = try store.writer.read { db in
      try String.fetchOne(db, sql: "PRAGMA journal_mode")
    }
    XCTAssertEqual(mode?.lowercased(), "wal", "on-disk store should be in WAL mode")

    let tables = try SchemaIntrospection.dump(store).filter { $0.type == "table" }.map(\.name)
    for expected in ["tasks", "lists", "ai_changelog"] {
      XCTAssertTrue(tables.contains(expected), "missing table: \(expected)")
    }
  }

  /// SB8: the store replays the whole `schema.sql` verbatim on every open, so an
  /// unguarded `INSERT INTO tasks_fts_trigram(...) VALUES('rebuild')` would tear
  /// down and re-project the trigram index from all tasks on every launch. Prove
  /// the rebuild is NOT performed on a normal open: seed a "ghost" posting at a
  /// rowid with no backing `tasks` row (a rebuild re-projects from `tasks` only,
  /// so it would erase the ghost) and assert it survives a close + reopen.
  func testSchemaReplayOnOpenDoesNotRebuildTrigramIndex() throws {
    let dir = Self.makeTempDir("lorvex-trigram-norebuild")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()
    let ghostTerm = "zzghosttrigramzz"

    var store: LorvexStore? = try LorvexStore.open(at: dbURL, schemaSQL: sql)
    try store!.writer.write { db in
      try db.execute(
        sql: "INSERT INTO tasks_fts_trigram(rowid, title, body, ai_notes) VALUES (?, ?, NULL, NULL)",
        arguments: [999_999, ghostTerm])
    }
    let matchedBefore = try store!.writer.read { db in
      try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tasks_fts_trigram WHERE tasks_fts_trigram MATCH ?",
        arguments: [ghostTerm]) ?? 0
    }
    XCTAssertEqual(matchedBefore, 1, "ghost posting should be present before reopen")

    // Release the first handle so the reopen replays schema.sql on the now
    // schema-initialized database.
    store = nil
    let reopened = try LorvexStore.open(at: dbURL, schemaSQL: sql)
    let matchedAfter = try reopened.writer.read { db in
      try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tasks_fts_trigram WHERE tasks_fts_trigram MATCH ?",
        arguments: [ghostTerm]) ?? 0
    }
    XCTAssertEqual(
      matchedAfter, 1,
      "the trigram ghost posting must survive a normal open — schema replay must NOT rebuild the "
        + "index (the tasks_fts_trigram_* triggers keep it fresh)")
  }

  // MARK: - schema_migrations bookkeeping parity (with the Tauri runner)

  func testFreshOnDiskStoreStampsSchemaMigrationsRow() throws {
    let dir = Self.makeTempDir("lorvex-stamp")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()

    let store = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: "deadbeefchecksum")
    XCTAssertNil(store.recovery, "a clean fresh open must not report a recovery")

    let row = try store.writer.read { db in
      try Row.fetchOne(db, sql: "SELECT version, name, checksum FROM schema_migrations")
    }
    XCTAssertEqual(row?["version"], 1)
    XCTAssertEqual(row?["name"], "schema")
    XCTAssertEqual(row?["checksum"], "deadbeefchecksum")
  }

  func testMatchingSchemaChecksumReopensWithoutRecovery() throws {
    let dir = Self.makeTempDir("lorvex-match")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()

    _ = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: "samesum")
    let store = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: "samesum")
    XCTAssertNil(store.recovery, "a matching checksum must reuse the existing database")
  }

  /// M6: a checksum mismatch on a READABLE, versioned database FAILS CLOSED —
  /// the open re-throws ``SchemaMismatch`` (a broken/tampered build, not corrupt
  /// user data) and leaves the file untouched, instead of quarantining healthy
  /// data into an empty app.
  func testMismatchedSchemaChecksumFailsClosedWithoutQuarantine() throws {
    let dir = Self.makeTempDir("lorvex-mismatch")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()

    // A database written under an older schema checksum, carrying real data.
    let seeded = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: "oldschemasum")
    try seeded.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at)
          VALUES ('t1', 'Keep me', 'open', 'inbox', '1711234567890_0000_a1b2c3d4a1b2c3d4',
                  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """)
    }
    try seeded.writer.close()

    // The current binary expects a different checksum: fail closed, do not
    // quarantine.
    XCTAssertThrowsError(
      try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: "newschemasum")
    ) { error in
      guard let mismatch = error as? LorvexStore.SchemaMismatch else {
        return XCTFail("expected SchemaMismatch, got \(error)")
      }
      XCTAssertEqual(mismatch.kind, .checksumMismatch)
      // The mismatch surfaces the full recorded identity (migration name +
      // checksum) so a renamed history entry is distinguishable from pure
      // checksum drift.
      XCTAssertEqual(mismatch.recorded, "name=schema; checksum=oldschemasum")
      XCTAssertEqual(mismatch.expected, "name=schema; checksum=newschemasum")
    }

    // The file was left untouched: no quarantine sidecar was written, and the
    // original database still reopens under its recorded checksum with data
    // intact.
    let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertFalse(
      siblings.contains { $0.contains("incompatible-") },
      "a checksum mismatch must not quarantine a readable database")
    let reopened = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: "oldschemasum")
    XCTAssertNil(reopened.recovery)
    let title = try reopened.writer.read { db in
      try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = 't1'")
    }
    XCTAssertEqual(title, "Keep me", "the readable database was preserved untouched")
  }

  func testDataBearingDatabaseWithoutBookkeepingIsQuarantined() throws {
    let dir = Self.makeTempDir("lorvex-nobookkeeping")
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")
    let sql = try Self.loadSchemaSQL()

    // Simulate a pre-bookkeeping database: full schema applied, but no
    // schema_migrations row was ever stamped.
    // schema.sql creates the data tables but not schema_migrations (the Tauri
    // runner / our open path own that), so a raw apply leaves no bookkeeping.
    let queue = try DatabaseQueue(path: dbURL.path)
    try queue.writeWithoutTransaction { db in
      try db.execute(sql: sql)
    }
    try queue.close()

    let store = try LorvexStore.open(at: dbURL, schemaSQL: sql, schemaChecksum: "anychecksum")
    XCTAssertNotNil(
      store.recovery,
      "a data-bearing database with no bookkeeping row cannot be verified and must be set aside")
  }

  func testOpenQuarantinesANonDatabaseFileAndStartsFresh() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-notadb-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")

    // A plain text file is not a SQLite database (SQLITE_NOTADB).
    try "this is definitely not a sqlite database".write(to: dbURL, atomically: true, encoding: .utf8)

    let sql = try Self.loadSchemaSQL()
    let store = try LorvexStore.open(at: dbURL, schemaSQL: sql)

    // It recovered: the bad file was renamed aside (preserved, not deleted) and
    // a fresh, usable database now lives at the original path.
    let recovery = try XCTUnwrap(store.recovery, "expected a recovery for a non-database file")
    XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.backupURL.path))
    XCTAssertTrue(recovery.backupURL.lastPathComponent.contains("incompatible-"))
    let tables = try SchemaIntrospection.dump(store).filter { $0.type == "table" }.map(\.name)
    XCTAssertTrue(tables.contains("tasks"))
  }

  func testOpenQuarantinesAStructurallyIncompatibleDatabaseAndStartsFresh() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-incompat-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("db.sqlite")

    // A valid SQLite DB whose `tasks` table conflicts with the schema: it has a
    // column the schema also declares but with an incompatible shape, so
    // applying the (idempotent) schema cannot reconcile it.
    let queue = try DatabaseQueue(path: dbURL.path)
    try queue.writeWithoutTransaction { db in
      // `id` declared NOT NULL PRIMARY KEY here vs the schema's definition makes
      // dependent index/trigger DDL in the schema fail against this structure.
      try db.execute(sql: "CREATE TABLE tasks (totally_wrong_shape INTEGER)")
    }
    try queue.close()

    let sql = try Self.loadSchemaSQL()
    let store = try LorvexStore.open(at: dbURL, schemaSQL: sql)

    let recovery = try XCTUnwrap(store.recovery, "expected a recovery for an incompatible DB")
    XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.backupURL.path))
    let tables = try SchemaIntrospection.dump(store).filter { $0.type == "table" }.map(\.name)
    XCTAssertTrue(tables.contains("ai_changelog"))
  }

  func testTransientOpenFailureDoesNotTouchTheFile() throws {
    // SQLITE_CANTOPEN (a missing parent directory) is environmental, not an
    // unreadable database: the open must re-throw and never rename anything.
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-missingdir-\(UUID().uuidString)", isDirectory: true)
    // Intentionally do NOT create `dir`.
    let dbURL = dir.appendingPathComponent("db.sqlite")

    let sql = try Self.loadSchemaSQL()
    XCTAssertThrowsError(try LorvexStore.open(at: dbURL, schemaSQL: sql))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: dir.path),
      "a transient failure must not create or rename files")
  }

  func testClassifierTreatsLockingAndPermissionAsTransient() {
    let transient: [ResultCode] = [
      .SQLITE_BUSY, .SQLITE_LOCKED, .SQLITE_CANTOPEN, .SQLITE_IOERR,
      .SQLITE_PERM, .SQLITE_AUTH, .SQLITE_READONLY, .SQLITE_FULL,
    ]
    for code in transient {
      let error = DatabaseError(resultCode: code)
      XCTAssertFalse(
        LorvexStore.isUnrecoverableDatabaseError(error),
        "\(code) should be treated as transient, not an unreadable database")
    }
    for code in [ResultCode.SQLITE_NOTADB, .SQLITE_CORRUPT] {
      XCTAssertTrue(LorvexStore.isUnrecoverableDatabaseError(DatabaseError(resultCode: code)))
    }
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
