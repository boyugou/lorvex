import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@Suite("Diagnostic fallback log")
struct DiagnosticFallbackLogTests {
  private func makeLog() -> (DiagnosticFallbackLog, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("diagnostic-fallback-\(UUID().uuidString)", isDirectory: true)
    return (
      DiagnosticFallbackLog(fileURL: directory.appendingPathComponent("log.json")), directory
    )
  }

  @Test func keepsTheNewestEntriesNewestFirst() {
    let (log, directory) = makeLog()
    defer { try? FileManager.default.removeItem(at: directory) }
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    for index in 0..<(DiagnosticFallbackLog.maximumEntries + 5) {
      log.append(
        source: "ios.ui.action_failed", message: "failure \(index)", details: nil,
        at: start.addingTimeInterval(TimeInterval(index)))
    }
    let entries = log.recentEntries()
    #expect(entries.count == DiagnosticFallbackLog.maximumEntries)
    #expect(entries.first?.summary == "failure \(DiagnosticFallbackLog.maximumEntries + 4)")
    #expect(entries.last?.summary == "failure 5")
    #expect(entries.allSatisfy { $0.level == .error && $0.origin == "ios.ui.action_failed" })
    #expect(Set(entries.map(\.id)).count == entries.count)
  }

  @Test func aDisabledLogRecordsNothing() {
    let log = DiagnosticFallbackLog(fileURL: nil)
    log.append(source: "s", message: "m", details: nil)
    #expect(log.recentEntries().isEmpty)
  }

  @Test func fallbackRowsMergeIntoTheStoredFeedByTime() {
    let stored = RecentLogEntry(
      id: "e1", timestamp: "2026-10-01T09:00:00.000Z", source: "error_log", level: .error,
      summary: "stored")
    let fallback = RecentLogEntry(
      id: "f1", timestamp: "2026-10-01T10:00:00.000Z", source: "error_log", level: .error,
      summary: "fallback")
    #expect(MobileStore.newestFirst([stored, fallback]).map(\.summary) == ["fallback", "stored"])
  }
}
