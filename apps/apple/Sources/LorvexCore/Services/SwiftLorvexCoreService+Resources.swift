import Foundation
import LorvexRuntime
import LorvexStore

extension SwiftLorvexCoreService {
  /// The database the lazy open resolved: which SQLite file to open, and — for
  /// Lorvex-managed resolutions — the path whose durable storage generation
  /// (`ManagedStorageGeneration`) the open store must watch, so a factory
  /// reset's delete-and-recreate is detected instead of written through.
  /// `managedGenerationDatabasePath` is `nil` for an explicit `databasePath`
  /// (dev/test injection, never factory-reset).
  struct ResolvedDatabase {
    let path: String
    let managedGenerationDatabasePath: String?
  }

  /// The SQLite file the open path should use: an explicit `databasePath`
  /// (dev/test injection) when configured, otherwise the runtime's managed
  /// local-storage resolver. The managed store — the App Group container when
  /// available, else the platform data dir — is opened directly and its durable
  /// storage generation is watched. The App Group container is shared across the
  /// app and its helpers/extensions, so any process may first-create it; there
  /// is no separate per-process database to reconcile.
  ///
  /// Throws ``DbLocationError/appGroupContainerUnavailable(appGroupIdentifier:)``
  /// when a sandboxed build cannot resolve its App Group container: the managed
  /// store's identity is unknown, and opening a per-process fallback would split
  /// the store across the app, MCP helper, and extensions. The open fails closed
  /// rather than silently diverging.
  func resolveDatabaseForOpen() throws -> ResolvedDatabase {
    if let databasePath, !databasePath.isEmpty {
      return ResolvedDatabase(path: databasePath, managedGenerationDatabasePath: nil)
    }
    let details = try DbLocator.resolveDetails(SwiftLorvexCoreService.dbLocatorEnv())
    switch details.source {
    case .envOverride:
      return ResolvedDatabase(path: details.resolvedPath, managedGenerationDatabasePath: nil)
    case .platformDataDir, .homeFallback, .appleAppGroup:
      return ResolvedDatabase(
        path: details.resolvedPath, managedGenerationDatabasePath: details.resolvedPath)
    }
  }

  /// Factory-reset cutover for the Lorvex-managed database: under the
  /// exclusive cross-process storage flock, bump the durable storage
  /// generation, then delete the database, its `-wal`/`-shm` sidecars, and the
  /// generation-bound Focus-filter sidecar (see
  /// `ManagedStorageGeneration.resetDatabase`). Callers must close/evict this
  /// process's open services first; other processes detect the bumped
  /// generation at their next operation and reopen the recreated store.
  /// Throws when the lock cannot be acquired or the main file cannot be
  /// deleted — the erase must never report a false success.
  @discardableResult
  public static func resetManagedStorage(at url: URL) throws -> Int {
    try ManagedStorageGeneration.resetDatabase(
      atPath: url.path,
      relatedSidecarPaths: [url.path + LorvexProductMetadata.focusFilterStateFileSuffix])
  }

  /// Current durable generation of a managed database, used by derived-file
  /// writers to reject a projection captured before an explicit reset even when
  /// the derived file itself is absent or unreadable.
  public static func managedStorageGeneration(atDatabasePath path: String) -> Int? {
    ManagedStorageGeneration.read(forDatabase: path)
  }

  /// The Lorvex-managed local-storage path: App Group container when available,
  /// else the platform data dir, independent of any explicit `databasePath`.
  ///
  /// Throws ``DbLocationError/appGroupContainerUnavailable(appGroupIdentifier:)``
  /// when a sandboxed build cannot resolve its App Group container — there is no
  /// safe managed path to return, since a per-process fallback would split the
  /// store.
  public static func managedDatabasePath() throws -> String {
    try DbLocator.resolvePath(dbLocatorEnv())
  }

  /// Test seam: replaces the process-derived locator environment so the on-disk
  /// open path can be exercised against temporary directories. Task-local so
  /// concurrent tests never leak an environment into each other; never bound in
  /// production.
  @TaskLocal static var dbLocatorEnvironmentOverride: (any DbLocatorEnvironment)?

  private static func dbLocatorEnv() -> any DbLocatorEnvironment {
    if let dbLocatorEnvironmentOverride {
      return dbLocatorEnvironmentOverride
    }
    let env = ProcessInfo.processInfo.environment
    let dataDir = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
    let appGroupContainer = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: LorvexProductMetadata.appGroupIdentifier)?
      .path
    return InMemoryDbLocatorEnv(
      dbPathEnvOverride: env[LorvexCoreRuntimeFactory.databasePathEnvironmentKey].flatMap {
        $0.isEmpty ? nil : $0
      },
      dataDir: dataDir,
      homeDir: NSHomeDirectory(),
      platform: .current,
      appleAppGroupContainerPath: appGroupContainer,
      // The `LORVEX_APPLE_DB_PATH` dev override is honored only on unsandboxed
      // builds; a sandboxed app/helper always resolves the managed store.
      allowsDbPathOverride: !AppSandboxEnvironment.isSandboxed(environment: env),
      // Names the App Group in a fail-closed error when the container above is
      // nil on a sandboxed build; never selects a path on its own.
      appleAppGroupIdentifier: LorvexProductMetadata.appGroupIdentifier
    )
  }

  static func resolveSchemaSQL() throws -> String {
    let env = ProcessInfo.processInfo.environment
    // Dev/source-build override only. A sandboxed app/helper ignores it and
    // resolves the bundled schema, matching the `LORVEX_APPLE_DB_PATH` gating:
    // otherwise the schema-integrity check is self-defeating, since the expected
    // checksum resolves through the same env-overridable path this validates.
    if !AppSandboxEnvironment.isSandboxed(environment: env),
      let path = env["LORVEX_APPLE_SCHEMA_PATH"], !path.isEmpty
    {
      return try String(contentsOfFile: path, encoding: .utf8)
    }
    if let sql = bundledSchemaSQL() {
      return sql
    }
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Services
      .deletingLastPathComponent()  // LorvexCore
      .deletingLastPathComponent()  // Sources
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
    let candidate = repoRoot.appendingPathComponent("schema/schema.sql")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return try String(contentsOf: candidate, encoding: .utf8)
    }
    throw LorvexCoreError.unsupportedOperation(
      "Lorvex schema SQL is unavailable; set LORVEX_APPLE_SCHEMA_PATH to schema/schema.sql.")
  }

  /// Side-effect-free package sanity check for helpers and diagnostics: the
  /// schema SQL matches its lock entry and the bundled migration ladder loads
  /// and validates against the same lock.
  public static func verifyBundledSchemaResources() throws {
    let schemaSQL = try resolveSchemaSQL()
    let checksum = try resolveSchemaChecksum()
    try verifySchemaChecksum(schemaSQL: schemaSQL, expectedChecksum: checksum)
    _ = try resolveSchemaMigrations()
  }

  /// Anchor for `Bundle(for:)` so resources resolve from the bundle carrying
  /// this module's code.
  private final class SchemaResourceAnchor {}

  private static func coreResourceBundle() -> Bundle {
    #if SWIFT_PACKAGE
      LorvexResourceBundleResolver.bundle(
        named: "LorvexApple_LorvexCore.bundle",
        bundleFor: SchemaResourceAnchor.self,
        swiftPMBundle: Bundle.module)
    #else
      Bundle(for: SchemaResourceAnchor.self)
    #endif
  }

  private static func bundledSchemaSQL() -> String? {
    let resolved = coreResourceBundle()
    for bundle in [resolved, Bundle(for: SchemaResourceAnchor.self), Bundle.main] {
      if let url = bundle.url(forResource: "schema", withExtension: "sql"),
        let sql = try? String(contentsOf: url, encoding: .utf8)
      {
        return sql
      }
    }
    return nil
  }

  /// The raw `checksums.lock` contents plus a human-readable origin for error
  /// messages, resolved through the same chain as the schema SQL: env override
  /// (`LORVEX_APPLE_CHECKSUMS_PATH`) → bundled resource → source-tree fallback.
  static func resolveChecksumsLockContents() throws -> (contents: String, origin: String) {
    let env = ProcessInfo.processInfo.environment
    // Dev/source-build override only; a sandboxed app/helper ignores it so the
    // expected checksum cannot be swapped out from under the integrity check
    // (matches the `LORVEX_APPLE_DB_PATH` / schema-path gating).
    if !AppSandboxEnvironment.isSandboxed(environment: env),
      let path = env["LORVEX_APPLE_CHECKSUMS_PATH"], !path.isEmpty
    {
      return (try String(contentsOfFile: path, encoding: .utf8), path)
    }
    if let contents = bundledChecksumsLock() {
      return (contents, "the bundled checksums.lock")
    }
    let sourceLock = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Services
      .deletingLastPathComponent()  // LorvexCore
      .appendingPathComponent("Resources/checksums.lock")
    if let contents = try? String(contentsOf: sourceLock, encoding: .utf8) {
      return (contents, sourceLock.path)
    }
    throw LorvexCoreError.unsupportedOperation(
      "Lorvex schema checksum lock is unavailable; bundle Resources/checksums.lock.")
  }

  static func resolveSchemaChecksum() throws -> String? {
    let lock = try resolveChecksumsLockContents()
    guard let checksum = schemaChecksum(fromLockContents: lock.contents) else {
      throw LorvexCoreError.unsupportedOperation(
        "Lorvex schema checksum lock is malformed at \(lock.origin).")
    }
    return checksum
  }

  private static func bundledChecksumsLock() -> String? {
    let resolved = coreResourceBundle()
    for bundle in [resolved, Bundle(for: SchemaResourceAnchor.self), Bundle.main] {
      if let url = bundle.url(forResource: "checksums", withExtension: "lock"),
        let contents = try? String(contentsOf: url, encoding: .utf8)
      {
        return contents
      }
    }
    return nil
  }

  private static func schemaChecksum(fromLockContents contents: String) -> String? {
    guard let data = contents.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let entry = root["001"] as? [String: Any],
      let sha = entry["sha256"] as? String,
      !sha.isEmpty
    else { return nil }
    return sha
  }

  static func normalizedSchemaChecksumForTesting(_ sql: String) -> String {
    normalizedSchemaChecksum(of: sql)
  }

  static func verifySchemaChecksumForTesting(sql: String, expectedChecksum: String?) throws {
    try verifySchemaChecksum(schemaSQL: sql, expectedChecksum: expectedChecksum)
  }

  static func verifySchemaChecksum(schemaSQL: String, expectedChecksum: String?) throws {
    guard let expectedChecksum else { return }
    let actual = normalizedSchemaChecksum(of: schemaSQL)
    guard actual == expectedChecksum else {
      throw LorvexCoreError.unsupportedOperation(
        "Lorvex schema SQL does not match checksums.lock for version 001.")
    }
  }

  /// The canonical normalized SQL digest (see `MigrationSqlChecksum` in
  /// `LorvexStore`) — the convention `checksums.lock` records.
  private static func normalizedSchemaChecksum(of sql: String) -> String {
    MigrationSqlChecksum.hexDigest(sql)
  }
}
