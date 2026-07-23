import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func sharedSystemIntentRunnerMutatesListsAndBatchTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let list = try await LorvexSystemIntentRunner.createList(
    name: "  Shared system list  ", description: "  Shared list description  ", core: core)
  #expect(list.name == "Shared system list")
  #expect(list.description == "Shared list description")
  let updatedList = try await LorvexSystemIntentRunner.updateList(
    id: " \(list.id) ", name: "  Renamed system list  ",
    description: "  Updated through shared runner  ", core: core)
  #expect(updatedList.id == list.id)
  #expect(updatedList.name == "Renamed system list")
  #expect(updatedList.description == "Updated through shared runner")
  let deletedListID = try await LorvexSystemIntentRunner.deleteList(id: " \(list.id) ", core: core)
  #expect(deletedListID == list.id)
  #expect(!((try await core.loadLists()).lists.contains { $0.id == list.id }))

  let batchList = try await LorvexSystemIntentRunner.createList(
    name: "  Shared system batch list  ", description: nil, core: core)
  let createdBatch = try await LorvexSystemIntentRunner.batchCreateTasks(
    titlesText: "Shared system batch one, Shared system batch two",
    notes: nil,
    listID: batchList.id,
    priority: 3,
    core: core
  )
  let batchOne = try #require(createdBatch.first { $0.title == "Shared system batch one" })
  let batchTwo = try #require(createdBatch.first { $0.title == "Shared system batch two" })
  #expect(batchTwo.priority == .p3)
  let batchIDs = [batchOne.id, batchTwo.id]
  let missingID = "missing-\(UUID().uuidString)"
  var result = try await LorvexSystemIntentRunner.batchCompleteTasks(
    taskIDs: batchIDs + [missingID], core: core)
  #expect(result.changedIDs.sorted() == batchIDs.sorted())
  #expect(result.skipped == [missingID])
  // Completed tasks leave the open-only Today snapshot; the row is the evidence.
  #expect(!result.snapshot.tasks.contains { $0.id == batchOne.id })
  #expect(try await core.loadTask(id: batchOne.id).status == .completed)
  result = try await LorvexSystemIntentRunner.batchReopenTasks(taskIDs: batchIDs, core: core)
  #expect(result.changedIDs.sorted() == batchIDs.sorted())
  #expect(result.skipped.isEmpty)
  #expect(result.snapshot.tasks.first { $0.id == batchTwo.id }?.status == .open)
  result = try await LorvexSystemIntentRunner.batchDeferTasks(
    taskIDs: batchIDs, until: " 2026-05-31 ", core: core)
  #expect(result.changedIDs.sorted() == batchIDs.sorted())
  #expect(result.skipped.isEmpty)
  #expect(result.snapshot.tasks.first { $0.id == batchOne.id }?.status == .open)
  // A move to the list the tasks already occupy is a skip, not a success, so
  // the batch move targets a fresh destination list.
  let moveDestination = try await LorvexSystemIntentRunner.createList(
    name: "Shared batch destination", description: nil, core: core)
  let movedBatch = try await LorvexSystemIntentRunner.batchMoveTasks(
    taskIDs: batchIDs, listID: " \(moveDestination.id) ", core: core)
  #expect(movedBatch.map(\.id).sorted() == [batchOne.id, batchTwo.id].sorted())
}
