import LorvexCore
import Testing

/// ``MemoryEntry/displayTitle``: the name a surface shows for an entry whose
/// key is the assistant's handle.
@Test("a snake_case key reads as a sentence-case phrase")
func memoryTitleReadsSnakeCaseAsWords() {
  #expect(MemoryEntry.displayTitle(forKey: "user_profile") == "User profile")
  #expect(MemoryEntry.displayTitle(forKey: "pending_followups") == "Pending followups")
  #expect(MemoryEntry.displayTitle(forKey: "swift-migration") == "Swift migration")
  #expect(MemoryEntry.displayTitle(forKey: "__odd__key__") == "Odd key")
}

@Test("initialisms and platform names keep their spelling")
func memoryTitleSpellsInitialisms() {
  #expect(MemoryEntry.displayTitle(forKey: "notes_for_ai") == "Notes for AI")
  #expect(MemoryEntry.displayTitle(forKey: "ios_shortcuts") == "iOS shortcuts")
  #expect(MemoryEntry.displayTitle(forKey: "mcp_setup") == "MCP setup")
}

@Test("a phrase the person typed reads as typed, and capitals of its own stay")
func memoryTitleLeavesTypedPhrasesAlone() {
  #expect(MemoryEntry.displayTitle(forKey: "coffee order") == "Coffee order")
  #expect(MemoryEntry.displayTitle(forKey: "Coffee order") == "Coffee order")
  #expect(MemoryEntry.displayTitle(forKey: "SwiftUI_notes") == "SwiftUI notes")
  #expect(MemoryEntry.displayTitle(forKey: "") == "")
  #expect(MemoryEntry.displayTitle(forKey: "___") == "___")
  let entry = MemoryEntry(key: "behavioral_patterns", content: "", updatedAt: "")
  #expect(entry.displayTitle == "Behavioral patterns")
}
