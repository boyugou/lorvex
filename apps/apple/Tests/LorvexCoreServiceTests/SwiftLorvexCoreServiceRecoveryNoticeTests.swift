import Foundation
import Testing

@testable import LorvexCore

/// C-8: an on-disk database that couldn't be opened (corrupt / schema-incompatible)
/// is quarantined and a fresh one created; the service must expose that as a
/// readable `databaseRecoveryNotice` so a surface can tell the user their data
/// was set aside, instead of silently handing them an empty app.
struct SwiftLorvexCoreServiceRecoveryNoticeTests {
  private func schemaSQL() throws -> String {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    return try String(contentsOf: schemaURL, encoding: .utf8)
  }

  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-recovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  @Test("a quarantined database surfaces a recovery notice with the backup location")
  func quarantineSurfacesRecoveryNotice() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("lorvex.sqlite")
    // A non-SQLite file forces the open path to quarantine and start fresh.
    try Data("this is not a sqlite database".utf8).write(to: dbURL)

    let service = SwiftLorvexCoreService(databasePath: dbURL.path, schemaSQL: try schemaSQL())
    _ = try await service.loadToday()  // opens the store, triggering quarantine

    let notice = try #require(service.databaseRecoveryNotice)
    #expect(notice.reason.isEmpty == false)
    // The quarantined file is preserved alongside the original, not deleted.
    #expect(notice.backupPath.hasPrefix(dir.path))
    #expect(notice.backupPath != dbURL.path)
    #expect(FileManager.default.fileExists(atPath: notice.backupPath))
  }

  @Test("a clean open reports no recovery notice")
  func cleanOpenReportsNoNotice() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbURL = dir.appendingPathComponent("fresh.sqlite")

    let service = SwiftLorvexCoreService(databasePath: dbURL.path, schemaSQL: try schemaSQL())
    _ = try await service.loadToday()

    #expect(service.databaseRecoveryNotice == nil)
  }
}
