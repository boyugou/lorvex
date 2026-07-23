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

  /// Fresh in-memory store with the authoritative schema applied.
  static func freshStore(file: StaticString = #filePath) throws -> LorvexStore {
    let sql = try loadSchemaSQL(file: file)
    return try LorvexStore.openInMemory(schemaSQL: sql)
  }
}
