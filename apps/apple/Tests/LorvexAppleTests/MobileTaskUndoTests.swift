import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// Completing, cancelling, and filing a task on iPhone and iPad offer an Undo
// banner: one change is on offer at a time, and its button takes the change
// back.

@MainActor
private func makeStore() async throws -> (store: MobileStore, core: any LorvexCoreServicing) {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  return (store, core)
}

@MainActor
@Test("Completing a task offers Undo, which reopens it and takes the banner down")
func mobileCompletionOffersUndo() async throws {
  let (store, core) = try await makeStore()
  let id = LorvexPreviewSeedID.agendaTask
  #expect(store.undoOffer == nil)

  #expect(await store.completeTask(id))
  #expect(try await core.loadTask(id: id).status == .completed)
  #expect(store.undoOffer?.message == MobileUndoCopy.completed)

  await store.performUndoOffer()

  #expect(try await core.loadTask(id: id).status == .open)
  #expect(store.undoOffer == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("One Undo reopens every task a batch completed")
func mobileBatchCompletionIsUndoneByOneUndo() async throws {
  let (store, core) = try await makeStore()
  let ids = [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.venueTask]

  #expect(await store.completeTasks(ids))
  #expect(try await core.loadTask(id: ids[0]).status == .completed)
  #expect(store.undoOffer?.message == MobileUndoCopy.completed)

  await store.performUndoOffer()

  #expect(try await core.loadTask(id: ids[0]).status == .open)
  #expect(try await core.loadTask(id: ids[1]).status == .open)
}

@MainActor
@Test("Cancelling a task offers Undo, which reopens it")
func mobileCancellationOffersUndo() async throws {
  let (store, core) = try await makeStore()
  let id = LorvexPreviewSeedID.agendaTask

  #expect(await store.cancelTask(id))
  #expect(try await core.loadTask(id: id).status == .cancelled)
  #expect(store.undoOffer?.message == MobileUndoCopy.cancelled)

  await store.performUndoOffer()

  #expect(try await core.loadTask(id: id).status == .open)
}

@MainActor
@Test("Undoing the completion of a repeating task leaves one open occurrence")
func mobileUndoOfARepeatingCompletionLeavesOneOpenOccurrence() async throws {
  let (store, core) = try await makeStore()
  let id = LorvexPreviewSeedID.statusUpdateTask
  let title = try await core.loadTask(id: id).title
  func openOccurrences() async throws -> [LorvexTask.ID] {
    try await core.listTasks(
      status: "open", listID: nil, priority: nil, text: title, limit: 50, offset: 0
    ).tasks.filter { $0.title == title }.map(\.id)
  }

  #expect(await store.completeTask(id))
  #expect(try await openOccurrences().count == 1)
  #expect(try await openOccurrences() != [id])

  await store.performUndoOffer()

  #expect(try await openOccurrences() == [id])
}

@MainActor
@Test("Filing a task into another list offers Undo naming the list")
func mobileListMoveOffersUndo() async throws {
  let (store, core) = try await makeStore()
  let personal = try await core.createList(name: "Personal", description: nil)
  await store.refresh()
  let id = LorvexPreviewSeedID.agendaTask

  #expect(await store.moveTasks([id], toListID: personal.id))
  #expect(try await core.loadTask(id: id).listID == personal.id)
  #expect(store.undoOffer?.message == MobileUndoCopy.moved(count: 1, listName: "Personal"))

  await store.performUndoOffer()

  #expect(try await core.loadTask(id: id).listID == LorvexPreviewSeedID.appleNativeList)
  #expect(store.undoOffer == nil)
}

@MainActor
@Test("Undoing a move from two lists restores each task's own list")
func mobileUndoOfAMoveFromSeveralListsRestoresEachList() async throws {
  let (store, core) = try await makeStore()
  let personal = try await core.createList(name: "Personal", description: nil)
  await store.refresh()

  #expect(
    await store.moveTasks(
      [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.venueTask], toListID: personal.id))
  #expect(store.undoOffer?.message == MobileUndoCopy.moved(count: 2, listName: "Personal"))

  await store.performUndoOffer()

  #expect(
    try await core.loadTask(id: LorvexPreviewSeedID.agendaTask).listID
      == LorvexPreviewSeedID.appleNativeList)
  #expect(
    try await core.loadTask(id: LorvexPreviewSeedID.venueTask).listID
      == LorvexPreviewSeedID.inboxList)
}

@MainActor
@Test("A move that changes nothing offers no Undo")
func mobileMoveIntoTheTasksOwnListOffersNoUndo() async throws {
  let (store, _) = try await makeStore()

  _ = await store.moveTasks(
    [LorvexPreviewSeedID.agendaTask], toListID: LorvexPreviewSeedID.appleNativeList)

  #expect(store.undoOffer == nil)
}

@MainActor
@Test("A newer change replaces the offer, and Undo takes back only that change")
func mobileANewerChangeReplacesTheOffer() async throws {
  let (store, core) = try await makeStore()
  let first = LorvexPreviewSeedID.agendaTask
  let second = LorvexPreviewSeedID.venueTask

  #expect(await store.completeTask(first))
  let firstOffer = try #require(store.undoOffer)
  #expect(await store.cancelTask(second))
  let secondOffer = try #require(store.undoOffer)
  #expect(secondOffer.id != firstOffer.id)
  #expect(secondOffer.message == MobileUndoCopy.cancelled)

  await store.performUndoOffer()

  #expect(try await core.loadTask(id: second).status == .open)
  #expect(try await core.loadTask(id: first).status == .completed)
  #expect(store.undoOffer == nil)
}

@MainActor
@Test("Dismissing the banner undoes nothing, and Undo runs once")
func mobileDismissAndRepeatedUndo() async throws {
  let (store, core) = try await makeStore()
  let id = LorvexPreviewSeedID.agendaTask

  #expect(await store.completeTask(id))
  store.dismissUndoOffer()
  #expect(store.undoOffer == nil)
  #expect(try await core.loadTask(id: id).status == .completed)
  await store.performUndoOffer()
  #expect(try await core.loadTask(id: id).status == .completed)

  #expect(await store.cancelTask(LorvexPreviewSeedID.venueTask))
  await store.performUndoOffer()
  await store.performUndoOffer()
  #expect(try await core.loadTask(id: LorvexPreviewSeedID.venueTask).status == .open)
}

@MainActor
@Test("A change that does not commit offers no Undo")
func mobileFailedChangeOffersNoUndo() async throws {
  let (store, _) = try await makeStore()

  #expect(await store.completeTask("no-such-task") == false)
  #expect(store.undoOffer == nil)
}

@Test("The root view floats the Undo banner, wired to the store's offer")
func mobileRootViewFloatsTheUndoBanner() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let rootView = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/LorvexMobileStoreRootView.swift"),
    encoding: .utf8)
  #expect(rootView.contains(".lorvexMobileUndoBanner("))
  #expect(rootView.contains("store.undoOffer,"))
  #expect(rootView.contains("Task { await store.performUndoOffer() }"))
  #expect(rootView.contains("store.dismissUndoOffer()"))

  let banner = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileUndoBanner.swift"),
    encoding: .utf8)
  #expect(banner.contains("mobile.undo.banner"))
  #expect(banner.contains("mobile.undo.button"))
  #expect(banner.contains("AccessibilityNotification.Announcement(offer.message).post()"))
}
