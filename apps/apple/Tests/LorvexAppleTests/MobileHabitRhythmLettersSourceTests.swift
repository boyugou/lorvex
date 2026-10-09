import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Test("The weekday letters under the iPhone habit's rhythm strip stay legible")
func mobileHabitRhythmLettersAreAtLeastSecondary() throws {
  let section = try source("Sources/LorvexMobile/MobileHabitVisualizationSection.swift")
  let start = try #require(section.range(of: "private struct MobileHabitRhythmPanel: View {"))
  let end = try #require(
    section.range(of: "private var rhythmAccessibilityLabel: String {", range: start.upperBound..<section.endIndex))
  let panel = section[start.upperBound..<end.lowerBound]

  // The letters name the days the capsules stand for. The tertiary style
  // measures about 1.9:1 on a card, where text reads as disabled; the Mac
  // habit card's letters and the History heatmap's use the secondary style, and
  // today's letter takes the habit's color.
  #expect(panel.contains("cell.isCurrent ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary)"))
  #expect(!panel.contains("AnyShapeStyle(.tertiary)"))
  #expect(!panel.contains(".foregroundStyle(.tertiary)"))
}
