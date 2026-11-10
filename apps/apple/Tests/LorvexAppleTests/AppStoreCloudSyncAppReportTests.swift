import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The Mac app tells the assistant, through the shared database, whether it
/// is syncing; the MCP helper reads it back for `get_sync_status`.
@Suite("The Mac app reports its sync state for the assistant")
struct AppStoreCloudSyncAppReportTests {
  private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
  }

  @MainActor
  @Test
  func aRefreshRecordsTheSyncModeAndState() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core, cloudSyncMode: .off)

    await store.refresh()

    let report = try #require(try await core.loadCloudSyncAppReport())
    #expect(report.mode == "off")
    #expect(report.state == "stopped")
    #expect(report.lastCompletedPassAt == nil)
  }

  @MainActor
  @Test
  func anUnchangedReportIsWrittenAgainOnlyOnceItHasAged() async throws {
    let core = try await makeSeededInMemoryCore()
    let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
    let store = AppStore(core: core, cloudSyncMode: .off, now: { clock.now })

    await store.reportCloudSyncToAssistant()
    let first = try #require(try await core.loadCloudSyncAppReport())

    clock.advance(60)
    await store.reportCloudSyncToAssistant()
    #expect(try await core.loadCloudSyncAppReport()?.reportedAt == first.reportedAt)

    clock.advance(AppStore.cloudSyncAppReportRefreshInterval)
    await store.reportCloudSyncToAssistant()
    #expect(try await core.loadCloudSyncAppReport()?.reportedAt != first.reportedAt)
  }

  @MainActor
  @Test
  func aCompletedPassIsReportedAtOnce() async throws {
    let core = try await makeSeededInMemoryCore()
    let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
    let store = AppStore(core: core, cloudSyncMode: .off, now: { clock.now })
    await store.reportCloudSyncToAssistant()

    clock.advance(30)
    store.lastCloudSyncRemoteChangeSucceededAt = clock.now
    await store.reportCloudSyncToAssistant()

    let report = try #require(try await core.loadCloudSyncAppReport())
    #expect(report.lastCompletedPassAt == AppStore.reportTimestamp(clock.now))
  }
}
