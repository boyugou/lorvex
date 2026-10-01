import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@Suite("Mobile composer sheets")
struct MobileComposerSheetTests {
  private func mobileSource(_ file: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(
      contentsOf: root.appending(path: "Sources/LorvexMobile/\(file)"), encoding: .utf8)
  }

  @Test("the Memory workspace drafts new entries in a sheet over the store's shared draft")
  func memoryComposerIsASheet() throws {
    let view = try mobileSource("MobileStoreMemoryView.swift")
    let composer = try mobileSource("MobileStoreMemoryComposerSheet.swift")

    // The list is the catalog only; drafting moved behind the toolbar ＋.
    #expect(view.contains("MobileStoreMemoryComposerSheet(store: store)"))
    #expect(view.contains("\"mobileMemory.new\""))
    #expect(!view.contains("$store.memoryKeyDraft"))
    #expect(!view.contains("$store.memoryContentDraft"))
    // The sheet edits the shared draft that inbound sync reloads preserve, saves
    // through the store, discards on Cancel, and cannot be swiped away mid-draft.
    #expect(composer.contains("$store.memoryKeyDraft"))
    #expect(composer.contains("$store.memoryContentDraft"))
    #expect(composer.contains("await store.saveMemoryDraft()"))
    #expect(composer.contains("store.clearMemoryDraft()"))
    #expect(composer.contains(".interactiveDismissDisabled(hasDraftText)"))
  }

  @MainActor
  @Test("saving from the composer clears the shared draft it edited")
  func composerSaveClearsSharedDraft() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    store.memoryKeyDraft = "composer_key"
    store.memoryContentDraft = "Drafted in the New Memory sheet."

    #expect(await store.saveMemoryDraft())
    #expect(store.memoryKeyDraft.isEmpty)
    #expect(store.memoryContentDraft.isEmpty)
    #expect(store.memory?.entries.contains { $0.key == "composer_key" } == true)
  }

  @Test("the capture sheet confirms from the navigation bar, not an in-form button")
  func captureConfirmLivesInTheBar() throws {
    let sheet = try mobileSource("MobileStoreCaptureSheet.swift")
    let sections = try mobileSource("MobileCaptureView.swift")

    #expect(sheet.contains("ToolbarItem(placement: .confirmationAction)"))
    #expect(sheet.contains("await store.submitCaptureDraft()"))
    #expect(sheet.contains("\"mobileCapture.confirm\""))
    #expect(!sections.contains(".borderedProminent"))
    #expect(!sections.contains("\"mobileCapture.confirm\""))
  }
}
