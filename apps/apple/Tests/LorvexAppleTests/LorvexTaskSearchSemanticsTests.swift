import LorvexCore
import Testing

/// Task search shares the term-AND semantics of catalog search
/// (`LorvexCatalogSearch.matches`), so a query behaves the same whether the user
/// is filtering tasks or lists/habits/memory. These tests document that unified
/// choice: multi-word queries match on independent terms in any order.
@Suite("Task search semantics")
struct LorvexTaskSearchSemanticsTests {
  private func task(title: String, notes: String = "", tags: [String] = []) -> LorvexTask {
    LorvexTask(
      id: "t",
      title: title,
      notes: notes,
      priority: .p2,
      status: .open,
      dueDate: nil,
      estimatedMinutes: nil,
      tags: tags
    )
  }

  @Test("multi-word query matches terms in any order (term-AND)")
  func termAndAnyOrder() {
    // The whole-query contiguous-substring behavior missed this; term-AND finds it.
    #expect(task(title: "Morning gym").matchesSearch("gym morning"))
    #expect(task(title: "Morning gym").matchesSearch("morning gym"))
  }

  @Test("every term must appear in some field")
  func everyTermRequired() {
    #expect(!task(title: "Morning walk").matchesSearch("gym morning"))
  }

  @Test("terms may match across different fields")
  func termsAcrossFields() {
    #expect(task(title: "Buy milk", tags: ["errand"]).matchesSearch("milk errand"))
  }

  @Test("single-word query is plain substring; empty query matches all")
  func singleWordAndEmpty() {
    #expect(task(title: "Weekly review").matchesSearch("review"))
    #expect(!task(title: "Weekly review").matchesSearch("monthly"))
    #expect(task(title: "Anything").matchesSearch("   "))
  }
}
