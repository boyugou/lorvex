import Foundation
import LorvexCore
import SwiftUI
import Testing

@Suite("Event tint")
struct LorvexEventTintTests {
  @Test("an event wears its calendar's color")
  func calendarColorWins() {
    #expect(LorvexDesign.Palette.eventTint("#FF9500") == Color(lorvexHex: "#FF9500"))
  }

  @Test("an event whose calendar has no usable color is neutral gray, never the accent")
  func uncoloredEventIsNeutral() {
    for hex in [nil, "", "   ", "not a color", "#12"] as [String?] {
      #expect(LorvexDesign.Palette.eventTint(hex) == LorvexDesign.Palette.neutral, "\(hex ?? "nil")")
    }
    #expect(LorvexDesign.Palette.neutral != LorvexDesign.Palette.accent)
  }

  @Test("no surface resolves an event's color on its own")
  func everySurfaceUsesTheSharedTint() throws {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "Sources")
    let enumerator = try #require(
      FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var offenders: [String] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
      let text = try String(contentsOf: url, encoding: .utf8)
      if text.contains("lorvexHex: event.color") || text.contains("lorvexHex: block.event.color") {
        offenders.append(url.lastPathComponent)
      }
    }
    #expect(offenders.isEmpty, "\(offenders)")
  }
}
