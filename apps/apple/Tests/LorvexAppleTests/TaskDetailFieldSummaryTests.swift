import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple

/// The values of the macOS task detail's rows, read from the selected task's draft.

@MainActor
@Test
func taskDetailDueSummaryNamesItsOwnDayEvenOnThePlannedDay() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  var draft = TaskCreateDraft(title: "File the claim", notes: "")
  draft.plannedDate = try store.storageDate(daysFromLogicalToday: 0)
  draft.dueDate = try store.storageDate(daysFromLogicalToday: 0)
  let task = try await core.createTask(draft)
  await store.refresh()

  store.selectTaskFromList(task.id)

  #expect(store.taskDetailDoOnSummary == "Today")
  // The Due row stands alone, so a deadline on the planned day still names it.
  #expect(store.taskDetailDueSummary == "today")

  _ = try await core.updateTask(
    TaskUpdateDraft(id: task.id, dueDate: .set(try store.storageDate(daysFromLogicalToday: 1))))
  await store.refresh()
  store.selectedTaskID = nil
  store.selectTaskFromList(task.id)
  #expect(store.taskDetailDueSummary == "tomorrow")
}

@MainActor
@Test
func taskDetailHideUntilSummaryReadsAnArrivedDayAsUnset() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  var draft = TaskCreateDraft(title: "Renew the lease", notes: "")
  draft.availableFrom = try store.storageDate(daysFromLogicalToday: -3)
  let task = try await core.createTask(draft)
  await store.refresh()

  store.selectTaskFromList(task.id)
  #expect(store.taskDetailHideUntilSummary == nil)

  _ = try await core.updateTask(
    TaskUpdateDraft(id: task.id, availableFrom: .set(try store.storageDate(daysFromLogicalToday: 1))))
  await store.refresh()
  store.selectedTaskID = nil
  store.selectTaskFromList(task.id)
  #expect(store.taskDetailHideUntilSummary == "tomorrow")
}
