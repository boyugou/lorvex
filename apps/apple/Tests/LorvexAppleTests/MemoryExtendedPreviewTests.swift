import Foundation
import LorvexCore
import Testing

// MARK: - Delete Memory

@Test
func previewDeleteMemoryRemovesEntry() async throws {
  let service = try await makeSeededInMemoryCore()
  _ = try await service.upsertMemory(key: "to_delete", content: "temporary")
  _ = try await service.deleteMemory(key: "to_delete")
  let memory = try await service.loadMemory()
  #expect(memory.entries.first { $0.key == "to_delete" } == nil)
}
