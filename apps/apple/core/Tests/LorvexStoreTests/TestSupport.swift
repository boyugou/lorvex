import Foundation

@testable import LorvexStore

/// Shared helpers for `LorvexStoreTests`.
enum TestSupport {
  /// Load the authoritative root `schema/schema.sql` via `#filePath`-relative
  /// path so tests run wherever the repo lives, without bundling a second
  /// copy of the schema as a SwiftPM resource.
  ///
  /// Layout: `apps/apple/core/Tests/LorvexStoreTests/<file>.swift` →
  ///         `<repo-root>/lorvex/schema/schema.sql` (5 levels up).
  static func loadSchemaSQL(file: StaticString = #filePath) throws -> String {
    var path = (String(describing: file) as NSString).deletingLastPathComponent
    for _ in 0..<5 {
      path = (path as NSString).deletingLastPathComponent
    }
    let schemaPath = (path as NSString).appendingPathComponent("schema/schema.sql")
    return try String(contentsOfFile: schemaPath, encoding: .utf8)
  }

  /// The versioned migrations (version 2 and later) pinned by
  /// `schema/migrations/checksums.lock`, in ascending version order. Each
  /// entry's `name` is the bare snake_case name (the file name without its
  /// `NNN_` prefix and `.sql` suffix) and `sql` is the file contents, matching
  /// how the app layer loads the ladder at open time.
  static func loadSchemaMigrations(
    file: StaticString = #filePath
  ) throws -> [LorvexStore.SchemaMigration] {
    var path = (String(describing: file) as NSString).deletingLastPathComponent
    for _ in 0..<5 {
      path = (path as NSString).deletingLastPathComponent
    }
    let directory = (path as NSString).appendingPathComponent("schema/migrations")
    let lockData = try Data(
      contentsOf: URL(
        fileURLWithPath: (directory as NSString).appendingPathComponent("checksums.lock")))
    guard let lock = try JSONSerialization.jsonObject(with: lockData) as? [String: [String: Any]]
    else {
      throw NSError(
        domain: "SchemaMigrations", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "checksums.lock is not a JSON object of objects"])
    }
    var migrations: [LorvexStore.SchemaMigration] = []
    for (key, entry) in lock {
      guard let version = Int(key), version >= 2, let fileName = entry["name"] as? String else {
        continue
      }
      guard fileName.hasSuffix(".sql"), let underscore = fileName.firstIndex(of: "_") else {
        throw NSError(
          domain: "SchemaMigrations", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "unexpected migration file name \(fileName)"])
      }
      let name = String(fileName[fileName.index(after: underscore)...].dropLast(".sql".count))
      let sql = try String(
        contentsOfFile: (directory as NSString).appendingPathComponent(fileName), encoding: .utf8)
      migrations.append(LorvexStore.SchemaMigration(version: version, name: name, sql: sql))
    }
    return migrations.sorted { $0.version < $1.version }
  }

  /// Fresh in-memory store with the authoritative schema applied and the
  /// numbered migration ladder run on top of it.
  static func freshStore(file: StaticString = #filePath) throws -> LorvexStore {
    let sql = try loadSchemaSQL(file: file)
    return try LorvexStore.openInMemory(
      schemaSQL: sql, migrations: try loadSchemaMigrations(file: file))
  }
}
