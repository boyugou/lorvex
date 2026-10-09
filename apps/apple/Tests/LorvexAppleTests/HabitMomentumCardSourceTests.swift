import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Test("The weekday letters under a habit card's rhythm strip stay legible")
func habitCardRhythmLettersAreAtLeastSecondary() throws {
  let card = try source("Sources/LorvexApple/Views/HabitMomentumCard.swift")
  let start = try #require(card.range(of: "private var rhythmRow: some View {"))
  let end = try #require(
    card.range(of: "private var rhythmDayLabels: [String] {", range: start.upperBound..<card.endIndex))
  let row = card[start.upperBound..<end.lowerBound]

  // The letters name the days the capsules stand for. The tertiary style
  // measures about 1.9:1 on a card's tint, where text reads as disabled; the
  // History heatmap's and By Weekday panel's letters beside it use the secondary
  // style (about 4.6:1), and today's letter takes the habit's color.
  #expect(row.contains("cell.isCurrent ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary)"))
  #expect(!row.contains("AnyShapeStyle(.tertiary)"))
  #expect(!row.contains(".foregroundStyle(.tertiary)"))
}
