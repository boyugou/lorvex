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

/// A log row replaces its combined accessibility label with a short phrase
/// (origin, summary, age), which leaves the detail line out. The detail is the
/// payload the feed exists to show, so the row must speak it as its value.
@Test
func mobileDiagnosticLogRowSpeaksItsDetailAsTheValue() throws {
  let source = try String(
    contentsOf: URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Sources/LorvexMobile/MobileDiagnosticLogRow.swift"),
    encoding: .utf8)
  #expect(source.contains(".accessibilityLabel(accessibilityLabel)"))
  #expect(source.contains(".accessibilityValue(details ?? \"\")"))
}

/// The shared report is how a failure leaves the phone, so it carries what a
/// screenshot of the list cannot: the build and system it happened on, and
/// each entry's exact time and whole detail line.
@Test
func mobileDiagnosticsReportNamesTheBuildAndCarriesEveryEntryInFull() {
  let detail = String(repeating: "frame ", count: 80) + "end"
  let report = MobileDiagnosticsReport.text(
    entries: [
      RecentLogEntry(
        id: "2", timestamp: "2026-11-22T02:57:59.050Z", source: "error_log", level: .error,
        summary: "Cloud sync failed.", details: "CKErrorDomain 2", origin: "ios.cloud_sync.cycle"),
      RecentLogEntry(
        id: "1", timestamp: "2026-11-15T10:00:00.000Z", source: "error_log", level: .error,
        summary: "App crash", details: detail, origin: "metrickit.crash"),
      RecentLogEntry(
        id: "0", timestamp: nil, source: "error_log", level: .error, summary: "No detail"),
    ],
    appVersion: "1.0.0", build: "174", system: "Version 27.2", model: "iPhone18,1")

  let lines = report.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  #expect(lines[0] == "Lorvex 1.0.0 (174) · Version 27.2 · iPhone18,1")
  #expect(lines[1] == "3 entries, newest first")
  #expect(
    Array(lines[2...5]) == [
      "", "2026-11-22T02:57:59.050Z  error  ios.cloud_sync.cycle", "Cloud sync failed.",
      "CKErrorDomain 2",
    ])
  #expect(lines.contains(detail), "a long detail line is not shortened")
  #expect(Array(lines.suffix(3)) == ["", "error  error_log", "No detail"])
}
