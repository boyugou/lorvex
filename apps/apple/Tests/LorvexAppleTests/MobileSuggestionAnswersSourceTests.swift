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

@Test("The suggestion's two answers stack, each as wide as the row, when they do not fit side by side")
func suggestionAnswersStackWhenTheyDoNotFit() throws {
  let sheet = try source("Sources/LorvexMobile/MobileTodayScheduleSheet.swift")

  // Side by side in a narrow row, the capsules wrap "Use These Times" onto
  // three lines and become a blob. At the accessibility sizes and in the
  // longer languages the answers take a row each instead.
  let answers = try declaration("private var answers:", in: sheet)
  #expect(answers.contains("ViewThatFits(in: .horizontal)"), "\(answers)")
  #expect(answers.contains("useButton(fillsWidth: false)"), "\(answers)")
  #expect(answers.contains("dismissButton(fillsWidth: false)"), "\(answers)")
  #expect(answers.contains("useButton(fillsWidth: true)"), "\(answers)")
  #expect(answers.contains("dismissButton(fillsWidth: true)"), "\(answers)")

  // The width goes on the label: a frame outside a bordered button leaves its
  // capsule as wide as the words.
  let use = try declaration("private func useButton(", in: sheet)
  let dismiss = try declaration("private func dismissButton(", in: sheet)
  #expect(use.contains(".frame(maxWidth: fillsWidth ? .infinity : nil)"), "\(use)")
  #expect(dismiss.contains(".frame(maxWidth: fillsWidth ? .infinity : nil)"), "\(dismiss)")
}
