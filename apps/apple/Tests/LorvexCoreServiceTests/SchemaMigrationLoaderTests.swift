import Foundation
import GRDB
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
  /// ladder holds exactly `002_retire_custom_sync_transport` and
  /// `003_habit_skips`, and resolving them (lock + migrations directory +
  /// validation) succeeds.
  @Test func productionLadderResolvesTheShippedMigrations() throws {
    let migrations = try SwiftLorvexCoreService.resolveSchemaMigrations()
    #expect(migrations.map(\.version) == [2, 3])
    #expect(migrations.map(\.name) == ["retire_custom_sync_transport", "habit_skips"])
  }

  /// The ladder applied to the baseline schema yields the production shape:
  /// the retired transport tables are gone and `sync_outbox` carries neither
  /// the authoritative-session owner nor the future-record resolution policy.
  @Test func productionLadderRetiresTheCustomSyncTransportSchema() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let schemaSQL = try String(
      contentsOf: root.appendingPathComponent("schema/schema.sql"), encoding: .utf8)
    let store = try LorvexStore.openInMemory(
      schemaSQL: schemaSQL, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations())

    let (tables, outboxColumns, changelogColumns, tombstoneColumns) = try store.writer.read {
      db -> (Set<String>, Set<String>, Set<String>, Set<String>) in
      func columns(_ table: String) throws -> Set<String> {
        Set(try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map { $0["name"] as String })
      }
      return (
        Set(
          try String.fetchAll(
            db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")),
        try columns("sync_outbox"), try columns("ai_changelog"),
        try columns("sync_tombstones")
      )
    }
    let retiredPrefixes = [
      "sync_cloudkit_", "sync_generation_snapshot_", "sync_authoritative_snapshot",
      "audit_retention_", "audit_changelog_cloud_presence",
    ]
    #expect(tables.filter { name in retiredPrefixes.contains { name.hasPrefix($0) } }.isEmpty)
    #expect(tables.isSuperset(of: ["sync_outbox", "ai_changelog", "sync_tombstones"]))
    #expect(
      outboxColumns.isDisjoint(with: ["authoritative_session_token", "future_record_resolution"]))
    #expect(changelogColumns.isDisjoint(with: ["retention_epoch", "retention_account_identifier"]))
    #expect(!tombstoneColumns.contains("cloud_confirmed_at"))
  }

  /// A managed on-disk database created before the ladder existed (baseline
  /// only) upgrades through the production ladder without being set aside, and
  /// every later open is an ordinary reopen. A quarantine on either open would
  /// surface the "previous data set aside" notice again after an update.
  @Test func baselineOnlyManagedDatabaseUpgradesWithoutQuarantine() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let schemaSQL = try String(
      contentsOf: root.appendingPathComponent("schema/schema.sql"), encoding: .utf8)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ladder-upgrade-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("db.sqlite")
    let checksum = "baseline-checksum"

    let created = try LorvexStore.open(
      at: url, schemaSQL: schemaSQL, schemaChecksum: checksum, managed: true)
    #expect(created.recovery == nil)
    try created.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, list_id, version, created_at, updated_at)
          VALUES ('t1', 'Kept', 'inbox', '0000000000001_0000_0000000000000001',
                  '2026-09-01T00:00:00.000Z', '2026-09-01T00:00:00.000Z')
          """)
    }
    try created.writer.close()

    let ladder = try SwiftLorvexCoreService.resolveSchemaMigrations()
    for _ in 0..<2 {
      let reopened = try LorvexStore.open(
        at: url, schemaSQL: schemaSQL, schemaChecksum: checksum, migrations: ladder,
        managed: true)
      #expect(reopened.recovery == nil)
      let title = try reopened.writer.read { db in
        try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = 't1'")
      }
      #expect(title == "Kept")
      try reopened.writer.close()
    }
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(leftovers.filter { $0.contains("incompatible") }.isEmpty)
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
