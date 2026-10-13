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
}
