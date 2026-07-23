import Foundation
import LorvexCore
import LorvexMobile
import Testing

@testable import LorvexApple

/// C-8: the stores must READ the core's quarantine notice and surface it, once.
/// Before this the notice was dead code and a set-aside database was silent.
@Suite("Database-recovery notice reaches the stores exactly once")
struct DatabaseRecoveryNoticeWiringTests {
  private func seededCore() async throws -> StubFocusCoreService {
    let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    core.databaseRecoveryNotice = DatabaseRecoveryNotice(
      backupPath: "/tmp/lorvex.incompatible-20260701.bak",
      reason: "schema checksum mismatch")
    return core
  }

  @MainActor
  @Test("AppStore surfaces the recovery message on first refresh and not again")
  func appStoreSurfacesRecoveryMessageOnce() async throws {
    let store = AppStore(
      core: try await seededCore(),
      taskSearchIndexer: RecordingTaskSearchIndexer(),
      widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
    )

    await store.refresh()
    let message = store.databaseRecoveryMessage
    #expect(message?.contains("/tmp/lorvex.incompatible-20260701.bak") == true)
    #expect(message?.contains("schema checksum mismatch") == true)

    // One-time: after the user dismisses it, a later refresh does not re-raise it.
    store.databaseRecoveryMessage = nil
    await store.refresh()
    #expect(store.databaseRecoveryMessage == nil)
  }

  @MainActor
  @Test("MobileStore surfaces the recovery message on first refresh and not again")
  func mobileStoreSurfacesRecoveryMessageOnce() async throws {
    let store = MobileStore(core: try await seededCore())

    await store.refresh()
    let message = store.databaseRecoveryMessage
    #expect(message?.contains("schema checksum mismatch") == true)
    // The backup lives in the app's sandbox container, a path the user can't
    // navigate to on iOS, so the mobile notice omits it (unlike the macOS one).
    #expect(message?.contains("/tmp/lorvex.incompatible-20260701.bak") == false)

    store.databaseRecoveryMessage = nil
    await store.refresh()
    #expect(store.databaseRecoveryMessage == nil)
  }
}
