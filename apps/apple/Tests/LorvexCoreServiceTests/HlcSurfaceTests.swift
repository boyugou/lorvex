import Foundation
import LorvexDomain
import Testing

@testable import LorvexCore

/// Separate writer surfaces can write the same database from independent
/// processes with independent monotonic counters; each must mint HLCs under its
/// own surface suffix or same-millisecond writes can collide, weakening the
/// per-device strict monotonicity LWW rests on.
@Suite("HLC surface separation")
struct HlcSurfaceTests {
  @Test("all writer surfaces mint distinct HLC suffixes over one database")
  func surfacesMintDistinctSuffixes() async throws {
    let dir = NSTemporaryDirectory() + "lorvex-hlc-surface-\(UUID().uuidString)/"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let path = dir + "db.sqlite"

    let readService = SwiftLorvexCoreService(databasePath: path)
    var taskIDs: [String] = []
    for surface in HlcSurface.allSurfaces {
      let service = SwiftLorvexCoreService(databasePath: path, surface: surface)
      let task = try await service.createTask(title: "From \(surface.rawValue)", notes: "")
      taskIDs.append(task.id)
    }

    func suffix(_ id: String) throws -> String {
      let version = try readService.read { db in
        try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [id])
      }
      return try Hlc.parse(#require(version)).deviceSuffix
    }

    let suffixes = try taskIDs.map(suffix)
    #expect(Set(suffixes).count == HlcSurface.allSurfaces.count)
  }
}
