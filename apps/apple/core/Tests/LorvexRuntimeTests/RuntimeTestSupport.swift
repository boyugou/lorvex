import Foundation
import GRDB
import LorvexStore

/// Shared helpers for `LorvexRuntimeTests`. Mirrors the `freshStore` pattern in
/// `LorvexStoreTests/TestSupport.swift` but lives here so the runtime test
/// target stays self-contained.
enum RuntimeTestSupport {
  /// Load the authoritative root `schema/schema.sql` via `#filePath`-relative
  /// path. Layout: `apps/apple/core/Tests/LorvexRuntimeTests/<file>.swift` →
  /// `<repo>/lorvex/schema/schema.sql` (5 levels up).
  static func loadSchemaSQL(file: StaticString = #filePath) throws -> String {
    var path = (String(describing: file) as NSString).deletingLastPathComponent
    for _ in 0..<5 {
      path = (path as NSString).deletingLastPathComponent
    }
    let schemaPath = (path as NSString).appendingPathComponent("schema/schema.sql")
    return try String(contentsOfFile: schemaPath, encoding: .utf8)
  }

  /// Fresh in-memory store with the authoritative root schema applied — gives
  /// the runtime tests `sync_checkpoints` and `local_counters` exactly as
  /// production migrations create them.
  static func freshStore(file: StaticString = #filePath) throws -> LorvexStore {
    let sql = try loadSchemaSQL(file: file)
    return try LorvexStore.openInMemory(schemaSQL: sql)
  }
}
