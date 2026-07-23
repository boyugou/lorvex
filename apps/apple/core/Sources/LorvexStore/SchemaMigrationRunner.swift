import Foundation
import GRDB

extension LorvexStore {
  /// A numbered, named SQL migration applied on top of the consolidated
  /// version-1 schema. Versions are monotonically increasing from 2 (version 1
  /// is `schema/schema.sql`, stamped by the open path). The SQL may contain
  /// multiple statements; once shipped, a migration is FROZEN — its recorded
  /// name and checksum (the canonical normalized digest,
  /// ``MigrationSqlChecksum``) are verified on every subsequent open.
  ///
  /// Production migrations are not authored as Swift strings: they are the
  /// canonical `schema/migrations/NNN_<name>.sql` files, bundled as byte-copies
  /// in the app layer's resources and loaded into this type at open time
  /// (`SwiftLorvexCoreService.resolveSchemaMigrations()`). `name` is the bare
  /// snake_case name (`add_widgets` for `002_add_widgets.sql`) recorded into
  /// `schema_migrations.name`.
  public struct SchemaMigration: Sendable, Equatable {
    public let version: Int
    public let name: String
    public let sql: String

    public init(version: Int, name: String, sql: String) {
      self.version = version
      self.name = name
      self.sql = sql
    }
  }

  /// The database records a schema version newer than this build knows about.
  /// Opening must REFUSE — never quarantine: the data is healthy, just written
  /// by a newer Lorvex, and setting it aside would present the user an empty
  /// app. The caller surfaces "your database is newer than this build; please
  /// update Lorvex".
  public struct SchemaDowngrade: Error, Equatable {
    public let binaryMaxVersion: Int
    public let dbMaxVersion: Int

    public init(binaryMaxVersion: Int, dbMaxVersion: Int) {
      self.binaryMaxVersion = binaryMaxVersion
      self.dbMaxVersion = dbMaxVersion
    }
  }

  /// A version-2+ migration's SQL (or its bookkeeping stamp) failed to execute.
  /// Deliberately its own type — not a `DatabaseError`, whose SQLite result
  /// code the open path could read as an unreadable file and quarantine — so
  /// the open path FAILS CLOSED and re-throws: the user's database is healthy,
  /// the shipped migration is what's broken, and setting every user's data
  /// aside over a bad migration would be unrecoverable.
  public struct SchemaMigrationFailed: Error {
    public let version: Int
    public let name: String
    public let underlying: any Error

    public init(version: Int, name: String, underlying: any Error) {
      self.version = version
      self.name = name
      self.underlying = underlying
    }
  }

}

/// Versioned-migration ladder for schema evolution past the consolidated
/// version-1 schema. The ladder's source of truth is the canonical
/// `schema/migrations/` directory; the caller supplies the loaded migrations.
///
/// - **Downgrade refusal**: a database whose recorded max version exceeds what
///   this build registers throws ``LorvexStore/SchemaDowngrade`` — surfaced as
///   an open failure, never a quarantine.
/// - **Frozen-migration verification**: an already-recorded version's name and
///   checksum must equal the registered migration's name and canonical
///   normalized SHA-256 (``MigrationSqlChecksum``), so a shipped Apple ladder
///   stays self-consistent across app versions; a mismatch
///   (an edited frozen migration, or genuine drift) throws
///   ``LorvexStore/SchemaMismatch`` of kind
///   ``LorvexStore/SchemaMismatch/Kind/checksumMismatch``, which the open path
///   FAILS CLOSED on (re-throws, never quarantines) — the database is healthy,
///   the build's ladder is what disagrees.
/// - **Atomic apply**: an unapplied migration executes and stamps its
///   bookkeeping row inside one `BEGIN IMMEDIATE` transaction, re-checking the
///   recorded row under the write lock so a concurrent process (app + MCP
///   host racing the same upgrade) applies each migration exactly once.
enum SchemaMigrationRunner {
  /// Run the ladder against an open connection at autocommit (the schema-apply
  /// path), in ascending version order.
  static func run(_ db: Database, migrations: [LorvexStore.SchemaMigration]) throws {
    try validateRecordedHistory(db, baselineVersion: 1)
    guard !migrations.isEmpty else { return }
    for migration in migrations.sorted(by: { $0.version < $1.version }) {
      let checksum = MigrationSqlChecksum.hexDigest(migration.sql)
      if let recorded = try recordedMigration(db, version: migration.version) {
        try verify(recorded, matches: migration, checksum: checksum)
        continue
      }

      try db.execute(sql: "BEGIN IMMEDIATE")
      do {
        // Re-check under the write lock: a concurrent process may have applied
        // this version between the read above and acquiring the lock.
        if let recorded = try recordedMigration(db, version: migration.version) {
          try verify(recorded, matches: migration, checksum: checksum)
          try db.execute(sql: "COMMIT")
          continue
        }
        try db.execute(sql: migration.sql)
        try db.execute(
          sql: "INSERT INTO schema_migrations (version, name, checksum) VALUES (?, ?, ?)",
          arguments: [migration.version, migration.name, checksum])
        try db.execute(sql: "COMMIT")
      } catch {
        // Roll the half-applied migration back so the DB never holds DDL with
        // no matching bookkeeping row (and the connection never leaks an open
        // transaction into the caller's autocommit context).
        try? db.execute(sql: "ROLLBACK")
        if error is LorvexStore.SchemaMismatch { throw error }
        throw LorvexStore.SchemaMigrationFailed(
          version: migration.version, name: migration.name, underlying: error)
      }
    }
  }

  /// Refuse to open a database written by a newer build. `binaryMaxVersion` is
  /// the highest version this build can realize (the consolidated baseline, or
  /// the highest registered migration).
  static func checkDowngrade(
    _ db: Database, migrations: [LorvexStore.SchemaMigration], baselineVersion: Int
  ) throws {
    try validateRecordedHistory(db, baselineVersion: baselineVersion)
    let binaryMax = max(baselineVersion, migrations.map(\.version).max() ?? baselineVersion)
    let dbMax = try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations") ?? 0
    if dbMax > binaryMax {
      throw LorvexStore.SchemaDowngrade(binaryMaxVersion: binaryMax, dbMaxVersion: dbMax)
    }
  }

  /// Once the production baseline is stamped, migration bookkeeping is an
  /// append-only contiguous history. Applying an older missing migration after
  /// a later version would execute DDL out of order and make the recorded
  /// ladder lie about the schema that actually produced the database.
  private static func validateRecordedHistory(
    _ db: Database, baselineVersion: Int
  ) throws {
    let versions = try Int.fetchAll(
      db, sql: "SELECT version FROM schema_migrations ORDER BY version")
    // Checksum-less in-memory/test stores deliberately do not stamp v1.
    guard versions.contains(baselineVersion), let maximum = versions.last else { return }
    let expected = Array(baselineVersion...maximum)
    guard versions == expected else {
      throw LorvexStore.SchemaMismatch(
        kind: .checksumMismatch,
        recorded: "versions=" + versions.map(String.init).joined(separator: ","),
        expected: "versions=" + expected.map(String.init).joined(separator: ","))
    }
  }

  private struct RecordedMigration {
    let name: String
    let checksum: String
  }

  private static func recordedMigration(_ db: Database, version: Int) throws
    -> RecordedMigration?
  {
    guard
      let row = try Row.fetchOne(
        db, sql: "SELECT name, checksum FROM schema_migrations WHERE version = ?",
        arguments: [version])
    else { return nil }
    return RecordedMigration(name: row["name"], checksum: row["checksum"])
  }

  private static func verify(
    _ recorded: RecordedMigration, matches migration: LorvexStore.SchemaMigration,
    checksum expectedChecksum: String
  ) throws {
    guard recorded.name == migration.name else {
      throw LorvexStore.SchemaMismatch(
        kind: .checksumMismatch,
        recorded: "name=\(recorded.name); checksum=\(recorded.checksum)",
        expected: "name=\(migration.name); checksum=\(expectedChecksum)")
    }
    guard recorded.checksum == expectedChecksum else {
      throw LorvexStore.SchemaMismatch(
        kind: .checksumMismatch, recorded: recorded.checksum, expected: expectedChecksum)
    }
  }
}
