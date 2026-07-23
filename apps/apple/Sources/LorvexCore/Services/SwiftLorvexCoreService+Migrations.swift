import Foundation
import LorvexStore

/// Loads the versioned-migration ladder from the bundled byte-copies of the
/// canonical `schema/migrations/` directory, mirroring how the schema SQL and
/// checksum lock are resolved: env override → bundled resource → source-tree
/// fallback. The loaded ladder is validated against `checksums.lock` before it
/// is handed to `LorvexStore.open` — an edited, missing, renumbered, or
/// unrecorded migration file refuses the open instead of stamping bad history
/// into `schema_migrations`.
extension SwiftLorvexCoreService {
  /// The validated migration ladder (versions 2+; empty while the canonical
  /// directory ships no migrations). Throws when the lock is malformed, the
  /// versions are non-contiguous, a locked migration's file is missing, a
  /// file's canonical normalized checksum disagrees with its lock entry, or a
  /// `.sql` file exists that the lock does not record.
  static func resolveSchemaMigrations() throws -> [LorvexStore.SchemaMigration] {
    let lock = try resolveChecksumsLockContents()
    return try schemaMigrations(
      lockContents: lock.contents,
      lockOrigin: lock.origin,
      migrationSQLByFileName: try resolveMigrationSQLByFileName())
  }

  /// `filename → SQL` for every `.sql` file in the resolved migrations
  /// directory: `LORVEX_APPLE_MIGRATIONS_PATH` when set, else the bundled
  /// `Migrations/` resource directory, else the repo-checkout
  /// `schema/migrations/`. An empty map when no directory resolves — the lock
  /// validation still fails if the lock names migrations that then have no
  /// file.
  private static func resolveMigrationSQLByFileName() throws -> [String: String] {
    let env = ProcessInfo.processInfo.environment
    // Dev/source-build override only; a sandboxed app/helper ignores it and uses
    // the bundled ladder, matching the schema-path / `LORVEX_APPLE_DB_PATH`
    // gating so migrations cannot be swapped in from an env-controlled path.
    if !AppSandboxEnvironment.isSandboxed(environment: env),
      let path = env["LORVEX_APPLE_MIGRATIONS_PATH"], !path.isEmpty
    {
      return try migrationSQL(inDirectory: URL(fileURLWithPath: path))
    }
    if let bundled = bundledMigrationsDirectory() {
      return try migrationSQL(inDirectory: bundled)
    }
    let repoMigrations = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Services
      .deletingLastPathComponent()  // LorvexCore
      .deletingLastPathComponent()  // Sources
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/migrations")
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: repoMigrations.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      return try migrationSQL(inDirectory: repoMigrations)
    }
    return [:]
  }

  /// Anchor for `Bundle(for:)` so the Migrations directory resolves from the
  /// bundle carrying this module's code.
  private final class MigrationsResourceAnchor {}

  /// The bundled `Migrations/` directory (`.copy("Resources/Migrations")` in
  /// Package.swift preserves it as a folder at the resource-bundle root), or
  /// `nil` when no candidate bundle carries it.
  private static func bundledMigrationsDirectory() -> URL? {
    var candidates = [Bundle(for: MigrationsResourceAnchor.self), Bundle.main]
    #if SWIFT_PACKAGE
      candidates.insert(
        LorvexResourceBundleResolver.bundle(
          named: "LorvexApple_LorvexCore.bundle",
          bundleFor: MigrationsResourceAnchor.self,
          swiftPMBundle: Bundle.module), at: 0)
    #endif
    for bundle in candidates {
      guard let resourceURL = bundle.resourceURL else { continue }
      let directory = resourceURL.appendingPathComponent("Migrations", isDirectory: true)
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        return directory
      }
    }
    return nil
  }

  private static func migrationSQL(inDirectory directory: URL) throws -> [String: String] {
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    var sqlByFileName: [String: String] = [:]
    for name in names where name.hasSuffix(".sql") {
      sqlByFileName[name] = try String(
        contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
    return sqlByFileName
  }

  /// Pure validation core behind ``resolveSchemaMigrations()``; separated so
  /// tests can drive it with fixture locks and files.
  ///
  /// The lock is the shared `checksums.lock` shape: an object keyed by
  /// zero-padded version, each entry `{"name": "NNN_<name>.sql", "sha256":
  /// <canonical normalized digest>}`. Entry `001` is the baseline
  /// (`001_schema.sql`, i.e. `schema/schema.sql`) and has no file in the
  /// migrations directory; entries `002`+ each require a file whose name
  /// matches the entry and whose ``MigrationSqlChecksum`` digest matches the
  /// recorded sha. Versions must be contiguous from 1, and every `.sql` file
  /// present must be recorded. The returned migrations carry the bare
  /// snake_case name (`add_widgets` for `002_add_widgets.sql`) — the value
  /// stamped into `schema_migrations.name`.
  static func schemaMigrations(
    lockContents: String, lockOrigin: String, migrationSQLByFileName: [String: String]
  ) throws -> [LorvexStore.SchemaMigration] {
    func malformed(_ detail: String) -> LorvexCoreError {
      .unsupportedOperation(
        "Lorvex schema checksum lock at \(lockOrigin) is invalid: \(detail)")
    }

    guard let data = lockContents.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw malformed("not a JSON object")
    }

    var entriesByVersion: [Int: (name: String, sha256: String)] = [:]
    for (key, value) in root {
      guard key.count == 3, key.allSatisfy(\.isNumber), let version = Int(key), version >= 1
      else {
        throw malformed("entry key '\(key)' is not a zero-padded version")
      }
      guard let entry = value as? [String: Any],
        let name = entry["name"] as? String,
        let sha = entry["sha256"] as? String,
        sha.count == 64, sha.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
      else {
        throw malformed("entry '\(key)' must carry a name and a lowercase 64-hex sha256")
      }
      entriesByVersion[version] = (name, sha)
    }
    guard let maxVersion = entriesByVersion.keys.max(), entriesByVersion[1] != nil else {
      throw malformed("the baseline entry '001' is missing")
    }
    for version in 1...maxVersion where entriesByVersion[version] == nil {
      throw malformed(
        "versions are not contiguous: entry '\(String(format: "%03d", version))' is missing")
    }
    guard entriesByVersion[1]?.name == "001_schema.sql" else {
      throw malformed("entry '001' must name the baseline '001_schema.sql'")
    }

    var migrations: [LorvexStore.SchemaMigration] = []
    var recordedFileNames: Set<String> = []
    for version in stride(from: 2, through: maxVersion, by: 1) {
      guard let entry = entriesByVersion[version] else { continue }
      let prefix = String(format: "%03d_", version)
      guard entry.name.hasPrefix(prefix), entry.name.hasSuffix(".sql") else {
        throw malformed(
          "entry '\(String(format: "%03d", version))' name '\(entry.name)' must be "
            + "'\(prefix)<name>.sql'")
      }
      let bareName = String(entry.name.dropFirst(prefix.count).dropLast(4))
      guard !bareName.isEmpty,
        bareName.allSatisfy({ ($0.isLowercase && $0.isASCII) || $0.isNumber || $0 == "_" })
      else {
        throw malformed(
          "entry '\(String(format: "%03d", version))' name '\(entry.name)' must use "
            + "snake_case ([a-z0-9_])")
      }
      guard let sql = migrationSQLByFileName[entry.name] else {
        throw malformed(
          "migration file '\(entry.name)' is recorded in the lock but missing from the "
            + "migrations directory")
      }
      let digest = MigrationSqlChecksum.hexDigest(sql)
      guard digest == entry.sha256 else {
        throw malformed(
          "migration file '\(entry.name)' does not match its recorded checksum "
            + "(recorded \(entry.sha256), computed \(digest)); a frozen migration must "
            + "never be edited — append a new migration instead")
      }
      recordedFileNames.insert(entry.name)
      migrations.append(
        LorvexStore.SchemaMigration(version: version, name: bareName, sql: sql))
    }

    let unrecorded = Set(migrationSQLByFileName.keys).subtracting(recordedFileNames)
    if let stray = unrecorded.sorted().first {
      throw malformed(
        "migration file '\(stray)' has no checksums.lock entry; record it (and mirror the "
          + "canonical schema/migrations/) before it can ship")
    }

    return migrations.sorted { $0.version < $1.version }
  }
}
