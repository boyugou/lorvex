import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple
@testable import LorvexMobile

/// The macOS `AppStore` and iOS `MobileStore` alert surfaces route thrown
/// errors through ``UserFacingError`` before setting `errorMessage`: a raw UUID
/// / SQL / internal invariant becomes generic localized copy, its technical
/// detail is logged to `error_logs`, and a clean validation message passes
/// through.
private let sampleUUID = "0192f3a1-7c4b-7def-9abc-1234567890ab"

private struct CleanCloudTransportError: LocalizedError {
  var errorDescription: String? { "The server is temporarily unavailable." }
}

@MainActor
@Test("macOS: a not-found error shows the generic message, not the raw UUID, and logs the detail")
func appStoreNotFoundIsGenericAndLogged() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)

  await store.presentUserFacingError(
    LorvexCoreError.unsupportedOperation("Task '\(sampleUUID)' was not found."))

  #expect(store.errorMessage == "That item no longer exists.")
  #expect(store.errorMessage?.contains(sampleUUID) == false)

  let logs = try await core.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  let logged = logs.entries.first { $0.details?.contains(sampleUUID) == true }
  let entry = try #require(logged, "the raw UUID must be preserved in error_logs")
  #expect(entry.origin == "macos.ui.action_failed")
  #expect(entry.level == .error)
}

@MainActor
@Test("macOS: a validation error passes through its bound message and is not logged")
func appStoreValidationPassesThrough() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)

  await store.presentUserFacingError(
    LorvexCoreError.unsupportedOperation("Mood must be between 1 and 5."))

  #expect(store.errorMessage == "Mood must be between 1 and 5.")

  let logs = try await core.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: false)
  #expect(!logs.entries.contains { $0.origin == "macos.ui.action_failed" })
}

@MainActor
@Test("iOS: a not-found error shows the generic message, not the raw UUID, and logs the detail")
func mobileStoreNotFoundIsGenericAndLogged() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)

  await store.presentUserFacingError(
    LorvexCoreError.unsupportedOperation("List '\(sampleUUID)' not found."))

  #expect(store.errorMessage == "That item no longer exists.")
  #expect(store.errorMessage?.contains(sampleUUID) == false)

  let logs = try await core.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  let logged = logs.entries.first { $0.details?.contains(sampleUUID) == true }
  let entry = try #require(logged, "the raw UUID must be preserved in error_logs")
  #expect(entry.origin == "ios.ui.action_failed")
}

@MainActor
@Test("iOS: a validation error passes through its bound message")
func mobileStoreValidationPassesThrough() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())

  await store.presentUserFacingError(
    LorvexCoreError.unsupportedOperation("A habit name is required."))

  #expect(store.errorMessage == "A habit name is required.")
}

@MainActor
@Test("Cloud sync banners never expose transport wording and retain diagnostics")
func cloudSyncBannersAreGenericAndLogged() async throws {
  let macCore = try await makeSeededInMemoryCore()
  let macStore = AppStore(core: macCore)
  let macMessage = await macStore.cloudSyncUserFacingErrorMessage(
    for: CleanCloudTransportError(), source: "macos.cloud_sync.test")
  #expect(macMessage == macStore.userFacingErrorCopy.somethingWentWrong)
  #expect(!macMessage.contains("server"))

  let mobileCore = try await makeSeededInMemoryCore()
  let mobileStore = MobileStore(core: mobileCore)
  let mobileMessage = await mobileStore.cloudSyncUserFacingErrorMessage(
    for: CleanCloudTransportError(), source: "ios.cloud_sync.test")
  #expect(mobileMessage == mobileStore.userFacingErrorCopy.somethingWentWrong)
  #expect(!mobileMessage.contains("server"))

  let macLogs = try await macCore.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  #expect(
    macLogs.entries.contains {
      $0.origin == "macos.cloud_sync.test"
        && $0.details?.contains("temporarily unavailable") == true
    })
  let mobileLogs = try await mobileCore.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  #expect(
    mobileLogs.entries.contains {
      $0.origin == "ios.cloud_sync.test"
        && $0.details?.contains("temporarily unavailable") == true
    })
}
