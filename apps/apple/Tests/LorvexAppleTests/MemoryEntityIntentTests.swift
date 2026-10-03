import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexSystemIntents

@Test
func memoryEntityQuerySuggestsAllMemoryEntries() async throws {
  let core = try await makeSeededInMemoryCore()

  let suggested = try await LorvexMemoryEntityQuery.suggestedEntities(core: core)

  #expect(suggested.contains { $0.key == "new_laptop" })
  #expect(suggested.contains { $0.key == "notes_for_ai" })
}

@Test
func aiMemoryEntityQuerySuggestsAllMemoryEntries() async throws {
  let core = try await makeSeededInMemoryCore()

  let suggested = try await LorvexAIMemoryEntityQuery.suggestedEntities(core: core)

  #expect(suggested.contains { $0.key == "new_laptop" })
  #expect(suggested.contains { $0.key == "notes_for_ai" })
}

@Test
func memoryIntentsUseMemoryEntities() {
  let memory = LorvexMemoryEntity(id: "new_laptop", key: "new_laptop")
  let aiMemory = LorvexAIMemoryEntity(id: "new_laptop", key: "new_laptop")

  let read = ReadLorvexMemoryIntent(memory: memory)
  let delete = DeleteLorvexMemoryIntent(memory: aiMemory)

  #expect(read.memory.key == "new_laptop")
  #expect(delete.memory.key == "new_laptop")
  #expect(ReadLorvexMemoryIntent.openAppWhenRun == false)
  #expect(DeleteLorvexMemoryIntent.openAppWhenRun == false)
}
