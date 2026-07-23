import LorvexCore
@testable import LorvexMobile
import Testing

@Suite("Mobile catalog search filtering")
struct MobileCatalogSearchFilteringTests {
  @Test("list search matches name description and AI notes")
  func listSearchMatchesRelevantFields() {
    let lists = [
      LorvexList(
        id: "work",
        name: "Work",
        color: nil,
        icon: nil,
        description: "Launch planning",
        aiNotes: "Roadmap owner",
        openCount: 2,
        totalCount: 3,
        updatedAt: "2026-06-28"
      ),
      LorvexList(
        id: "home",
        name: "Home",
        color: nil,
        icon: nil,
        description: "Errands",
        openCount: 1,
        totalCount: 1,
        updatedAt: "2026-06-28"
      ),
    ]

    #expect(LorvexCatalogSearch.lists(lists, query: "roadmap").map(\.id) == ["work"])
    #expect(LorvexCatalogSearch.lists(lists, query: "launch work").map(\.id) == ["work"])
  }

  @Test("habit search matches name cue and cadence")
  func habitSearchMatchesRelevantFields() {
    let habits = [
      LorvexHabit(
        id: "run",
        name: "Morning Run",
        icon: "figure.run",
        color: nil,
        cue: "After coffee",
        frequencyType: "daily",
        targetCount: 1,
        completionsToday: 0,
        totalCompletions: 10,
        completionRate30d: 0.5,
        archived: false
      ),
      LorvexHabit(
        id: "read",
        name: "Read",
        icon: nil,
        color: nil,
        cue: "Before sleep",
        frequencyType: "weekly",
        targetCount: 1,
        completionsToday: 0,
        totalCompletions: 4,
        completionRate30d: 0.2,
        archived: false
      ),
    ]

    #expect(LorvexCatalogSearch.habits(habits, query: "coffee").map(\.id) == ["run"])
    #expect(LorvexCatalogSearch.habits(habits, query: "weekly").map(\.id) == ["read"])
  }

  @Test("memory search matches key and content")
  func memorySearchMatchesRelevantFields() {
    let entries = [
      MemoryEntry(
        key: "project_goal",
        content: "Ship mobile polish",
        updatedAt: "2026-06-28"
      ),
      MemoryEntry(
        key: "user_note",
        content: "Prefers compact summaries",
        updatedAt: "2026-06-28"
      ),
    ]

    #expect(LorvexCatalogSearch.memory(entries, query: "mobile").map(\.id) == ["project_goal"])
    #expect(LorvexCatalogSearch.memory(entries, query: "compact").map(\.id) == ["user_note"])
  }

  @Test("term-AND matches independent words in any order")
  func termAndSemantics() {
    // Every whitespace-separated term must appear in some field, order-free.
    #expect(LorvexCatalogSearch.matches("morning gym", fields: ["Gym in the morning", nil]))
    // A term absent from every field fails the whole match.
    #expect(!LorvexCatalogSearch.matches("morning gym", fields: ["Morning walk"]))
    // A blank query matches everything.
    #expect(LorvexCatalogSearch.matches("   ", fields: [nil]))
  }
}
