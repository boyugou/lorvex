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

@MainActor
@Test func existingTaskCanBePlannedFromEmptyTodayAndUndone() async throws {
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core)
  await store.refresh()
  let day = store.logicalTodayString
  let later = try #require(PlannedDayBridge.storageDate(forLogicalDay: day, addingDays: 4))
  let list = try await core.createList(name: "Studio", description: nil)
  let task = try await core.createTask(.init(title: "Bring field notes", listID: list.id, dueDate: later))
  _ = try await core.createTask(.init(title: "Reserved for Friday", plannedDate: later))
  _ = try await core.createTask(.init(title: "Hidden until Friday", availableFrom: later))
  await store.refresh()
  #expect(try await store.unplannedTodayCandidates().tasks.map(\.id) == [task.id])
  #expect(await store.addExistingTaskToToday(task, on: day))
  #expect(store.snapshot.today.tasks.contains { $0.id == task.id })
  let planned = try await core.loadTask(id: task.id)
  #expect(planned.listID == list.id && planned.dueDate == later)
  #expect(planned.plannedDate == PlannedDayBridge.storageDate(forLogicalDay: day))
  #expect(try await store.unplannedTodayCandidates().tasks.isEmpty)

  _ = try await core.updateTask(.init(id: task.id, title: "Bring revised field notes"))
  await store.performUndoOffer()
  let restored = try await core.loadTask(id: task.id)
  #expect(restored.plannedDate == nil)
  #expect(restored.title == "Bring revised field notes")
  #expect(restored.listID == list.id && restored.dueDate == later)
  #expect(!store.snapshot.today.tasks.contains { $0.id == task.id })

  // A task assigned elsewhere after the picker was opened keeps its new plan.
  _ = try await core.updateTask(.init(id: task.id, plannedDate: .set(later)))
  #expect(!(await store.addExistingTaskToToday(task, on: day)))
  #expect(try await core.loadTask(id: task.id).plannedDate == later)
  #expect(store.undoOffer == nil)
}

@MainActor
@Test func choosingFromTodaySearchesBeyondTheFirstPageAndUndoHonorsNewPlans() async throws {
  let core = try makeInMemoryCore()
  let store = MobileStore(core: core)
  await store.refresh()
  let day = store.logicalTodayString
  let later = try #require(PlannedDayBridge.storageDate(forLogicalDay: day, addingDays: 2))
  for word in ["Alpha", "Beta", "Gamma"] {
    _ = try await core.createTask(.init(title: "Notebook " + word))
  }
  let first = try await store.unplannedTodayCandidates(limit: 2)
  let second = try await store.unplannedTodayCandidates(offset: #require(first.nextOffset), limit: 2)
  let last = try #require(second.tasks.first)
  #expect(try await store.unplannedTodayCandidates(text: last.title).tasks.map(\.id) == [last.id])
  #expect(await store.addExistingTaskToToday(last, on: day))
  _ = try await core.updateTask(.init(id: last.id, plannedDate: .set(later)))
  await store.performUndoOffer()
  #expect(try await core.loadTask(id: last.id).plannedDate == later)
}
