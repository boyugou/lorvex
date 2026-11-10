import Foundation
import GRDB
import LorvexRuntime
import LorvexStore
import Synchronization
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

  /// Suspending interrupts a statement, but the operation that ran it holds its
  /// locks until its thread has unwound, so a host waits for the operations in
  /// flight before it lets the system suspend the process.
  @Test
  func suspendingWaitsForTheOperationsInFlight() {
    let state = DatabaseSuspension.State { _ in }
    DatabaseSuspension.$stateOverride.withValue(state) {
      // Nothing in flight: no wait.
      #expect(DatabaseSuspension.suspend(waitingForOperations: 5))
      #expect(DatabaseSuspension.isSuspended)
      DatabaseSuspension.resume()

      // One that ends while the suspension waits. The wait blocks this thread,
      // so the operation ends on a thread of its own: a task would need the
      // cooperative pool, which a full parallel run can keep busy past the bound.
      DatabaseSuspension.operationWillBegin()
      Thread.detachNewThread {
        Thread.sleep(forTimeInterval: 0.04)
        state.operations.leave()
      }
      #expect(DatabaseSuspension.suspend(waitingForOperations: 5))
      DatabaseSuspension.resume()

      // One that does not end: the wait gives up at its bound and says so.
      DatabaseSuspension.operationWillBegin()
      #expect(!DatabaseSuspension.suspend(waitingForOperations: 0.05))
      DatabaseSuspension.operationDidEnd()
    }
  }

  /// A managed operation is counted from before it reads the suspended flag
  /// until its lock is released, and a refused one leaves nothing counted.
  @Test
  func managedOperationsAreCountedWhileTheyHoldTheLease() async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-suspension-count-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let env = InMemoryDbLocatorEnv(
      dataDir: root.appendingPathComponent("AppSupport").path, homeDir: root.path,
      platform: .current)
    let state = DatabaseSuspension.State { _ in }

    try await DatabaseSuspension.$stateOverride.withValue(state) {
      try await SwiftLorvexCoreService.$dbLocatorEnvironmentOverride.withValue(env) {
        let service = SwiftLorvexCoreService(databasePath: nil)
        _ = try await service.setPreference(key: "theme", value: "system")

        let idleInside = try service.read { _ in
          // In flight: a suspension asked to wait gives up at its bound.
          state.operations.waitUntilIdle(deadline: Date().addingTimeInterval(0.05))
        }
        #expect(!idleInside)
        #expect(state.operations.waitUntilIdle(deadline: Date()))

        DatabaseSuspension.suspend()
        #expect(throws: DatabaseError.self) { try service.read { _ in } }
        #expect(state.operations.waitUntilIdle(deadline: Date()))
        DatabaseSuspension.resume()
      }
    }
  }

  @Test
  func suspendAndResumeTrackTheirOwnState() {
    // A state of its own: the real one is shared with every test running beside
    // this one, and a posted notification flags every connection they hold open.
    let posted = Mutex<[Notification.Name]>([])
    let state = DatabaseSuspension.State { name in posted.withLock { $0.append(name) } }
    DatabaseSuspension.$stateOverride.withValue(state) {
      #expect(!DatabaseSuspension.isSuspended)
      DatabaseSuspension.suspend()
      #expect(DatabaseSuspension.isSuspended)
      DatabaseSuspension.suspendConnectionOpenedWhileSuspended()
      DatabaseSuspension.resume()
      #expect(!DatabaseSuspension.isSuspended)
      DatabaseSuspension.suspendConnectionOpenedWhileSuspended()
    }
    #expect(
      posted.withLock { $0 }
        == [Database.suspendNotification, Database.suspendNotification, Database.resumeNotification])
  }
}
