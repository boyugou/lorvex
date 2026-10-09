import Foundation
import GRDB
import XCTest

@testable import LorvexStore

/// Migration `003_habit_skips`: a database that already sits at version 2 gains
/// the `habit_skips` relation and a tombstone table that accepts the
/// `habit_skip` entity type, and keeps the tombstones it already holds. Each
/// test seeds an on-disk database with the ladder up to version 2, closes it,
/// and reopens the same file with the full canonical ladder.
final class HabitSkipsMigrationTests: XCTestCase {
  private let hlc = "1800000000000_0000_1111222233334444"
  private let timestamp = "2026-07-15T00:00:00.000Z"
  private let habitId = "01966a3f-7c8b-7d4e-8f3a-0000000000b1"

  private struct Fixture {
    let databaseURL: URL
    let schema: String
    let schemaChecksum: String
    let ladder: [LorvexStore.SchemaMigration]

    func open(through version: Int) throws -> LorvexStore {
      try LorvexStore.open(
        at: databaseURL, schemaSQL: schema, schemaChecksum: schemaChecksum,
        migrations: ladder.filter { $0.version <= version })
    }
  }

  private func makeFixture() throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-habit-skips-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let schema = try TestSupport.loadSchemaSQL()
    return Fixture(
      databaseURL: directory.appendingPathComponent("db.sqlite"),
      schema: schema,
      schemaChecksum: MigrationSqlChecksum.hexDigest(schema),
      ladder: try TestSupport.loadSchemaMigrations())
  }

  /// Seed a database at version 2 with `seed`, close it, and return the store
  /// reopened with the full ladder.
  private func upgrade(
    _ fixture: Fixture, seed: (Database) throws -> Void
  ) throws -> LorvexStore {
    let before = try fixture.open(through: 2)
    try before.writer.write { db in
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"), 2)
      try seed(db)
    }
    try before.writer.close()
    let after = try fixture.open(through: Int.max)
    XCTAssertNil(after.recovery, "a healthy upgrade must not quarantine the database")
    return after
  }

  private func insertTombstone(
    _ db: Database, type: String, id: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
        VALUES (?, ?, ?, ?)
        """,
      arguments: [type, id, hlc, timestamp])
  }

  private func insertHabit(_ db: Database) throws {
    try db.execute(
      sql: "INSERT INTO habits (id, name, version, created_at, updated_at) VALUES (?, 'Cardio', ?, ?, ?)",
      arguments: [habitId, hlc, timestamp, timestamp])
  }

  func testUpgradeKeepsTombstonesAndAcceptsSkipTombstones() throws {
    let fixture = try makeFixture()
    let store = try upgrade(fixture) { db in
      try self.insertTombstone(db, type: "task", id: "task-1")
      try self.insertTombstone(db, type: "habit_completion", id: "\(self.habitId):2026-07-01")
    }
    try store.writer.write { db in
      XCTAssertEqual(
        try Set(
          String.fetchAll(
            db, sql: "SELECT entity_type || '|' || entity_id FROM sync_tombstones")),
        ["task|task-1", "habit_completion|\(habitId):2026-07-01"],
        "the rebuild must carry every existing tombstone over")
      XCTAssertEqual(
        try Set(String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('sync_tombstones')")),
        ["entity_type", "entity_id", "version", "deleted_at"])
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_sync_tombstones_version'"),
        "idx_sync_tombstones_version")

      try self.insertTombstone(db, type: "habit_skip", id: "\(self.habitId):2026-07-15")
      XCTAssertThrowsError(
        try self.insertTombstone(db, type: "not_an_entity", id: "x"),
        "the entity-type list must still be closed")
      XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
      XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
    }
  }

  func testSkipRelationHasTheDayEdgeShapeAndCascadesWithItsHabit() throws {
    let fixture = try makeFixture()
    let store = try upgrade(fixture) { _ in }
    try store.writer.write { db in
      XCTAssertEqual(
        try Row.fetchAll(
          db, sql: "SELECT name FROM pragma_table_info('habit_skips') ORDER BY pk, cid"
        ).map { $0["name"] as String },
        ["version", "created_at", "updated_at", "habit_id", "skipped_date"],
        "non-key columns first, then the (habit_id, skipped_date) primary key in order")
      try self.insertHabit(db)
      try db.execute(
        sql: """
          INSERT INTO habit_skips (habit_id, skipped_date, version, created_at, updated_at)
          VALUES (?, '2026-07-15', ?, ?, ?)
          """,
        arguments: [habitId, hlc, timestamp, timestamp])

      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO habit_skips (habit_id, skipped_date, version, created_at, updated_at)
            VALUES (?, '2026-07-16', 'not-an-hlc', ?, ?)
            """,
          arguments: [habitId, timestamp, timestamp]),
        "the version column carries the canonical HLC guard")
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO habit_skips (habit_id, skipped_date, version, created_at, updated_at)
            VALUES (?, '2026-07-15', ?, ?, ?)
            """,
          arguments: [habitId, hlc, timestamp, timestamp]),
        "one skip per habit and day")

      try db.execute(sql: "DELETE FROM habits WHERE id = ?", arguments: [habitId])
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM habit_skips"), 0)
    }
  }
}
