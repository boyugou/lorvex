import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// Coverage for what Settings → Diagnostics shows about failures.
///
/// A Cloud Sync cycle keeps its technical detail out of the user-facing status
/// line by design and writes it to `error_logs` instead, so this feed is the
/// only place on the device that can name why sync is failing. These pin that
/// it does.

@MainActor
@Test
func mobileDiagnosticsFeedCarriesAppErrorsAlongsideSystemCrashes() async throws {
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  try await core.appendDiagnosticLog(
    source: "metrickit.crash", level: "error", message: "App crash",
    details: "RUNNINGBOARD 0xdead10cc")
  try await core.appendDiagnosticLog(
    source: "ios.cloud_sync.cycle", level: "error", message: "Cloud sync failed.",
    details: "CKErrorDomain 26: zone not found")

  await store.loadRecentDiagnosticLogs()

  let origins = Set(store.recentDiagnosticLogs.compactMap(\.origin))
  #expect(origins.contains("metrickit.crash"))
  #expect(origins.contains("ios.cloud_sync.cycle"))
  #expect(
    store.recentDiagnosticLogs.contains { $0.details?.contains("zone not found") == true },
    "the transport's own words are the payload this feed exists to carry")
}

@MainActor
@Test
func mobileDiagnosticsFeedLeavesRoutineLowerSeverityRowsOut() async throws {
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  try await core.appendDiagnosticLog(
    source: "ios.retention.gc", level: "warn", message: "Retention sweep deferred.", details: nil)
  try await core.appendDiagnosticLog(
    source: "ios.setup", level: "info", message: "Seeded default list.", details: nil)

  await store.loadRecentDiagnosticLogs()

  #expect(
    store.recentDiagnosticLogs.isEmpty,
    "a failure panel that also lists routine activity buries the failures")
}
