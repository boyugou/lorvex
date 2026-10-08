import Foundation
import Testing

@testable import LorvexMarkdownUI

/// `MarkdownSourceView` hands SwiftUI an equatable inner view, so a redraw of
/// its parent with the same source and labels skips the parse. These tests pin
/// the comparison.

@Test
func markdownSourceContentIsEqualWhenSourceAndLabelsMatch() {
  let first = MarkdownSourceView.Content(source: "- [ ] Ship it", taskItemAccessibility: .init())
  let second = MarkdownSourceView.Content(source: "- [ ] Ship it", taskItemAccessibility: .init())

  #expect(first == second)
}

@Test
func markdownSourceContentDiffersWhenTheSourceChanges() {
  let first = MarkdownSourceView.Content(source: "- [ ] Ship it", taskItemAccessibility: .init())
  let second = MarkdownSourceView.Content(source: "- [x] Ship it", taskItemAccessibility: .init())

  #expect(first != second)
}

@Test
func markdownSourceContentDiffersWhenTheTaskItemLabelsChange() {
  let first = MarkdownSourceView.Content(source: "- [ ] Ship it", taskItemAccessibility: .init())
  let second = MarkdownSourceView.Content(
    source: "- [ ] Ship it",
    taskItemAccessibility: .init(completedFormat: "Fait : %@", todoFormat: "À faire : %@"))

  #expect(first != second)
}
