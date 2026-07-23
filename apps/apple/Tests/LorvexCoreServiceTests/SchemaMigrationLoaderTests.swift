import Foundation
import LorvexStore
import Testing

@testable import LorvexCore

/// The app-layer derivation of the migration ladder from the canonical
/// `schema/migrations/` artifacts: `SwiftLorvexCoreService` loads the bundled
/// byte-copies, validates them against `checksums.lock`, and hands the result
/// to `LorvexStore.open`. These tests drive the validation core with fixture
/// locks/files and the production resolver against the real repo artifacts.
@Suite struct SchemaMigrationLoaderTests {
  private static let baselineSha = String(repeating: "0", count: 64)

  private func lockJSON(_ entries: [(key: String, name: String, sha: String)]) -> String {
    let body = entries
      .map { "\"\($0.key)\": {\"name\": \"\($0.name)\", \"sha256\": \"\($0.sha)\"}" }
      .joined(separator: ", ")
    return "{\(body)}"
  }

  private func load(
    _ entries: [(key: String, name: String, sha: String)],
    files: [String: String]
  ) throws -> [LorvexStore.SchemaMigration] {
    try SwiftLorvexCoreService.schemaMigrations(
      lockContents: lockJSON(entries), lockOrigin: "fixture", migrationSQLByFileName: files)
  }

  /// The production resolver against the real repo artifacts: the canonical
  /// ladder is empty pre-launch, and resolving it (lock + migrations
  /// directory + validation) succeeds.
  @Test func productionLadderResolvesEmptyPreLaunch() throws {
    let migrations = try SwiftLorvexCoreService.resolveSchemaMigrations()
    #expect(migrations.isEmpty)
  }

  @Test func validLadderLoadsWithBareNamesInVersionOrder() throws {
    let widgets = "CREATE TABLE widgets (id TEXT PRIMARY KEY) STRICT;"
    let gadgets = "CREATE TABLE gadgets (id TEXT PRIMARY KEY) STRICT;"
    let migrations = try load(
      [
        ("001", "001_schema.sql", Self.baselineSha),
        ("003", "003_add_gadgets.sql", MigrationSqlChecksum.hexDigest(gadgets)),
        ("002", "002_add_widgets.sql", MigrationSqlChecksum.hexDigest(widgets)),
      ],
      files: ["002_add_widgets.sql": widgets, "003_add_gadgets.sql": gadgets])
    #expect(
      migrations == [
        LorvexStore.SchemaMigration(version: 2, name: "add_widgets", sql: widgets),
        LorvexStore.SchemaMigration(version: 3, name: "add_gadgets", sql: gadgets),
      ])
  }

  /// Comment-only differences between the file and the SQL the lock was
  /// seeded from are not drift: the canonical digest ignores comments.
  @Test func commentOnlyVariantOfLockedMigrationLoads() throws {
    let seeded = "CREATE TABLE widgets (id TEXT PRIMARY KEY) STRICT;"
    let onDisk = "-- widgets\nCREATE TABLE widgets (id TEXT PRIMARY KEY) STRICT;  -- inline\n"
    let migrations = try load(
      [
        ("001", "001_schema.sql", Self.baselineSha),
        ("002", "002_add_widgets.sql", MigrationSqlChecksum.hexDigest(seeded)),
      ],
      files: ["002_add_widgets.sql": onDisk])
    #expect(migrations.count == 1)
    #expect(migrations.first?.sql == onDisk)
  }

  @Test func editedMigrationFileIsRejected() {
    let widgets = "CREATE TABLE widgets (id TEXT PRIMARY KEY) STRICT;"
    let edited = "CREATE TABLE widgets (id TEXT PRIMARY KEY, extra TEXT) STRICT;"
    #expect(throws: LorvexCoreError.self) {
      _ = try load(
        [
          ("001", "001_schema.sql", Self.baselineSha),
          ("002", "002_add_widgets.sql", MigrationSqlChecksum.hexDigest(widgets)),
        ],
        files: ["002_add_widgets.sql": edited])
    }
  }

  @Test func lockedMigrationWithoutFileIsRejected() {
    #expect(throws: LorvexCoreError.self) {
      _ = try load(
        [
          ("001", "001_schema.sql", Self.baselineSha),
          ("002", "002_add_widgets.sql", String(repeating: "a", count: 64)),
        ],
        files: [:])
    }
  }

  @Test func unrecordedMigrationFileIsRejected() {
    #expect(throws: LorvexCoreError.self) {
      _ = try load(
        [("001", "001_schema.sql", Self.baselineSha)],
        files: ["002_add_widgets.sql": "CREATE TABLE widgets (id TEXT) STRICT;"])
    }
  }

  @Test func versionGapIsRejected() {
    let gadgets = "CREATE TABLE gadgets (id TEXT PRIMARY KEY) STRICT;"
    #expect(throws: LorvexCoreError.self) {
      _ = try load(
        [
          ("001", "001_schema.sql", Self.baselineSha),
          ("003", "003_add_gadgets.sql", MigrationSqlChecksum.hexDigest(gadgets)),
        ],
        files: ["003_add_gadgets.sql": gadgets])
    }
  }

  @Test func misnumberedEntryNameIsRejected() {
    let widgets = "CREATE TABLE widgets (id TEXT PRIMARY KEY) STRICT;"
    #expect(throws: LorvexCoreError.self) {
      _ = try load(
        [
          ("001", "001_schema.sql", Self.baselineSha),
          ("002", "003_add_widgets.sql", MigrationSqlChecksum.hexDigest(widgets)),
        ],
        files: ["003_add_widgets.sql": widgets])
    }
  }

  @Test func missingBaselineEntryIsRejected() {
    let widgets = "CREATE TABLE widgets (id TEXT PRIMARY KEY) STRICT;"
    #expect(throws: LorvexCoreError.self) {
      _ = try load(
        [("002", "002_add_widgets.sql", MigrationSqlChecksum.hexDigest(widgets))],
        files: ["002_add_widgets.sql": widgets])
    }
  }

  /// End-to-end: a loaded fixture ladder drives `LorvexStore.open`'s runner —
  /// the migration applies on top of the real baseline schema and records the
  /// canonical checksum the lock carries.
  @Test func loadedLadderAppliesThroughTheStore() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let schemaSQL = try String(
      contentsOf: root.appendingPathComponent("schema/schema.sql"), encoding: .utf8)
    let widgets = "CREATE TABLE IF NOT EXISTS widgets (id TEXT PRIMARY KEY) STRICT;"
    let sha = MigrationSqlChecksum.hexDigest(widgets)
    let migrations = try load(
      [
        ("001", "001_schema.sql", Self.baselineSha),
        ("002", "002_add_widgets.sql", sha),
      ],
      files: ["002_add_widgets.sql": widgets])

    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL, migrations: migrations)
    let recorded = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT checksum FROM schema_migrations WHERE version = 2 AND name = 'add_widgets'")
    }
    #expect(recorded == sha)
  }
}
