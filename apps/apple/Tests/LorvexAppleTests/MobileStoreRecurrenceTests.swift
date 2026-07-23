import LorvexCore
import LorvexMobile
import Testing

@MainActor
@Test
func mobileStoreBuildsAndSavesTaskRecurrence() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let taskID = try #require(store.selectedTaskID)
  store.beginRecurrenceEditing()
  #expect(!store.taskDetailRecurrenceCanSave)

  store.taskDetailHasRecurrence = true
  store.taskDetailRecurrenceFrequency = .weekly
  store.taskDetailRecurrenceIntervalText = "2"
  store.toggleRecurrenceDay("MO")
  store.toggleRecurrenceDay("WE")

  #expect(store.taskDetailRecurrenceCanSave)
  await store.saveSelectedTaskRecurrence()

  let saved = try #require(store.snapshot.today.tasks.first { $0.id == taskID })
  #expect(saved.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO", "WE"]))
  // Live snapshot now equals the draft, so the save affordance disables itself.
  #expect(!store.taskDetailRecurrenceCanSave)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreDailyRecurrenceDropsWeekdaySelection() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let taskID = try #require(store.selectedTaskID)
  store.beginRecurrenceEditing()

  // Weekday codes selected under weekly must not leak into a non-weekly rule.
  store.taskDetailHasRecurrence = true
  store.setRecurrenceFrequency(.weekly)
  store.toggleRecurrenceDay("MO")
  store.setRecurrenceFrequency(.daily)
  store.taskDetailRecurrenceIntervalText = "3"

  await store.saveSelectedTaskRecurrence()

  let saved = try #require(store.snapshot.today.tasks.first { $0.id == taskID })
  #expect(saved.recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
  #expect(saved.recurrence?.byDay == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStorePreservesAdvancedRuleFields() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)
  await store.refresh()
  let taskID = try #require(store.selectedTaskID)
  let advanced = TaskRecurrenceRule(
    freq: .monthly, interval: 1, byDay: ["MO"], byMonth: [3],
    byMonthDay: [1, 15], bySetPos: [1], wkst: "SU", until: "2028-03-31")
  _ = try await core.setTaskRecurrence(
    taskID: taskID,
    rule: advanced
  )
  await store.refresh()

  store.beginRecurrenceEditing()
  // Monthly/ordinal constraints stay in the full-fidelity baseline rather than
  // being misrepresented as editable weekly chips.
  #expect(store.taskDetailRecurrenceByDay.isEmpty)
  #expect(!store.taskDetailRecurrenceCanSave)

  store.taskDetailRecurrenceIntervalText = "2"
  #expect(await store.saveSelectedTaskRecurrence())
  let saved = try #require(store.selectedTask?.recurrence)
  #expect(saved.interval == 2)
  #expect(saved.byDay == advanced.byDay)
  #expect(saved.byMonth == advanced.byMonth)
  #expect(saved.byMonthDay == advanced.byMonthDay)
  #expect(saved.bySetPos == advanced.bySetPos)
  #expect(saved.wkst == advanced.wkst)
  #expect(saved.until == advanced.until)
  #expect(!store.taskDetailRecurrenceCanSave)
}

@MainActor
@Test
func mobileStorePreservesCompletionAnchor() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)
  await store.refresh()
  let taskID = try #require(store.selectedTaskID)
  _ = try await core.setTaskRecurrence(
    taskID: taskID,
    rule: TaskRecurrenceRule(freq: .weekly, interval: 2, count: 10, anchor: .completion))
  await store.refresh()

  store.beginRecurrenceEditing()
  #expect(store.taskDetailRecurrenceAnchor == .completion)
  #expect(!store.taskDetailRecurrenceCanSave)
  store.taskDetailRecurrenceIntervalText = "3"
  #expect(await store.saveSelectedTaskRecurrence())
  #expect(store.selectedTask?.recurrence?.anchor == .completion)
  #expect(store.selectedTask?.recurrence?.count == 10)
}

@MainActor
@Test
func mobileStoreNoOpRecurrenceSaveDoesNotWrite() async throws {
  let stub = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: stub)
  await store.refresh()
  store.beginRecurrenceEditing()

  #expect(await store.saveSelectedTaskRecurrence())
  #expect(stub.setTaskRecurrenceCallCount == 0)
  #expect(stub.removeTaskRecurrenceCallCount == 0)
}

@MainActor
@Test
func mobileStoreSeedsAndRemovesExistingRecurrence() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let taskID = try #require(store.selectedTaskID)
  store.beginRecurrenceEditing()
  store.taskDetailHasRecurrence = true
  store.taskDetailRecurrenceFrequency = .monthly
  store.taskDetailRecurrenceIntervalText = "2"
  await store.saveSelectedTaskRecurrence()
  #expect(store.selectedTask?.recurrence != nil)

  // Re-open: editor seeds from the persisted rule.
  store.beginRecurrenceEditing()
  #expect(store.taskDetailHasRecurrence)
  #expect(store.taskDetailRecurrenceFrequency == .monthly)
  #expect(store.taskDetailRecurrenceIntervalText == "2")
  #expect(!store.taskDetailRecurrenceCanSave)

  store.taskDetailHasRecurrence = false
  #expect(store.taskDetailRecurrenceCanSave)
  await store.saveSelectedTaskRecurrence()

  let saved = try #require(store.snapshot.today.tasks.first { $0.id == taskID })
  #expect(saved.recurrence == nil)
  #expect(!store.taskDetailRecurrenceCanSave)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreRecurrenceSaveDoesNotReloadPlanningSnapshots() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core)

  await store.refresh()
  let listLoads = core.loadListsCallCount
  let habitLoads = core.loadHabitsCallCount
  let calendarLoads = core.loadCalendarTimelineCallCount
  store.beginRecurrenceEditing()
  store.taskDetailHasRecurrence = true
  store.taskDetailRecurrenceFrequency = .weekly
  store.taskDetailRecurrenceIntervalText = "2"

  let saved = await store.saveSelectedTaskRecurrence()

  #expect(saved)
  #expect(core.loadListsCallCount == listLoads)
  #expect(core.loadHabitsCallCount == habitLoads)
  #expect(core.loadCalendarTimelineCallCount == calendarLoads)
  #expect(store.selectedTask?.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
  #expect(store.errorMessage == nil)
}
