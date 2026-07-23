import LorvexCore
import LorvexMobile
import Testing

@MainActor
@Test
func mobileStoreAddsAndRemovesChecklistItemsThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let task = try #require(store.snapshot.openTasks.first)

  let blankSaved = await store.addChecklistItem(taskID: task.id, text: "   ")
  #expect(!blankSaved)

  let initialCount = store.snapshot.today.tasks.first { $0.id == task.id }?.checklistItems.count ?? 0
  let added = await store.addChecklistItem(taskID: task.id, text: " Confirm native checklist ")
  let item = try #require(
    store.snapshot.today.tasks.first { $0.id == task.id }?.checklistItems.first {
      $0.text == "Confirm native checklist"
    }
  )

  #expect(added)

  let removed = await store.removeChecklistItem(item)

  #expect(removed)
  #expect(store.snapshot.today.tasks.first { $0.id == task.id }?.checklistItems.count == initialCount)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreChecklistMutationsDoNotReloadPlanningSnapshots() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let listLoads = core.loadListsCallCount
  let habitLoads = core.loadHabitsCallCount
  let calendarLoads = core.loadCalendarTimelineCallCount
  let task = try #require(store.snapshot.openTasks.first)

  let added = await store.addChecklistItem(taskID: task.id, text: "Targeted checklist")

  #expect(added)
  #expect(core.loadListsCallCount == listLoads)
  #expect(core.loadHabitsCallCount == habitLoads)
  #expect(core.loadCalendarTimelineCallCount == calendarLoads)
  #expect(store.selectedTask?.checklistItems.contains { $0.text == "Targeted checklist" } == true)
  #expect(store.errorMessage == nil)
}
