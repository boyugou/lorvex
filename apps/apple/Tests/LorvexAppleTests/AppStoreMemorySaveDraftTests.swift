import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// Saving a memory entry resets the composer only when it still holds what was
/// saved: text typed, or an entry opened, while the save was in flight stays.
@MainActor
@Suite("Memory composer after a save")
struct AppStoreMemorySaveDraftTests {
  @Test("The composer is reset after a save nobody typed over")
  func resetsWhenUntouched() async throws {
    let store = AppStore(core: StubCoreService(preview: try await makeSeededInMemoryCore()))
    await store.refresh()
    store.memoryKeyDraft = "travel_notes"
    store.memoryContentDraft = "Prefers aisle seats."

    let saved = await store.saveMemoryDraft()

    #expect(saved)
    #expect(store.memoryKeyDraft.isEmpty && store.memoryContentDraft.isEmpty)
  }

  @Test("Text typed while the save is in flight survives it")
  func keepsTextTypedDuringTheSave() async throws {
    let core = StubCoreService(preview: try await makeSeededInMemoryCore())
    let store = AppStore(core: core)
    await store.refresh()
    store.memoryKeyDraft = "travel_notes"
    store.memoryContentDraft = "Prefers aisle seats."
    core.loadMemoryGate = {
      await MainActor.run {
        store.memoryKeyDraft = "next_entry"
        store.memoryContentDraft = "Started typing the next one."
      }
    }

    let saved = await store.saveMemoryDraft()

    #expect(saved)
    #expect(store.memoryKeyDraft == "next_entry")
    #expect(store.memoryContentDraft == "Started typing the next one.")
  }

  @Test("A new entry under a key another entry holds is refused, and both texts are kept")
  func newEntryUnderATakenKeyIsRefused() async throws {
    let preview = try await makeSeededInMemoryCore()
    _ = try await preview.upsertMemory(key: "travel_notes", content: "Prefers aisle seats.")
    let store = AppStore(core: StubCoreService(preview: preview))
    await store.refresh()
    store.memoryKeyDraft = " travel_notes "
    store.memoryContentDraft = "Window seat please."

    let saved = await store.saveMemoryDraft()

    #expect(!saved)
    #expect(store.errorMessage != nil)
    #expect(store.memoryContentDraft == "Window seat please.")
    let stored = try await preview.loadMemory().entries.first { $0.key == "travel_notes" }
    #expect(stored?.content == "Prefers aisle seats.")
  }

  @Test("Saving an entry opened for editing under its own key still replaces its text")
  func editingAnEntryUnderItsOwnKeySaves() async throws {
    let preview = try await makeSeededInMemoryCore()
    let entry = try await preview.upsertMemory(key: "travel_notes", content: "Prefers aisle seats.")
    let store = AppStore(core: StubCoreService(preview: preview))
    await store.refresh()
    store.beginEditingMemory(entry)
    store.memoryContentDraft = "Prefers window seats."

    #expect(await store.saveMemoryDraft())
    let stored = try await preview.loadMemory().entries.first { $0.key == "travel_notes" }
    #expect(stored?.content == "Prefers window seats.")
  }
}
