import Foundation
import LorvexMobile
import Testing

@testable import LorvexCore

// Swift reads a CR LF pair as one `Character`, which `== "\n"` does not match.
// These tests pin that every reader of a typed or pasted list treats LF, CR LF,
// and a lone CR as the same line break.

@Test
func listTextSplitsAtEveryKindOfLineBreak() {
  #expect(LorvexListText.entries(in: "a\nb\r\nc\rd") == ["a", "b", "c", "d"])
}

@Test
func listTextSplitsAtCommasAndTabsAndDropsBlanksAndRepeats() {
  #expect(LorvexListText.entries(in: " a ,b\t\tc,, a\r\n\r\n b ") == ["a", "b", "c"])
  #expect(LorvexListText.entries(in: "").isEmpty)
  #expect(LorvexListText.entries(in: " \r\n ,\t").isEmpty)
}

@Test
func mobileTaskEditDraftReadsTagsAndDependenciesSeparatedByWindowsLineBreaks() {
  let task = LorvexTask(
    id: "task-edit",
    title: "Edit task",
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: [],
    dependsOn: []
  )
  var draft = MobileTaskEditDraft(task: task)
  draft.tagsText = "mobile\r\nreview\r\nmobile"
  draft.dependsOnText = "dep-1\r\ndep-2"

  #expect(draft.parsedTags == ["mobile", "review"])
  #expect(draft.parsedDependencies == ["dep-1", "dep-2"])
}

@Test
func shortcutsTitleListSplitsAtEveryKindOfLineBreak() throws {
  let titles = try LorvexSystemIntentRunner.parsedTaskTitleList(
    "Buy milk\r\nCall mom\rWrite report\nPay rent, Book flights")

  #expect(titles == ["Buy milk", "Call mom", "Write report", "Pay rent", "Book flights"])
}

@Test
func shortcutsTextListSplitsAtEveryKindOfLineBreak() {
  #expect(LorvexSystemIntentRunner.parsedTextList("a\r\nb c,d\ne\rf") == ["a", "b", "c", "d", "e", "f"])
}
