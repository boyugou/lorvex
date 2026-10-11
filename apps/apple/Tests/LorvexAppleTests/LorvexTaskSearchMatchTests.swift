import Foundation
import LorvexCore
import Testing

/// The one-line explanation a search result carries when its title does not
/// show the match: which field holds the term and the text around it.
@Suite("Task search match excerpt")
struct LorvexTaskSearchMatchTests {
  private func task(
    title: String, notes: String = "", aiNotes: String? = nil, tags: [String] = []
  ) -> LorvexTask {
    LorvexTask(
      id: "t", title: title, notes: notes, aiNotes: aiNotes, priority: .p2, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: tags)
  }

  @Test("a title that holds the term needs no excerpt")
  func titleMatchHasNoExcerpt() {
    let budget = task(title: "Review the budget", notes: "Budget numbers are in the sheet")
    #expect(budget.searchMatch(for: "budget") == nil)
  }

  @Test("an empty or blank query has no excerpt")
  func blankQueryHasNoExcerpt() {
    let budget = task(title: "Plan", notes: "Review the budget")
    #expect(budget.searchMatch(for: "") == nil)
    #expect(budget.searchMatch(for: "  \n ") == nil)
  }

  @Test("a short note is quoted whole around the matched word")
  func shortNoteIsQuotedWhole() throws {
    let planning = task(title: "Quarterly planning", notes: "Call Dana about the budget review")
    let match = try #require(planning.searchMatch(for: "budget"))
    #expect(match.field == .notes)
    #expect(match.before == "Call Dana about the ")
    #expect(match.matched == "budget")
    #expect(match.after == " review")
    #expect(match.text == "Call Dana about the budget review")
  }

  @Test("a long note is cut on word boundaries with an ellipsis at each cut end")
  func longNoteIsCut() throws {
    let notes =
      "Gather the figures from every department before the meeting, then compare the budget "
      + "against last quarter and send a summary to the finance team by Friday afternoon"
    let match = try #require(task(title: "Prep", notes: notes).searchMatch(for: "budget"))
    #expect(match.before == "…then compare the ")
    #expect(match.matched == "budget")
    #expect(match.after == " against last quarter and send a summary to…")
  }

  @Test("an unspaced script is cut by character count")
  func unspacedScriptIsCutByCharacter() throws {
    let notes =
      String(repeating: "整理资料。", count: 8) + "预算" + String(repeating: "确认细节。", count: 12)
    let match = try #require(task(title: "季度计划", notes: notes).searchMatch(for: "预算"))
    #expect(match.matched == "预算")
    #expect(match.before.count == 19)
    #expect(match.before.hasPrefix("…"))
    #expect(match.after.count == 45)
    #expect(match.after.hasSuffix("…"))
  }

  @Test("line breaks and repeated spaces collapse to single spaces")
  func whitespaceCollapses() throws {
    let notes = "First line\n\nSecond   line mentions the budget\nthird line"
    let match = try #require(task(title: "Prep", notes: notes).searchMatch(for: "budget"))
    #expect(match.text == "First line Second line mentions the budget third line")
  }

  @Test("accents and case do not stop a match, and the text keeps the task's spelling")
  func accentsAndCaseAreIgnored() throws {
    let meeting = task(title: "Llamar", notes: "Reunión con Ana el lunes")
    let match = try #require(meeting.searchMatch(for: "reunion"))
    #expect(match.matched == "Reunión")
  }

  @Test("a term only the folded comparison finds quotes the start of the field")
  func foldedOnlyMatchQuotesTheStart() throws {
    let trip = task(title: "Book train", notes: "Trip to Łódź next week")
    let match = try #require(trip.searchMatch(for: "lodz"))
    #expect(match.field == .notes)
    #expect(match.text == "Trip to Łódź next week")
  }

  @Test("the first term the title lacks decides the excerpt")
  func firstMissingTermDecides() throws {
    let planning = task(title: "Quarterly planning", notes: "Compare the budget with last year")
    let match = try #require(planning.searchMatch(for: "quarterly budget"))
    #expect(match.matched == "budget")
  }

  @Test("the notes are quoted before the assistant context")
  func notesComeBeforeAssistantContext() throws {
    let trip = task(
      title: "Plan trip", notes: "Prefers morning flights", aiNotes: "Flights under 300 dollars")
    #expect(try #require(trip.searchMatch(for: "flights")).field == .notes)
  }

  @Test("the assistant context is quoted when only it holds the term")
  func assistantContextIsQuoted() throws {
    let trip = task(title: "Plan trip", notes: "Check visas", aiNotes: "Prefers aisle seats")
    let match = try #require(trip.searchMatch(for: "aisle"))
    #expect(match.field == .assistantContext)
    #expect(match.text == "Prefers aisle seats")
  }

  @Test("a hidden tag is quoted by itself")
  func hiddenTagIsQuoted() throws {
    let errands = task(title: "Errands", tags: ["home", "shop", "weekend", "budget"])
    let match = try #require(errands.searchMatch(for: "budg", visibleTagCount: 3))
    #expect(match.field == .tags)
    #expect(match.before == "")
    #expect(match.matched == "budg")
    #expect(match.after == "et")
  }

  @Test("a tag the row shows explains its term without an excerpt")
  func visibleTagNeedsNoExcerpt() {
    let errands = task(title: "Errands", notes: "Pick up the budget folder", tags: ["budget"])
    #expect(errands.searchMatch(for: "budget", visibleTagCount: 3) == nil)
    #expect(errands.searchMatch(for: "budget", visibleTagCount: 0)?.field == .notes)
  }

  @Test("a term a visible tag explains is skipped for the next term")
  func visibleTagTermIsSkipped() throws {
    let trip = task(
      title: "Trip", aiNotes: "Prefers morning flights", tags: ["budget"])
    let match = try #require(trip.searchMatch(for: "budget flights", visibleTagCount: 3))
    #expect(match.field == .assistantContext)
    #expect(match.matched == "flights")
  }

  @Test("a task search finds always has an excerpt unless the title or a visible tag explains it")
  func everyHiddenMatchHasAnExcerpt() {
    let tasks = [
      task(title: "A", notes: "alpha beta"), task(title: "B", aiNotes: "alpha"),
      task(title: "C", tags: ["alpha"]), task(title: "alpha"),
    ]
    for item in tasks where item.matchesSearch("alpha") {
      let explained = item.title.localizedCaseInsensitiveContains("alpha")
      #expect((item.searchMatch(for: "alpha") == nil) == explained, "task \(item.title)")
    }
  }

  @Test("the Tasks tab home quotes a hidden match on its search results, as the task lists do")
  func tasksHomeSearchRowsQuoteTheirMatch() throws {
    let source = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/LorvexMobile/MobileStoreTasksHomeView.swift"),
      encoding: .utf8)
    let start = try #require(source.range(of: "private var searchResultsList"))
    let end = try #require(source.range(of: "// MARK: - Data"))
    let results = String(source[start.lowerBound..<end.lowerBound])
    #expect(results.contains("MobileActionTaskRow("))
    #expect(results.contains("searchQuery: trimmedQuery"))
    #expect(source.contains("private var hasQuery: Bool { !trimmedQuery.isEmpty }"))
  }

  @Test("the matched term is bold in the attributed excerpt and nothing else is")
  func attributedExcerptBoldsOnlyTheMatch() throws {
    let planning = task(title: "Quarterly planning", notes: "Call Dana about the budget review")
    let excerpt = try #require(planning.searchMatch(for: "budget")).attributedExcerpt
    let bold = excerpt.runs
      .filter { $0.inlinePresentationIntent == .stronglyEmphasized }
      .map { String(excerpt[$0.range].characters) }
    #expect(bold == ["budget"])
    #expect(String(excerpt.characters) == "Call Dana about the budget review")
  }

  @Test("the assistant context is quoted without its markdown marks")
  func assistantContextDropsMarkdownMarks() throws {
    let context =
      "**Context:** the investor asked for the `Q3` deck, see [the plan](https://example.com/plan)."
    let match = try #require(task(title: "Prep", aiNotes: context).searchMatch(for: "investor"))
    #expect(match.field == .assistantContext)
    #expect(match.matched == "investor")
    #expect(match.text == "Context: the investor asked for the Q3 deck, see the plan.")
  }

  @Test("heading, quote, list and checkbox markers do not lead the quoted line")
  func blockMarkersAreDropped() throws {
    let context = "## Plan\n- [ ] call the investor\n> noted\n1. send the deck\n   * [x] done"
    let match = try #require(task(title: "Prep", aiNotes: context).searchMatch(for: "investor"))
    #expect(match.text == "Plan call the investor noted send the deck done")
  }

  @Test("a term only a link address holds is quoted from the source as written")
  func termInsideALinkAddressKeepsTheSource() throws {
    let context = "see [the plan](https://example.com/budget)"
    let match = try #require(task(title: "Prep", aiNotes: context).searchMatch(for: "budget"))
    #expect(match.matched == "budget")
    #expect(match.text == context)
  }

  @Test("a note's own text is quoted as written, marks included")
  func notesKeepTheirMarks() throws {
    let notes = "**Context:** the investor asked"
    let match = try #require(task(title: "Prep", notes: notes).searchMatch(for: "investor"))
    #expect(match.text == notes)
  }

  @Test("assistant context nested or repeated tens of thousands of times is still quoted")
  func deeplyNestedAssistantContextIsQuoted() throws {
    let shapes = [
      String(repeating: "> ", count: 50_000) + "investor",
      String(repeating: "[", count: 50_000) + "investor",
      String(repeating: "_a ", count: 8_000) + "investor" + String(repeating: " a_", count: 8_000),
      "investor" + String(repeating: "*", count: 50_000),
      String(repeating: "[a](", count: 12_000) + "investor",
    ]
    for context in shapes {
      let match = try #require(task(title: "Prep", aiNotes: context).searchMatch(for: "investor"))
      #expect(match.matched == "investor")
    }
  }

  @Test("the Mac Tasks table quotes the match under a row's title like list mode")
  func tasksTableTitleCellQuotesTheMatch() throws {
    let source = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/LorvexApple/Views/TasksTableWorkspaceView.swift"),
      encoding: .utf8)
    #expect(source.contains("let searchQuery = store.trimmedSearchText"))
    #expect(
      source.contains(
        "task.searchMatch(for: searchQuery, visibleTagCount: LorvexTaskRow.visibleTagCount)"))
    #expect(source.contains("if let searchMatch { LorvexSearchExcerptLine(match: searchMatch) }"))
  }
}
