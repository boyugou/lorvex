import Foundation
import Testing

@testable import LorvexMCPHost

/// Coverage for `LorvexMCPHost.runProbe`, the body of the `LORVEX_MCP_PROBE=1`
/// self-check the MCP settings panel runs against the bundled helper. Before
/// the fix this branch never constructed a `CoreBridgeConfiguration` or opened
/// the store, so a denied App Group or an unreachable path reported "ready"
/// regardless. These tests exercise the same configuration + open path a real
/// MCP client's first tool call would take, so a broken configuration fails here
/// exactly as it would for that client.
struct LorvexMCPHostProbeTests {
  @Test("probe succeeds against a fresh on-disk database")
  func probeSucceedsAgainstFreshOnDiskDatabase() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-mcp-host-probe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let dbPath = directory.appendingPathComponent("db.sqlite").path

    try await LorvexMCPHost.runProbe(environment: ["LORVEX_APPLE_DB_PATH": dbPath])
  }

  @Test("probe fails when the configured database path cannot be opened")
  func probeFailsForUnreachableDatabasePath() async throws {
    // A regular file blocking a path component makes the directory the store
    // would need to create unreachable, so the real open path this exercises
    // throws exactly as it would for a real client launched against the same
    // broken configuration (e.g. storage that moved or lost permissions).
    let blocker = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-mcp-host-probe-blocker-\(UUID().uuidString)")
    try Data().write(to: blocker)
    defer { try? FileManager.default.removeItem(at: blocker) }
    let unreachableDBPath = blocker.appendingPathComponent("sub").appendingPathComponent("db.sqlite").path

    await #expect(throws: (any Error).self) {
      try await LorvexMCPHost.runProbe(environment: ["LORVEX_APPLE_DB_PATH": unreachableDBPath])
    }
  }
}
