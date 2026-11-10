import Foundation
import GRDB
import LorvexRuntime
import LorvexStore
import Testing

@testable import LorvexCore

/// Guards on the managed store that outlast its open: a schema a newer build
/// has migrated since, and the notice that a database was set aside.
@Suite(.serialized)
struct ManagedStoreGuardTests {
  private func withManagedRoot<T>(
    _ body: () async throws -> T
  ) async throws -> T {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-managed-guard-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let env = InMemoryDbLocatorEnv(
      dataDir: root.appendingPathComponent("AppSupport").path, homeDir: root.path,
      platform: .current)
    return try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      try await body()
    }
  }

  /// A helper process stays open across an app update. Once the updated app
  /// has migrated the database, the helper's writes are refused with the error
  /// an open would raise, and its reads go on.
  @Test
  func aWriteIsRefusedOnceANewerBuildHasMigratedTheDatabase() async throws {
    try await withManagedRoot {
      let service = SwiftLorvexCoreService(databasePath: nil, writeInitiatorDefault: "user")
      _ = try await service.setPreference(key: "theme", value: "system")

      let top = try service.schemaLadderTop()
      try service.write { db in
        try db.execute(
          sql: "INSERT INTO schema_migrations (version, name, checksum) VALUES (?, ?, ?)",
          arguments: [top + 1, "from_a_newer_build", "0"])
      }

      await #expect(throws: LorvexStore.SchemaDowngrade.self) {
        _ = try await service.setPreference(key: "theme", value: "dark")
      }
      #expect(try await service.getPreference(key: "theme") == "\"system\"")
    }
  }

  /// The process that meets an unreadable database may be a helper, or may end
  /// before anyone reads its notice. The fresh database remembers the
  /// quarantine until the user has seen it.
  @Test
  func aSetAsideDatabaseIsRememberedUntilTheNoticeIsAcknowledged() async throws {
    try await withManagedRoot {
      let first = SwiftLorvexCoreService(databasePath: nil, writeInitiatorDefault: "user")
      _ = try await first.setPreference(key: "theme", value: "system")
      let path = try #require(first.openedManagedDatabasePathSnapshot())
      first.closeStoreForCutover()

      // The file becomes unreadable.
      let fm = FileManager.default
      for sidecar in ["-wal", "-shm"] { try? fm.removeItem(atPath: path + sidecar) }
      try Data("this is not a database".utf8).write(to: URL(fileURLWithPath: path))

      // A helper opens it: the file is set aside and a fresh one created.
      let helper = SwiftLorvexCoreService(databasePath: nil, writeInitiatorDefault: "user")
      _ = try await helper.getPreference(key: "theme")
      let own = try #require(helper.databaseRecoveryNotice)
      #expect(fm.fileExists(atPath: own.backupPath))
      helper.closeStoreForCutover()

      // The app opens the fresh database cleanly, and still learns of it.
      let app = SwiftLorvexCoreService(databasePath: nil, writeInitiatorDefault: "user")
      _ = try await app.getPreference(key: "theme")
      #expect(app.databaseRecoveryNotice == nil)
      #expect(await app.pendingDatabaseRecoveryNotice() == own)

      await app.acknowledgeDatabaseRecoveryNotice()
      #expect(await app.pendingDatabaseRecoveryNotice() == nil)
      app.closeStoreForCutover()

      let later = SwiftLorvexCoreService(databasePath: nil, writeInitiatorDefault: "user")
      #expect(await later.pendingDatabaseRecoveryNotice() == nil)
    }
  }
}
