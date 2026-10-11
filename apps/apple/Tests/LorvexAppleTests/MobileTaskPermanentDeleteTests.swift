import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// A task's detail on iPhone and iPad ends with a row that deletes the task for
// good, after a confirmation.

@MainActor
private func makeStore() async throws -> (store: MobileStore, core: any LorvexCoreServicing) {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  return (store, core)
}

@MainActor
@Test("A permanent delete removes the task from the core and from every list the store holds")
func mobilePermanentDeleteRemovesTheTaskEverywhere() async throws {
  let (store, core) = try await makeStore()
  let id = LorvexPreviewSeedID.agendaTask
  store.selectTask(id)
  #expect(store.resolveTask(id) != nil)
  #expect(store.snapshot.today.tasks.contains { $0.id == id })

  #expect(await store.permanentlyDeleteTask(id))

  await #expect(throws: LorvexCoreError.self) { _ = try await core.loadTask(id: id) }
  #expect(store.resolveTask(id) == nil)
  #expect(!store.snapshot.today.tasks.contains { $0.id == id })
  #expect(store.selectedTaskID == nil)
  #expect(store.undoOffer == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("Deleting one task leaves the others in place")
func mobilePermanentDeleteLeavesOtherTasks() async throws {
  let (store, core) = try await makeStore()
  let other = LorvexPreviewSeedID.venueTask

  #expect(await store.permanentlyDeleteTask(LorvexPreviewSeedID.agendaTask))

  #expect(try await core.loadTask(id: other).id == other)
  #expect(store.resolveTask(other) != nil)
}

@MainActor
@Test("A delete of a task that is not there fails and reports the error")
func mobilePermanentDeleteOfAnUnknownTaskFails() async throws {
  let (store, _) = try await makeStore()

  #expect(await store.permanentlyDeleteTask("no-such-task") == false)
  #expect(store.errorMessage != nil)
}

@Test("The detail ends with a destructive row that asks before deleting, and pops before the delete")
func mobileTaskDetailEndsWithAConfirmedDelete() throws {
  let sources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/LorvexMobile")
  let content = try String(
    contentsOf: sources.appending(path: "MobileTaskDetailContent.swift"), encoding: .utf8)
  let actionsEnd = try #require(content.range(of: "actions(task.isHeldUp(by: resolvedDependencies ?? []))"))
  let row = try #require(content.range(of: "if let deleteTask {"))
  #expect(actionsEnd.upperBound <= row.lowerBound)
  let rowText = content[row.lowerBound...]
  #expect(rowText.contains("Button(role: .destructive)"))
  // A list row recolors only a destructive button's title; the style paints the symbol red too.
  #expect(rowText.contains(".mobileDestructiveRowStyle()"))
  #expect(rowText.contains(".mobileDeleteConfirmation("))
  #expect(rowText.contains("confirmTitle: MobileTaskDeleteCopy.confirm"))
  #expect(rowText.contains("\"task.detail.delete\""))

  let detail = try String(
    contentsOf: sources.appending(path: "MobileStoreTaskDetailView.swift"), encoding: .utf8)
  let dismiss = try #require(detail.range(of: "deleteTask: {\n        dismiss()"))
  let delete = try #require(detail.range(of: "await store.permanentlyDeleteTask(task.id)"))
  #expect(dismiss.upperBound <= delete.lowerBound)
}
