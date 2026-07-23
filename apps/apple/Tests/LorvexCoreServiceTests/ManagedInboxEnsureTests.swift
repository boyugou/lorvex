import Foundation
import GRDB
import LorvexRuntime
import Testing

@testable import LorvexCore

/// H2: the managed open re-ensures the canonical `inbox` list row, so implicit
/// task creation on the default list can never soft-brick on the `lists`
/// `ON DELETE RESTRICT` foreign key after a database whose `inbox` row went
/// missing (a sync-driven delete, or a database past its once-only baseline
/// seed). Exercised through `SwiftLorvexCoreService` over a real managed
/// on-disk store — the production open path — not the in-memory seam.
struct ManagedInboxEnsureTests {
  @Test
  func createTaskSucceedsAfterInboxRowRemoved() async throws {
    try await withManagedFixture { service, dbPath in
      // First managed open seeds inbox; a create on the default list succeeds.
      _ = try await service.createTask(title: "seed", notes: "")

      // Remove the inbox row out-of-band, then drop the cached handle so the next
      // operation reopens the managed store (and re-runs the inbox ensure).
      try removeInboxRow(at: dbPath)
      service.closeStoreForCutover()

      // Creating a task on the DEFAULT list must now succeed — the managed open
      // re-ensured the inbox row, so it does not hit the ON DELETE RESTRICT FK.
      let task = try await service.createTask(title: "after inbox loss", notes: "")
      #expect(task.title == "after inbox loss")
      #expect(try inboxRowCount(at: dbPath) == 1, "managed open must re-ensure the inbox row")
    }
  }

  /// Delete the `inbox` list row (and any referencing tasks) through a fresh
  /// connection with foreign keys off, so the fixture can drop it despite the
  /// ON DELETE RESTRICT guard. Synchronous so the queue closes at deinit without
  /// an async-context `close()`.
  private func removeInboxRow(at path: String) throws {
    var config = Configuration()
    config.foreignKeysEnabled = false
    let queue = try DatabaseQueue(path: path, configuration: config)
    try queue.write { db in
      try db.execute(sql: "DELETE FROM tasks")
      try db.execute(sql: "DELETE FROM lists WHERE id = 'inbox'")
    }
  }

  private func inboxRowCount(at path: String) throws -> Int {
    let queue = try DatabaseQueue(path: path)
    return try queue.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = 'inbox'") ?? -1
    }
  }

  /// Open a managed-storage service over a throwaway temp directory (platform
  /// data-dir modeling, so `managedGenerationDatabasePath` is non-nil and the
  /// managed-only post-open guarantees run) and pass the service + its resolved
  /// db path to `body`.
  private func withManagedFixture(
    _ body: (SwiftLorvexCoreService, String) async throws -> Void
  ) async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-inbox-ensure-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let dataDir = root.appendingPathComponent("AppSupport").path
    let dbPath = dataDir + "/Lorvex/db.sqlite"
    let env = InMemoryDbLocatorEnv(dataDir: dataDir, homeDir: root.path, platform: .current)
    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      try await body(SwiftLorvexCoreService(databasePath: nil), dbPath)
    }
  }
}
