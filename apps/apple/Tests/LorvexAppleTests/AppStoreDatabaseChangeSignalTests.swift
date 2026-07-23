import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import Synchronization
import Testing

@testable import LorvexApple

@Suite(.serialized)
@MainActor
struct AppStoreDatabaseChangeSignalTests {
  @Test("only a successful canonical inbound report broadcasts and reloads its domain")
  func inboundApplyBroadcastIsMutationGated() async throws {
    let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    let store = AppStore(core: core)
    let deliveries = Mutex(0)
    let token = NotificationCenter.default.addObserver(
      forName: DatabaseChangeSignal.didChangeNotification,
      object: store,
      queue: nil
    ) { _ in
      deliveries.withLock { $0 += 1 }
    }
    defer { NotificationCenter.default.removeObserver(token) }

    // A server winner applied from the outbound conflict path has no fetched
    // page, but is still a canonical inbound mutation that must reload/broadcast.
    let applied = CloudSyncCycleReport(
      pushedRecordCount: 1, failedPushCount: 0, fetchedRecordCount: 0,
      moreInboundComing: false,
      inbound: InboundApplyReport(applied: 1, appliedEntityTypes: [.habit]))
    await store.reconcileSurfacesAfterCompletedCloudSyncCycle(applied)

    #expect(deliveries.withLock { $0 } == 1)
    #expect(core.loadHabitsCallCount == 1)
    #expect(core.loadTodayCallCount == 0)

    // Empty/fetched-but-skipped and pure-outbound reports do not claim a
    // canonical mutation, so they must not wake detached stores. The fetched
    // empty report may conservatively request a full local read, but it cannot
    // create another notification/sync loop.
    let skipped = CloudSyncCycleReport(
      pushedRecordCount: 0, failedPushCount: 0, fetchedRecordCount: 1,
      moreInboundComing: false, inbound: InboundApplyReport(skipped: 1))
    await store.reconcileSurfacesAfterCompletedCloudSyncCycle(skipped)
    let outbound = CloudSyncCycleReport(
      pushedRecordCount: 1, failedPushCount: 0, fetchedRecordCount: 0,
      moreInboundComing: false, inbound: InboundApplyReport())
    await store.reconcileSurfacesAfterCompletedCloudSyncCycle(outbound)

    #expect(deliveries.withLock { $0 } == 1)
  }
}
