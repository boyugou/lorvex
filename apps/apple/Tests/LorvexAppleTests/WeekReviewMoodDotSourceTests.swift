import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

/// The text of the declaration that starts at `signature`, up to the blank line
/// that ends it. The declarations read here have no blank line inside.
private func declaration(_ signature: String, in text: String) throws -> String {
  let start = try #require(text.range(of: signature), "\(signature) is missing")
  let rest = text[start.lowerBound...]
  return String(rest[..<(rest.range(of: "\n\n")?.lowerBound ?? rest.endIndex)])
}

@Test("The week review's mood dot scales with the day label so it stays level with it")
func moodDotScalesWithTheDayLabel() throws {
  let page = try source("Sources/LorvexCore/Support/LorvexWeekReviewPage.swift")

  // The label is a text style that grows with the text size. A dot of fixed
  // size, set a fixed distance below the label's center, sinks below the
  // lowercase letters and shrinks next to them at the accessibility sizes.
  #expect(page.contains("@ScaledMetric(relativeTo: .subheadline) private var moodDotScale"))
  let dot = try declaration("private func moodDot(", in: page)
  #expect(dot.contains("let scale = moodDotScale"), "\(dot)")
  #expect(dot.contains("* scale"), "\(dot)")
  #expect(dot.contains("16 * scale"), "\(dot)")
  #expect(dot.contains("$0[VerticalAlignment.center] + 4 * scale"), "\(dot)")
}
