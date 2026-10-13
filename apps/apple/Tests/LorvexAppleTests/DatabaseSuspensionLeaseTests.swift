import Foundation
import GRDB
import LorvexRuntime
import LorvexStore
import Testing

@testable import LorvexCore

/// A suspended store takes no lock the system could suspend the process on: the
/// cutover lease, a `flock` on a file in the App Group container, is not taken
/// either, so database work is refused as a suspended connection refuses it, and
/// runs again once the store is resumed.
@Suite(.serialized)
struct DatabaseSuspensionLeaseTests {
  @Test
  func managedWorkIsRefusedWithoutTheLeaseWhileSuspendedAndRunsAfterwards() async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-suspension-lease-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let dataDir = root.appendingPathComponent("AppSupport").path
    let env = InMemoryDbLocatorEnv(dataDir: dataDir, homeDir: root.path, platform: .current)

    try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
      let service = SwiftLorvexCoreService(databasePath: nil)
      _ = try await service.setPreference(key: "theme", value: "system")

      // Suspended: refused before any lock, with the error a suspended connection raises.
      await DatabaseSuspension.$suspendedOverride.withValue(true) {
        do {
          _ = try await service.getPreference(key: "theme")
          Issue.record("work ran while the store was suspended")
        } catch let error as DatabaseError {
          #expect(error.resultCode == .SQLITE_ABORT)
        } catch {
          Issue.record("unexpected error \(error)")
        }
      }

      // Resumed: the same work runs.
      let value = try await service.getPreference(key: "theme")
      #expect(value == "\"system\"")
    }
  }

  @Test
  func suspendAndResumeTrackTheProcessState() {
    // Nothing else in the process posts these, so the real flag is safe here.
    #expect(!DatabaseSuspension.isSuspended)
    DatabaseSuspension.suspend()
    #expect(DatabaseSuspension.isSuspended)
    DatabaseSuspension.resume()
    #expect(!DatabaseSuspension.isSuspended)
  }
}
