import Foundation
import Testing
@testable import LorvexCore

/// Guards the production schema path: constructing `SwiftLorvexCoreService` with
/// only a database path (no explicit `schemaSQL`, the way `AppCoreFactory` /
/// `LorvexCoreRuntimeFactory` build it in the shipping app) must resolve the
/// bundled `schema.sql` resource and open a usable database. This would have
/// caught the gap where the Swift core could only find schema via an env var or
/// the dev repo checkout — never in a packaged build.
@Test
func swiftCoreOpensFreshDatabaseFromBundledSchema() async throws {
  let dbPath = NSTemporaryDirectory()
    + "lorvex-schema-smoke-\(UUID().uuidString).db"
  defer { try? FileManager.default.removeItem(atPath: dbPath) }

  let core = SwiftLorvexCoreService(databasePath: dbPath)
  // loadToday() opens the store, which applies the resolved schema. A fresh DB
  // has no tasks; the call succeeding at all proves schema resolution worked.
  let snapshot = try await core.loadToday()
  #expect(snapshot.tasks.isEmpty)

  // And a round-trip write proves the applied schema is actually functional.
  let created = try await core.createTask(title: "Schema smoke", notes: "")
  #expect(created.title == "Schema smoke")
}

@Test
func swiftCoreSchemaChecksumMatchesSharedLock() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let sql = try String(contentsOf: root.appendingPathComponent("schema/schema.sql"), encoding: .utf8)
  let lockData = try Data(contentsOf: root.appendingPathComponent("apps/apple/Sources/LorvexCore/Resources/checksums.lock"))
  let lock = try #require(
    JSONSerialization.jsonObject(with: lockData) as? [String: [String: String]])
  let expected = try #require(lock["001"]?["sha256"])

  #expect(SwiftLorvexCoreService.normalizedSchemaChecksumForTesting(sql) == expected)
  #expect(throws: LorvexCoreError.self) {
    try SwiftLorvexCoreService.verifySchemaChecksumForTesting(
      sql: sql + "\nCREATE TABLE checksum_should_fail(id TEXT);\n",
      expectedChecksum: expected)
  }
}
