import Foundation
import Testing

private func macViewSource(_ name: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "Sources/LorvexApple/Views/\(name)")
  return try String(contentsOf: url, encoding: .utf8)
}

/// How many times `pattern` matches in `text`.
private func matchCount(_ pattern: String, in text: String) throws -> Int {
  try NSRegularExpression(pattern: pattern)
    .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
}

@Test(
  "A small icon button on a Mac row is clickable over its whole frame, not only over its glyph",
  arguments: [
    ("ListCatalogRow.swift", 2),
    ("MemoryEntryRow.swift", 2),
    ("HabitMomentumCard.swift", 2),
  ])
func smallIconButtonFramesCarryAContentShape(file: String, buttons: Int) throws {
  let text = try macViewSource(file)
  let framed = #"\.frame\(width: 1[68], height: 1[68]\)"#
  let shaped = framed + #"\s*\.contentShape\(Rectangle\(\)\)"#

  #expect(try matchCount(framed, in: text) == buttons)
  #expect(try matchCount(shaped, in: text) == buttons)
}

@Test("The Lists catalog card opens its list from its padding, not only from its text")
func listCatalogCardTapIncludesItsPadding() throws {
  let text = try macViewSource("ListCatalogRow.swift")

  let padding = try #require(text.range(of: ".padding(.vertical, ListCatalogRowMetrics.verticalPadding)"))
  let shape = try #require(text.range(of: ".contentShape(Rectangle())\n    .onTapGesture(perform: select)"))
  #expect(padding.lowerBound < shape.lowerBound)
}
