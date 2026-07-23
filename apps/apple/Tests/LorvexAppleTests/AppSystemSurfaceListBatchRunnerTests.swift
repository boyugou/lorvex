import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func taskIntentRunnerHandlesListBatchAndTagActions() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(title: "Shortcut tagged task", notes: "")
  let list = try await LorvexTaskIntentRunner.createList(
    name: "  Shortcut list  ",
    description: "  Created from Shortcuts  ",
    core: core
  )
  #expect(list.name == "Shortcut list")
  #expect(list.description == "Created from Shortcuts")

  let updatedList = try await LorvexTaskIntentRunner.updateList(
    id: " \(list.id) ",
    name: "  Renamed shortcut list  ",
    description: "  Updated from Shortcuts  ",
    core: core
  )
  #expect(updatedList.id == list.id)
  #expect(updatedList.name == "Renamed shortcut list")
  #expect(updatedList.description == "Updated from Shortcuts")
  let lists = try await LorvexTaskIntentRunner.readLists(core: core)
  #expect(lists.lists.contains { $0.id == list.id })
  let listDetail = try await LorvexTaskIntentRunner.readListDetail(
    id: " \(list.id) ",
    limit: 10,
    offset: 0,
    core: core
  )
  #expect(listDetail.list.id == list.id)
  #expect(listDetail.limit == 10)
  let listHealth = try await LorvexTaskIntentRunner.readListHealth(core: core)
  #expect(listHealth.totalLists == listHealth.lists.count)
  let deletedListID = try await LorvexTaskIntentRunner.deleteList(
    id: " \(list.id) ",
    core: core
  )
  #expect(deletedListID == list.id)
  #expect(!((try await core.loadLists()).lists.contains { $0.id == list.id }))

  let batchList = try await LorvexTaskIntentRunner.createList(
    name: "  Shortcut batch list  ",
    description: nil,
    core: core
  )
  let createdBatch = try await LorvexTaskIntentRunner.batchCreateTasks(
    titlesText: "Shortcut batch one\nShortcut batch two",
    notes: "Created as a shortcut batch.",
    listID: batchList.id,
    priority: 1,
    core: core
  )
  let batchOne = try #require(createdBatch.first { $0.title == "Shortcut batch one" })
  let batchTwo = try #require(createdBatch.first { $0.title == "Shortcut batch two" })
  #expect(batchOne.priority == .p1)
  let batchIDs = [batchOne.id, batchTwo.id]
  let missingID = "missing-\(UUID().uuidString)"
  var result = try await LorvexTaskIntentRunner.batchCompleteTasks(
    taskIDs: batchIDs + [missingID],
    core: core
  )
  #expect(result.changedIDs.sorted() == batchIDs.sorted())
  #expect(result.skipped == [missingID])
  // Completed tasks leave the open-only Today snapshot; the row is the evidence.
  #expect(!result.snapshot.tasks.contains { $0.id == batchOne.id })
  #expect(try await core.loadTask(id: batchOne.id).status == .completed)
  result = try await LorvexTaskIntentRunner.batchReopenTasks(
    taskIDs: batchIDs,
    core: core
  )
  #expect(result.changedIDs.sorted() == batchIDs.sorted())
  #expect(result.skipped.isEmpty)
  #expect(result.snapshot.tasks.first { $0.id == batchTwo.id }?.status == .open)
  result = try await LorvexTaskIntentRunner.batchDeferTasks(
    taskIDs: batchIDs,
    until: " 2026-05-30 ",
    core: core
  )
  #expect(result.changedIDs.sorted() == batchIDs.sorted())
  #expect(result.skipped.isEmpty)
  #expect(result.snapshot.tasks.first { $0.id == batchOne.id }?.status == .open)
  // A move to the list the tasks already occupy is a skip, not a success, so
  // the batch move targets a fresh destination list.
  let moveDestination = try await LorvexTaskIntentRunner.createList(
    name: "Shortcut batch destination",
    description: nil,
    core: core
  )
  let movedBatch = try await LorvexTaskIntentRunner.batchMoveTasks(
    taskIDs: batchIDs,
    listID: " \(moveDestination.id) ",
    core: core
  )
  #expect(movedBatch.map(\.id).sorted() == [batchOne.id, batchTwo.id].sorted())

  let taggedTask = try await core.updateTask(
    id: created.id,
    title: created.title,
    notes: created.notes,
    priority: created.priority,
    estimatedMinutes: created.estimatedMinutes,
    plannedDate: created.dueDate,
    tags: ["shortcut", "apple"],
    dependsOn: created.dependsOn
  )
  // Tags added in one write surface alphabetically (shared created_at).
  #expect(taggedTask.tags == ["apple", "shortcut"])
  let allTags = try await LorvexTaskIntentRunner.listAllTags(core: core)
  #expect(allTags.contains("apple"))
  #expect(allTags.contains("shortcut"))
  let renamedTag = try await LorvexTaskIntentRunner.renameTag(
    oldTag: " shortcut ",
    newTag: " system ",
    core: core
  )
  #expect(renamedTag == "system")
  let taggedTasks = try await LorvexTaskIntentRunner.getTasksByTag(tag: " system ", core: core)
  #expect(taggedTasks.map(\.id).contains(created.id))
}
