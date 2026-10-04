import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore

/// A row that replaces its combined accessibility label with a short phrase
/// must still speak the facts it draws outside that phrase: the diagnostics
/// row's time and the memory row's last-updated day.
@Suite("Mac row accessibility values")
@MainActor
struct MacRowAccessibilityTests {
  private static let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  @Test("a diagnostics row speaks when the entry happened, with its date")
  func runtimeEntryRowSpeaksItsTimestamp() {
    let timestamp = "2026-10-04T15:41:07.000Z"
    let row = RuntimeEntryRow(
      title: "Cloud sync failed", subtitle: "ios.cloud_sync.cycle · error", timestamp: timestamp)
    #expect(row.spokenTimestamp.contains("2026"))
    #expect(row.spokenTimestamp != timestamp)
  }

  @Test("a timestamp that is missing or unparsable speaks the text the row shows in its place")
  func runtimeEntryRowFallsBackToTheTextItShows() {
    let unparsable = RuntimeEntryRow(title: "Edit", subtitle: "task · update", timestamp: "yesterday")
    #expect(unparsable.spokenTimestamp == "yesterday")

    let attributed = RuntimeEntryRow(
      title: "Edit", subtitle: "task · update", timestamp: nil, fallbackDetail: "assistant")
    #expect(attributed.spokenTimestamp == "assistant")

    let bare = RuntimeEntryRow(title: "Edit", subtitle: "task · update", timestamp: nil)
    #expect(bare.spokenTimestamp.isEmpty)
  }

  @Test("a memory row speaks the day it was last updated")
  func memoryRowSpeaksItsUpdatedDay() {
    let entry = MemoryEntry(
      key: "project_goal", content: "Ship v1 by Q3", updatedAt: "2026-05-22T09:00:00.000Z")
    let row = MemoryEntryRow(entry: entry, edit: {}, delete: {})
    #expect(row.spokenUpdatedDay.contains("2026"))
  }

  @Test("both rows attach those facts as their accessibility value")
  func rowsAttachTheirFactsAsTheValue() throws {
    let pins = [
      ("Sources/LorvexApple/Views/SettingsActivitySections.swift", ".accessibilityValue(spokenTimestamp)"),
      ("Sources/LorvexApple/Views/MemoryEntryRow.swift", ".accessibilityValue(spokenUpdatedDay)"),
    ]
    for (path, modifier) in pins {
      let source = try String(
        contentsOf: Self.packageRoot.appending(path: path), encoding: .utf8)
      #expect(source.contains(modifier), "\(path)")
    }
  }
}
