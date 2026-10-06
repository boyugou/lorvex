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

/// Lorvex's drop targets read the reference; every other app receiving the drag
/// reads the title as plain text.
@Test
func lorvexTaskRefExportsItsReferenceAndItsTitleAsText() async throws {
  let ref = LorvexTaskRef(id: "task-abc", title: "Buy: milk & eggs — today")

  let reference = try await ref.exported(as: .lorvexTask)
  #expect(try JSONDecoder().decode(LorvexTaskRef.self, from: reference) == ref)

  let text = try await ref.exported(as: .utf8PlainText)
  #expect(String(decoding: text, as: UTF8.self) == "Buy: milk & eggs — today")
}

@Test
func lorvexTaskUTTypeIdentifier() {
  #expect(UTType.lorvexTask.identifier == "com.lorvex.apple.task-ref")
}

// MARK: - A drag that carries several tasks

@Test
func lorvexTaskRefWithCompanionsRoundTripsAndListsEveryTask() throws {
  let ref = LorvexTaskRef(
    id: "a", title: "First",
    companions: [LorvexTaskRef(id: "b", title: "Second"), LorvexTaskRef(id: "c", title: "Third")])

  let decoded = try JSONDecoder().decode(LorvexTaskRef.self, from: JSONEncoder().encode(ref))

  #expect(decoded == ref)
  #expect(decoded.taskIDs == ["a", "b", "c"])
  #expect(decoded.titles == ["First", "Second", "Third"])
}

@Test
func lorvexTaskRefOfOneTaskListsOnlyThatTask() {
  let ref = LorvexTaskRef(id: "a", title: "Only")

  #expect(ref.taskIDs == ["a"])
  #expect(ref.titles == ["Only"])
}

/// A drop handler acts on every dropped task once, in drop order, even when two
/// references name the same task.
@Test
func droppedTaskIDsFlattensCompanionsAndDropsRepeats() {
  let refs = [
    LorvexTaskRef(id: "a", title: "A", companions: [LorvexTaskRef(id: "b", title: "B")]),
    LorvexTaskRef(id: "b", title: "B"),
    LorvexTaskRef(id: "c", title: "C"),
  ]

  #expect(refs.droppedTaskIDs == ["a", "b", "c"])
}

/// Another app receiving a multi-task drag gets one title per line.
@Test
func lorvexTaskRefWithCompanionsExportsOneTitlePerLine() async throws {
  let ref = LorvexTaskRef(
    id: "a", title: "Buy milk", companions: [LorvexTaskRef(id: "b", title: "Call Sam")])

  let text = try await ref.exported(as: .utf8PlainText)

  #expect(String(decoding: text, as: UTF8.self) == "Buy milk\nCall Sam")
}

// MARK: - AppStore drag-drop actions (integration with SwiftLorvexCoreService)

@MainActor
@Test
func appStoreMoveTaskClearsErrorOnSuccess() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.errorMessage = "stale"

  // The seeded preview store has LorvexPreviewSeedID.venueTask in "inbox"; move it to LorvexPreviewSeedID.appleNativeList.
  await store.moveTasks(
    ids: [LorvexPreviewSeedID.venueTask], toListID: LorvexPreviewSeedID.appleNativeList)

  #expect(store.errorMessage == nil)
}

