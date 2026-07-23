import Foundation

@testable import LorvexStore

/// Shared helpers for `LorvexWorkflowTests`. Mirrors the store-tests'
/// `TestSupport` shim — the file lives once per test target rather than as a
/// shared library because the `LorvexStore` `@testable import` is module-
/// scoped and SwiftPM test targets cannot depend on each other.
enum WorkflowTestSupport {
  /// Layout: `apps/apple/core/Tests/LorvexWorkflowTests/<file>.swift` →
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
