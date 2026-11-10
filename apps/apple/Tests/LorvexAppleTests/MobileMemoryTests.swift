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
  let entry = try #require(store.memory?.entries.first { $0.key == "new_laptop" })

  store.beginEditingMemory(entry)
  store.memoryKeyDraft = "new_laptop_mobile"
  store.memoryContentDraft = "Renamed mobile memory."
  let saved = await store.saveMemoryDraft()
  let entries = try await core.loadMemory().entries

  #expect(saved)
  #expect(entries.contains { $0.key == "new_laptop_mobile" })
  #expect(!entries.contains { $0.key == "new_laptop" })
  #expect(store.selectedMemoryKey == "new_laptop_mobile")
  #expect(store.memoryEditingKey == nil)
  #expect(store.memoryKeyDraft == "")
  #expect(store.memoryContentDraft == "")
}

// #15: the modal editor sheet's dedicated save path must not touch the shared
// inline-composer draft, so opening the editor for an existing entry never
// clobbers the unsaved "new memory" text the user was typing inline.
@MainActor
@Test
func mobileStoreEditorSaveLeavesInlineNewMemoryDraftUntouched() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)
  await store.loadMemorySnapshot()
  let existing = try #require(store.memory?.entries.first { $0.key == "new_laptop" })

  // The user is mid-way through typing a NEW entry in the inline composer.
  store.memoryKeyDraft = "trip-ideas"
  store.memoryContentDraft = "book flights"

  let saved = await store.saveMemoryEntryEdit(
    originalKey: existing.key, newKey: "new_laptop_renamed", content: "Edited via sheet.")
  #expect(saved)

  // The inline new-entry draft survives untouched.
  #expect(store.memoryKeyDraft == "trip-ideas")
  #expect(store.memoryContentDraft == "book flights")

  // The edit (a rename) persisted and became the selection.
  let entries = try await core.loadMemory().entries
  #expect(entries.contains { $0.key == "new_laptop_renamed" && $0.content == "Edited via sheet." })
  #expect(!entries.contains { $0.key == "new_laptop" })
  #expect(store.selectedMemoryKey == "new_laptop_renamed")
}

@MainActor
@Test
func mobileStoreDeletesMemory() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)

  await store.loadMemorySnapshot()
  let entry = try #require(store.memory?.entries.first { $0.key == "new_laptop" })

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
  let first = try #require(store.memory?.entries.first { $0.key == "new_laptop" })
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

@MainActor
@Test
func mobileStoreRefusesANewMemoryUnderATakenKey() async throws {
  let core = try await makeSeededInMemoryCore()
  _ = try await core.upsertMemory(key: "travel_notes", content: "Prefers aisle seats.")
  let store = MobileStore(core: core)
  await store.refresh()
  store.memoryKeyDraft = "travel_notes"
  store.memoryContentDraft = "Window seat please."

  #expect(await store.saveMemoryDraft() == false)
  #expect(store.errorMessage != nil)
  #expect(store.memoryContentDraft == "Window seat please.")
  let stored = try await core.loadMemory().entries.first { $0.key == "travel_notes" }
  #expect(stored?.content == "Prefers aisle seats.")
}

/// Creating refuses a key another memory holds, in the same transaction as the
/// write; upserting replaces on purpose.
@Test
func coreCreateMemoryRefusesATakenKey() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createMemory(key: " packing_list ", content: "Charger.")
  #expect(created.key == "packing_list")

  do {
    _ = try await core.createMemory(key: "packing_list", content: "Passport.")
    Issue.record("a second create under the same key was accepted")
  } catch LorvexCoreError.conflict(_, let entity) {
    #expect(entity == .memory)
  }
  #expect(
    UserFacingError.Reason(
      LorvexCoreError.conflict(message: "", entity: .memory)) == .memoryNameTaken)

  _ = try await core.upsertMemory(key: "packing_list", content: "Passport.")
  let stored = try await core.loadMemory().entries.first { $0.key == "packing_list" }
  #expect(stored?.content == "Passport.")
}
