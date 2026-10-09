import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

/// The text just before the first occurrence of `marker`, which is where the
/// stack that holds the marker's view opens.
private func opening(before marker: String, in text: String) throws -> String {
  let range = try #require(text.range(of: marker), "\(marker) is missing")
  return String(text[..<range.lowerBound].suffix(120))
}

@Test("The Mac day review sets its sentence under the date by the gap the week review uses")
func dayReviewHeaderUsesTheWeekReviewHeaderGap() throws {
  let gap = "VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {"
  let day = try source("Sources/LorvexApple/Views/DailyReviewForm.swift")
  let week = try source("Sources/LorvexCore/Support/LorvexWeekReviewPage.swift")

  // Both pages sit in one workspace behind a Daily / Weekly switch. A different
  // gap under the date moves the sentence, and everything below it, whenever
  // the switch is used.
  let dayStack = try opening(
    before: "Text(TodayCalmCopy.dateLine(logicalDay: store.selectedReviewDate))", in: day)
  let weekStack = try opening(before: "Text(dateLine)", in: week)
  #expect(dayStack.contains(gap), "the day review's header stack: \(dayStack)")
  #expect(weekStack.contains(gap), "the week review's header stack: \(weekStack)")
}

@Test("The day review's return link keeps its distance from the sentence above it")
func dayReviewReturnLinkKeepsItsDistance() throws {
  let day = try source("Sources/LorvexApple/Views/DailyReviewForm.swift")

  // The header stack's gap is the small one, so the link adds the rest of the
  // space that separates it from the sentence.
  let link = try #require(day.range(of: ".buttonStyle(.link)"))
  #expect(day[link.upperBound...].prefix(80).contains(".padding(.top, LorvexDesign.Spacing.xs)"))
}
