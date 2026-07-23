import Foundation
import LorvexCore
import Testing
import LorvexCloudSync

@testable import LorvexApple

// MARK: - Status report aggregation

@Test
func cloudSyncStatusReportSummaryWhenOffMode() {
  let report = CloudSyncStatusReport(
    mode: .off,
    accountAvailability: .noAccount,
    pauseReason: nil,
    lastPushAt: nil,
    lastPushError: nil,
    lastPullAt: nil,
    lastPullError: nil,
    pendingCount: 0
  )
  #expect(report.localizedSettingsSummary == "iCloud Sync is off.")
  #expect(report.isOperational == false)
}

@Test
func cloudSyncStatusReportSummaryWhenLiveModeNoAccount() {
  let report = CloudSyncStatusReport(
    mode: .live,
    accountAvailability: .noAccount,
    pauseReason: nil,
    lastPushAt: nil,
    lastPushError: nil,
    lastPullAt: nil,
    lastPullError: nil,
    pendingCount: 0
  )
  #expect(report.localizedSettingsSummary.contains("iCloud"))
  #expect(report.isOperational == false)
}

@Test
func cloudSyncStatusReportIsOperationalWhenLiveAndAvailable() {
  let report = CloudSyncStatusReport(
    mode: .live,
    accountAvailability: .available,
    pauseReason: nil,
    lastPushAt: Date(timeIntervalSinceNow: -60),
    lastPushError: nil,
    lastPullAt: Date(timeIntervalSinceNow: -30),
    lastPullError: nil,
    pendingCount: 2
  )
  #expect(report.isOperational == true)
  #expect(report.localizedSettingsSummary.contains("Live sync active"))
}

@Test
func cloudSyncStatusReportIsNotOperationalWhenDurablyPaused() {
  // A standing pause (account changed / zone deleted / backfill failed) stops sync
  // until the user acts. Even under `.live` mode with an available account, the
  // report must read NOT operational so the Settings icon doesn't show green over
  // the "Sync Paused" notice.
  for reason in CloudSyncPauseReason.allCases {
    let report = CloudSyncStatusReport(
      mode: .live,
      accountAvailability: .available,
      pauseReason: reason,
      lastPushAt: Date(timeIntervalSinceNow: -60),
      lastPushError: nil,
      lastPullAt: Date(timeIntervalSinceNow: -30),
      lastPullError: nil,
      pendingCount: 0
    )
    #expect(report.isOperational == false, "paused (\(reason)) must not read operational")
  }
}

@Test
func cloudSyncStatusReportReflectsPushErrorAndPullError() {
  let report = CloudSyncStatusReport(
    mode: .live,
    accountAvailability: .available,
    pauseReason: nil,
    lastPushAt: nil,
    lastPushError: "Network error",
    lastPullAt: nil,
    lastPullError: "Token expired",
    pendingCount: 0
  )
  #expect(report.lastPushError == "Network error")
  #expect(report.lastPullError == "Token expired")
}

// MARK: - Account availability user-facing messages

@Test
func cloudKitAccountAvailabilityUserFacingMessages() {
  #expect(CloudKitAccountAvailability.noAccount.userFacingMessage.contains("No iCloud"))
  #expect(CloudKitAccountAvailability.restricted.userFacingMessage.contains("restricted"))
  #expect(CloudKitAccountAvailability.available.userFacingMessage.contains("available"))
}

// MARK: - AppStore cloudSyncStatusReport derivation

@MainActor
@Test
func appStoreCloudSyncStatusReportDerivesFromSyncStorage() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
    cloudSyncMode: .live
  )
  await store.refresh()

  let report = store.cloudSyncStatusReport
  #expect(report.mode == .live)
  // accountAvailability defaults to .couldNotDetermine (no real CKContainer in tests).
  #expect(report.accountAvailability == .couldNotDetermine)
  // No coordinator is wired (SwiftLorvexCoreService does not support envelope
  // sync and no CK container exists), so no cycle has run.
  #expect(report.lastPullAt == nil)
}
