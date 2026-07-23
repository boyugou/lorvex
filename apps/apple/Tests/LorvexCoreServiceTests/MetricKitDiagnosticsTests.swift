import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import Testing

@testable import LorvexCore

/// The MetricKit crash/hang observability path: the pure diagnostic→`error_logs`
/// mapping, and the read surfaces that render the appended rows on both the
/// on-disk core and the in-memory fake.
@Suite("MetricKit diagnostics")
struct MetricKitDiagnosticsTests {

  // MARK: - Diagnostic → error_logs mapping

  @Test("crash maps to error / metrickit.crash with an exception+signal summary")
  func crashMapping() {
    let record = MetricKitDiagnosticMapper.record(
      for: MetricKitDiagnosticFields(
        kind: .crash, exceptionType: 1, exceptionCode: 0, signal: 11,
        terminationReason: "Namespace SIGNAL", details: #"{"k":"v"}"#))

    #expect(record.source == "metrickit.crash")
    #expect(record.level == "error")
    #expect(
      record.message
        == "App crash: Namespace SIGNAL (exceptionType=1, exceptionCode=0, signal=11)")
    #expect(record.details == #"{"k":"v"}"#)
  }

  @Test("crash with no fields still maps to a stable summary")
  func crashMappingBare() {
    let record = MetricKitDiagnosticMapper.record(for: MetricKitDiagnosticFields(kind: .crash))
    #expect(record.source == "metrickit.crash")
    #expect(record.level == "error")
    #expect(record.message == "App crash")
    #expect(record.details == nil)
  }

  @Test("hang maps to error / metrickit.hang with a duration summary")
  func hangMapping() {
    let record = MetricKitDiagnosticMapper.record(
      for: MetricKitDiagnosticFields(kind: .hang, hangDurationSeconds: 3.4))
    #expect(record.source == "metrickit.hang")
    #expect(record.level == "error")
    #expect(record.message == "App hang for 3.4s")
  }

  @Test("CPU exception maps to warn / metrickit.cpu_exception")
  func cpuMapping() {
    let record = MetricKitDiagnosticMapper.record(
      for: MetricKitDiagnosticFields(kind: .cpuException, cpuTimeSeconds: 21.7))
    #expect(record.source == "metrickit.cpu_exception")
    #expect(record.level == "warn")
    #expect(record.message == "CPU exception: 21.7s of CPU time")
  }

  @Test("disk-write exception maps to warn / metrickit.disk_write with a byte label")
  func diskMapping() {
    let record = MetricKitDiagnosticMapper.record(
      for: MetricKitDiagnosticFields(kind: .diskWriteException, diskWritesBytes: 2_500_000))
    #expect(record.source == "metrickit.disk_write")
    #expect(record.level == "warn")
    #expect(record.message == "Excessive disk writes: 2.5 MB")
  }

  // MARK: - Aggregate metric → error_logs mapping

  @Test("aggregate metrics map to an info metrickit.metrics record with compact JSON")
  func metricsRecordMapping() throws {
    let summary = MetricKitMetricsSummary(
      appVersion: "1.2.3", osVersion: "iOS 18.0",
      launchTimeMs: 320, hangTimeMs: 12, peakMemoryMB: 180.5,
      cpuTimeSeconds: 42, logicalWriteKB: 1500,
      foregroundExitCount: 3, backgroundExitCount: 5)
    let record = MetricKitDiagnosticMapper.record(for: summary)

    #expect(record.source == "metrickit.metrics")
    #expect(record.source == MetricKitDiagnosticMapper.metricsSource)
    #expect(record.level == "info")
    #expect(record.message.hasPrefix("MetricKit metrics: "))
    #expect(record.message.contains("launch 320ms"))
    #expect(record.message.contains("peakMem 180.5 MB"))
    #expect(record.message.contains("fgExits 3"))

    // A metrics source is not a crash/hang diagnostic kind.
    #expect(MetricKitDiagnosticMapper.kind(forSource: record.source) == nil)

    // `details` is compact JSON that round-trips the present fields; absent
    // fields are omitted rather than serialized as null.
    let details = try #require(record.details)
    #expect(!details.contains("resumeTimeMs"))
    let decoded = try JSONDecoder().decode(
      MetricKitMetricsSummary.self, from: Data(details.utf8))
    #expect(decoded == summary)
    #expect(decoded.resumeTimeMs == nil)
  }

  @Test("a summary with no measured metrics is flagged empty")
  func metricsSummaryEmptyClassification() {
    #expect(MetricKitMetricsSummary(appVersion: "1.0", osVersion: "iOS 18.0").hasMetrics == false)
    #expect(MetricKitMetricsSummary(peakMemoryMB: 120).hasMetrics)
  }

  @Test("source strings round-trip through the reverse kind classifier")
  func sourceReverseMapping() {
    #expect(MetricKitDiagnosticMapper.kind(forSource: "metrickit.crash") == .crash)
    #expect(MetricKitDiagnosticMapper.kind(forSource: "metrickit.hang") == .hang)
    #expect(MetricKitDiagnosticMapper.kind(forSource: "metrickit.cpu_exception") == .cpuException)
    #expect(
      MetricKitDiagnosticMapper.kind(forSource: "metrickit.disk_write") == .diskWriteException)
    // Any non-MetricKit log source is not a diagnostic kind.
    #expect(MetricKitDiagnosticMapper.kind(forSource: "sync.pending_inbox") == nil)
    #expect(MetricKitDiagnosticMapper.kind(forSource: "metrickit.metrics") == nil)
  }

  // MARK: - Read surface

  @Test("appended diagnostics render newest-first on the read surface")
  func readSurfaceRendersRowsNewestFirst() async throws {
    let service = try makeService()

    let crash = MetricKitDiagnosticMapper.record(
      for: MetricKitDiagnosticFields(
        kind: .crash, signal: 11, terminationReason: "SIGSEGV", details: "{}"))
    let hang = MetricKitDiagnosticMapper.record(
      for: MetricKitDiagnosticFields(kind: .hang, hangDurationSeconds: 2.0))
    try await service.appendDiagnosticLog(
      source: crash.source, level: crash.level, message: crash.message, details: crash.details)
    try await service.appendDiagnosticLog(
      source: hang.source, level: hang.level, message: hang.message, details: hang.details)

    let page = try await service.loadRecentLogs(
      limit: 20, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: false)

    #expect(page.entries.count == 2)
    // Newest-first: the hang was appended after the crash.
    #expect(page.entries.first?.summary == hang.message)
    #expect(page.entries.first?.level == .error)
    #expect(page.entries.last?.summary == crash.message)
    #expect(page.entries.allSatisfy { $0.source == "error_log" })

    // The diagnostics snapshot the settings surface binds to sees them too.
    let snapshot = try await service.loadRuntimeDiagnostics()
    let summaries = snapshot.recentLogs.entries.map(\.summary)
    #expect(summaries.contains(crash.message))
    #expect(summaries.contains(hang.message))
  }

  @Test("empty source or message is dropped")
  func appendDropsEmptySourceOrMessage() async throws {
    let service = try makeService()
    try await service.appendDiagnosticLog(source: "  ", level: "error", message: "x", details: nil)
    try await service.appendDiagnosticLog(
      source: "metrickit.crash", level: "error", message: "   ", details: nil)

    let page = try await service.loadRecentLogs(
      limit: 20, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: false)
    #expect(page.entries.isEmpty)
  }

  // MARK: - Read surface (on-disk core)

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  @Test("appendDiagnosticLog persists an error_logs row the merged feed surfaces")
  func onDiskAppendPersistsAndSurfaces() async throws {
    let service = try makeService()
    let record = MetricKitDiagnosticMapper.record(
      for: MetricKitDiagnosticFields(
        kind: .crash, exceptionType: 1, signal: 11, terminationReason: "SIGSEGV",
        details: #"{"signal":11}"#))

    try await service.appendDiagnosticLog(
      source: record.source, level: record.level, message: record.message,
      details: record.details)

    // The raw row lands in error_logs with the metrickit source preserved.
    let row = try service.read { db -> (String, String, String)? in
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT source, level, message FROM error_logs LIMIT 1")
      else { return nil }
      let source: String = row["source"]
      let level: String = row["level"]
      let message: String = row["message"]
      return (source, level, message)
    }
    let unwrapped = try #require(row)
    #expect(unwrapped.0 == "metrickit.crash")
    #expect(unwrapped.1 == "error")
    #expect(unwrapped.2.contains("App crash"))

    // The merged read path folds it into the newest-first `error_log` stream,
    // projecting the `error_logs.source` column as per-row `origin` provenance.
    let page = try await service.loadRecentLogs(
      limit: 20, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: false)
    let entry = try #require(page.entries.first)
    #expect(entry.source == "error_log")
    #expect(entry.origin == "metrickit.crash")
    #expect(entry.isMetricKitDiagnostic)
    #expect(entry.metricKitDiagnosticKind == .crash)
    #expect(entry.level == .error)
    #expect(entry.summary.contains("App crash"))
    #expect(entry.details != nil)
  }

  @Test("aggregate metrics persist a metrickit.metrics error_logs row via the crash-path seam")
  func onDiskMetricsPersistsAndSurfaces() async throws {
    let service = try makeService()
    let summary = MetricKitMetricsSummary(
      intervalStart: "2026-07-10T00:00:00Z", intervalEnd: "2026-07-11T00:00:00Z",
      appVersion: "1.2.3", osVersion: "iOS 18.0",
      launchTimeMs: 320, peakMemoryMB: 180.5, cpuTimeSeconds: 42)
    let record = MetricKitDiagnosticMapper.record(for: summary)

    // The metrics record uses the same append seam the crash path uses.
    try await service.appendDiagnosticLog(
      source: record.source, level: record.level, message: record.message,
      details: record.details)

    // The raw row lands in error_logs under the metrics source at info level.
    let row = try service.read { db -> (String, String)? in
      guard
        let row = try Row.fetchOne(db, sql: "SELECT source, level FROM error_logs LIMIT 1")
      else { return nil }
      let source: String = row["source"]
      let level: String = row["level"]
      return (source, level)
    }
    let unwrapped = try #require(row)
    #expect(unwrapped.0 == "metrickit.metrics")
    #expect(unwrapped.1 == "info")

    // The merged feed surfaces it, but a metrics summary is NOT a crash-scoped
    // diagnostic — it must not appear in the MetricKit crash feed.
    let page = try await service.loadRecentLogs(
      limit: 20, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: false)
    let entry = try #require(page.entries.first)
    #expect(entry.source == "error_log")
    #expect(entry.origin == "metrickit.metrics")
    #expect(entry.isMetricKitDiagnostic == false)
    #expect(entry.metricKitDiagnosticKind == nil)
    #expect(entry.level == .info)
    #expect(entry.summary.hasPrefix("MetricKit metrics"))
    #expect(entry.details != nil)
  }

  @Test("the crash-scoped feed excludes non-MetricKit error_log rows")
  func onDiskCrashFeedExcludesNonCrashRows() async throws {
    let service = try makeService()
    // A real MetricKit crash and an unrelated sync failure both land in
    // `error_logs`; the Settings crash feed must show only the former.
    try await service.appendDiagnosticLog(
      source: "metrickit.crash", level: "error", message: "App crash: signal=11", details: nil)
    try await service.appendDiagnosticLog(
      source: "sync.pending_inbox", level: "error", message: "Inbox drain failed", details: nil)

    let page = try await service.loadRecentLogs(
      limit: 50, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: false)

    // The unscoped error_log stream carries both rows…
    #expect(page.entries.count == 2)
    #expect(Set(page.entries.compactMap(\.origin)) == ["metrickit.crash", "sync.pending_inbox"])

    // …but the MetricKit-scoped feed keeps only the crash.
    let scoped = page.entries.filter(\.isMetricKitDiagnostic)
    #expect(scoped.map(\.origin) == ["metrickit.crash"])

    let syncRow = try #require(page.entries.first { $0.origin == "sync.pending_inbox" })
    #expect(!syncRow.isMetricKitDiagnostic)
    #expect(syncRow.metricKitDiagnosticKind == nil)
  }
}
