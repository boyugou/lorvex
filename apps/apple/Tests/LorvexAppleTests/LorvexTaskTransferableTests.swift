import CoreTransferable
import Foundation
import LorvexCore
import Testing
import UniformTypeIdentifiers

@testable import LorvexApple

// MARK: - LorvexTaskRef Transferable round-trip

@Test
func lorvexTaskRefRoundTrip() throws {
  let ref = LorvexTaskRef(id: "task-abc", title: "Write tests")

  let encoded = try JSONEncoder().encode(ref)
  let decoded = try JSONDecoder().decode(LorvexTaskRef.self, from: encoded)

  #expect(decoded.id == "task-abc")
  #expect(decoded.title == "Write tests")
}

@Test
func lorvexTaskRefPreservesSpecialCharacters() throws {
  let ref = LorvexTaskRef(id: "id/with/slashes", title: "Buy: milk & eggs — today")

  let encoded = try JSONEncoder().encode(ref)
  let decoded = try JSONDecoder().decode(LorvexTaskRef.self, from: encoded)

  #expect(decoded.id == ref.id)
  #expect(decoded.title == ref.title)
}

@Test
func lorvexTaskRefHashableEquality() {
  let a = LorvexTaskRef(id: "x", title: "A")
  let b = LorvexTaskRef(id: "x", title: "A")
  let c = LorvexTaskRef(id: "y", title: "A")

  #expect(a == b)
  #expect(a != c)
  #expect(Set([a, b]).count == 1)
}

@Test
func lorvexTaskUTTypeIdentifier() {
  #expect(UTType.lorvexTask.identifier == "com.lorvex.apple.task-ref")
}

// MARK: - AppStore drag-drop actions (integration with SwiftLorvexCoreService)

@MainActor
@Test
func appStoreMoveTaskClearsErrorOnSuccess() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.errorMessage = "stale"

  // The seeded preview store has LorvexPreviewSeedID.venueTask in "inbox"; move it to LorvexPreviewSeedID.appleNativeList.
  await store.moveTask(id: LorvexPreviewSeedID.venueTask, toListID: LorvexPreviewSeedID.appleNativeList)

  #expect(store.errorMessage == nil)
}

