import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Test("The week shape strip's columns share the width they are given, so it fits a phone at large text")
func weekShapeStripColumnsShareTheirWidth() throws {
  let strip = try source("Sources/LorvexCore/Support/LorvexWeekShape.swift")

  // Seven columns of a fixed, text-scaled width are wider than a phone from
  // the accessibility sizes up. The page then grows past the screen and its
  // headline and day letters are cut off at both edges.
  #expect(strip.contains(".frame(minWidth: 0, maxWidth: columnWidth)"))
  #expect(!strip.contains(".frame(width: columnWidth)"))
}
