import LorvexCore
import Testing

@testable import LorvexMobile

// The checklist composer clears its field the moment an item is submitted, so
// an add that did not happen has to give the item back: the store answers
// false for a failed write and for one refused because the task's previous
// write is still in flight, and the composer restores the item only into an
// empty field.

@Suite("Checklist composer keeps an item that was not added")
struct MobileChecklistComposerRestoreTests {
  @MainActor
  @Test("an add refused while the task's previous write is in flight answers false")
  func anAddRefusedByTheInFlightGuardAnswersFalse() async throws {
    let core = StubCoreService(preview: try await makeSeededInMemoryCore())
    let store = MobileStore(core: core, todayString: { "2026-05-23" })
    await store.refresh()
    let task = try #require(store.snapshot.today.tasks.first)
    let checklistCount = task.checklistItems.count

    // The first add parks in its Today reload while the task's mutation is
    // still open; the second arrives meanwhile and is refused without
    // presenting an error.
    let gate = TodayReadGate()
    core.loadTodayGate = { await gate.wait() }
    let first = Task { await store.addChecklistItem(taskID: task.id, text: "First item") }
    await gate.waitUntilEntered()

    let refused = await store.addChecklistItem(taskID: task.id, text: "Second item")
    #expect(!refused)
    #expect(store.errorMessage == nil)

    await gate.release()
    let firstAdded = await first.value
    #expect(firstAdded)
    let items = try #require(store.resolveTask(task.id)?.checklistItems)
    #expect(items.count == checklistCount + 1)
    #expect(items.contains { $0.text == "First item" })
    #expect(!items.contains { $0.text == "Second item" })
  }

  @Test("an item that was not added returns into an empty field")
  func aMissedAddRestoresTheItemIntoAnEmptyField() {
    #expect(
      MobileChecklistComposerRow.restoredText(item: "Passport", added: false, current: "")
        == "Passport")
  }

  @Test("an item that was not added never overwrites the next one being typed")
  func aMissedAddLeavesTheNextItemAlone() {
    #expect(
      MobileChecklistComposerRow.restoredText(item: "Passport", added: false, current: "Char")
        == nil)
  }

  @Test("an added item leaves the field as it is")
  func anAddedItemRestoresNothing() {
    #expect(MobileChecklistComposerRow.restoredText(item: "Passport", added: true, current: "") == nil)
    #expect(
      MobileChecklistComposerRow.restoredText(item: "Passport", added: true, current: "Char")
        == nil)
  }
}

/// Holds the first `loadToday` read inside the core until the test releases it.
private actor TodayReadGate {
  private var entered = false
  private var released = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    entered = true
    for waiter in enteredWaiters { waiter.resume() }
    enteredWaiters = []
    guard !released else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { enteredWaiters.append($0) }
  }

  func release() {
    released = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }
}
