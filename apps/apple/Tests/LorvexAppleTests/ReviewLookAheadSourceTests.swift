import Foundation
import Testing

private func sourceURL(_ path: String) -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: path)
}

private func source(_ path: String) throws -> String {
  try String(contentsOf: sourceURL(path), encoding: .utf8)
}

/// The text of the declaration that starts at `signature`, up to the blank line
/// that ends it. The declarations read here have no blank line inside.
private func declaration(_ signature: String, in text: String) throws -> String {
  let start = try #require(text.range(of: signature), "\(signature) is missing")
  let rest = text[start.lowerBound...]
  return String(rest[..<(rest.range(of: "\n\n")?.lowerBound ?? rest.endIndex)])
}

/// The English text a shipped catalog holds for `key`.
private func englishValue(of key: String, module: String) throws -> String {
  let data = try Data(contentsOf: sourceURL("Sources/\(module)/Resources/Localizable.xcstrings"))
  let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  let strings = try #require(catalog["strings"] as? [String: Any])
  let entry = try #require(strings[key] as? [String: Any], "\(key) is missing from \(module)")
  let localizations = try #require(entry["localizations"] as? [String: Any])
  let english = try #require(localizations["en"] as? [String: Any])
  let unit = try #require(english["stringUnit"] as? [String: Any])
  return try #require(unit["value"] as? String)
}

@Test("The look-ahead rows lead with a mark in a column as wide as the task lists' circle")
func lookAheadMarkColumnMatchesTheCompletionCircle() throws {
  let row = try source("Sources/LorvexCore/Support/LorvexReviewAheadRow.swift")
  let tasks = try source("Sources/LorvexCore/Support/LorvexReviewTaskList.swift")

  // The column is the circle's own symbol in the circle's own font, hidden and
  // given no height. Every title in the review then starts at one edge at any
  // text size, the mark takes the circle's center on the title's first line,
  // and the rows keep the height they have without the column.
  let column = try declaration("private var markColumn:", in: row)
  #expect(column.contains(#"Image(systemName: "circle")"#), "\(column)")
  #expect(column.contains(".font(LorvexDesign.Typography.primaryText)"), "\(column)")
  #expect(column.contains(".hidden()"), "\(column)")
  #expect(column.contains(".frame(height: 0)"), "\(column)")
  #expect(!row.contains("alignmentGuide"), "the mark follows the symbol, not a fixed offset")

  let circle = try declaration("private func circle(", in: tasks)
  #expect(circle.contains(".font(LorvexDesign.Typography.primaryText)"), "\(circle)")

  // The mark grows with the text, as the circle does.
  #expect(row.contains("@ScaledMetric(relativeTo: .body) private var markScale"))

  // Both look-ahead sections draw their rows with it.
  for section in ["LorvexReviewTomorrow", "LorvexReviewWeekAhead"] {
    let text = try source("Sources/LorvexCore/Support/\(section).swift")
    #expect(text.contains("LorvexReviewAheadRow("), "\(section)")
    #expect(!text.contains("func marker("), "\(section) draws its marks through the shared row")
  }
}

@Test("A look-ahead row keeps its time whole: beside the title it does not shrink, from xxLarge it stacks")
func lookAheadRowKeepsItsTimeWhole() throws {
  let row = try source("Sources/LorvexCore/Support/LorvexReviewAheadRow.swift")

  #expect(row.contains("dynamicTypeSize.stacksTimeColumn"))
  #expect(row.contains(".fixedSize(horizontal: !stacked, vertical: true)"))
  #expect(row.contains(".lineLimitUnlessAccessibilitySize(2)"), "titles wrap at the accessibility sizes")
}

@Test("The week-ahead heading is in sentence case, like the other review headings")
func weekAheadHeadingUsesSentenceCase() throws {
  let surfaces = [
    (module: "LorvexApple", copy: "Sources/LorvexApple/Views/ReviewCalmCopy.swift"),
    (module: "LorvexMobile", copy: "Sources/LorvexMobile/MobileReviewCalmCopy.swift"),
  ]
  for surface in surfaces {
    let copy = try source(surface.copy)
    #expect(copy.contains(#"defaultValue: "The week ahead""#), "\(surface.copy)")
    #expect(
      try englishValue(of: "review.calm.week_ahead", module: surface.module) == "The week ahead",
      "\(surface.module) catalog")
  }
}
