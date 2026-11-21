import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// Empty Today's "No Open Tasks" card shows only when its title is true: the
/// lists have loaded and none holds an open task. A finished task leaves its
/// list empty in this sense.
@MainActor
@Test
func mobileStoreHasNoOpenTasksOnlyWhenNoListHoldsOpenWork() async throws {
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core)
  #expect(!store.hasNoOpenTasks)

  await store.refresh()
  #expect(store.hasNoOpenTasks)

  let task = try await core.createTask(title: "Water the plants", notes: "")
  await store.refresh()
  #expect(!store.hasNoOpenTasks)

  _ = try await core.completeTask(id: task.id)
  await store.refresh()
  #expect(store.hasNoOpenTasks)
}

@MainActor
@Test("The first task keeps a literal title and lands on the product day")
func firstTaskOnEmptyTodayKeepsTitleAndPlan() async throws {
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core, todayString: { "1999-12-31" })
  await store.refresh()
  let title = "约明天的会 #42"
  try await store.addTaskForToday(title)
  let task = try #require(store.snapshot.today.tasks.first)
  #expect(task.title == title)
  #expect(task.plannedDate == PlannedDayBridge.storageDate(forLogicalDay: store.logicalTodayString))
  #expect(task.dueDate == nil)
  #expect(!store.hasNoOpenTasks)
}
