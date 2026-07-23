import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexSystemIntents

@Test
func memoryEntityQuerySuggestsAllMemoryEntries() async throws {
  let core = try await makeSeededInMemoryCore()

  let suggested = try await LorvexMemoryEntityQuery.suggestedEntities(core: core)

  #expect(suggested.contains { $0.key == "swift_migration" })
  #expect(suggested.contains { $0.key == "notes_for_ai" })
}

@Test
func aiMemoryEntityQuerySuggestsAllMemoryEntries() async throws {
  let core = try await makeSeededInMemoryCore()

  let suggested = try await LorvexAIMemoryEntityQuery.suggestedEntities(core: core)

  #expect(suggested.contains { $0.key == "swift_migration" })
  #expect(suggested.contains { $0.key == "notes_for_ai" })
}

@Test
func memoryIntentsUseMemoryEntities() {
  let memory = LorvexMemoryEntity(id: "swift_migration", key: "swift_migration")
  let aiMemory = LorvexAIMemoryEntity(id: "swift_migration", key: "swift_migration")

  let read = ReadLorvexMemoryIntent(memory: memory)
  let delete = DeleteLorvexMemoryIntent(memory: aiMemory)

  #expect(read.memory.key == "swift_migration")
  #expect(delete.memory.key == "swift_migration")
  #expect(ReadLorvexMemoryIntent.openAppWhenRun == false)
  #expect(DeleteLorvexMemoryIntent.openAppWhenRun == false)
}
