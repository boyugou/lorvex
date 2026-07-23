import LorvexCore
import LorvexMobile
import Testing

@MainActor
@Test
func mobileStoreLoadsAndWritesMemoryThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)

  await store.loadMemorySnapshot()

  #expect(store.memory?.entries.isEmpty == false)
  #expect(store.errorMessage == nil)
  #expect(store.canSaveMemoryDraft == false)

  store.memoryKeyDraft = "mobile_context"
  store.memoryContentDraft = "Mobile review owns quick memory edits."
  #expect(store.canSaveMemoryDraft == true)

  let saved = await store.saveMemoryDraft()
  let entry = try #require(store.memory?.entries.first { $0.key == "mobile_context" })
  let reloaded = try await core.loadMemory()

  #expect(saved)
  #expect(entry.content == "Mobile review owns quick memory edits.")
  #expect(reloaded.entries.contains { $0.key == "mobile_context" })
  #expect(store.memoryKeyDraft == "")
  #expect(store.memoryContentDraft == "")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreRenamesEditedMemoryInsteadOfDuplicatingKey() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)

  await store.loadMemorySnapshot()
  let entry = try #require(store.memory?.entries.first { $0.key == "swift_migration" })

  store.beginEditingMemory(entry)
  store.memoryKeyDraft = "swift_migration_mobile"
  store.memoryContentDraft = "Renamed mobile memory."
  let saved = await store.saveMemoryDraft()
  let entries = try await core.loadMemory().entries

  #expect(saved)
  #expect(entries.contains { $0.key == "swift_migration_mobile" })
  #expect(!entries.contains { $0.key == "swift_migration" })
  #expect(store.selectedMemoryKey == "swift_migration_mobile")
  #expect(store.memoryEditingKey == nil)
  #expect(store.memoryKeyDraft == "")
  #expect(store.memoryContentDraft == "")
}

@MainActor
@Test
func mobileStoreDeletesMemory() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)

  await store.loadMemorySnapshot()
  let entry = try #require(store.memory?.entries.first { $0.key == "swift_migration" })

  let deleted = await store.deleteMemoryEntry(entry)
  #expect(deleted)
  #expect(store.memory?.entries.contains { $0.key == entry.key } == false)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreBatchDeletesMemory() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)

  await store.loadMemorySnapshot()
  let first = try #require(store.memory?.entries.first { $0.key == "swift_migration" })
  let second = try #require(store.memory?.entries.first { $0.key == "notes_for_ai" })

  store.selectMemoryEntry(first.id)
  let deleted = await store.deleteMemoryEntries([first, second])

  #expect(deleted)
  #expect(store.memory?.entries.contains { $0.key == first.key } == false)
  #expect(store.memory?.entries.contains { $0.key == second.key } == false)
  #expect(store.selectedMemoryKey == nil)
  #expect(store.errorMessage == nil)
  #expect(store.isSavingMemory == false)
}

@MainActor
@Test
func mobileStoreRejectsBlankMemoryDraft() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)
  let before = try await core.loadMemory().entries

  store.memoryKeyDraft = "   "
  store.memoryContentDraft = "Context"
  let saved = await store.saveMemoryDraft()
  let after = try await core.loadMemory().entries

  #expect(saved == false)
  #expect(store.canSaveMemoryDraft == false)
  #expect(after == before)
}
