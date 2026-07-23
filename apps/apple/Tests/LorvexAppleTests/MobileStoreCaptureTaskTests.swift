import Foundation
import LorvexCore
import LorvexMobile
import Testing

@MainActor
@Test
func mobileStoreCaptureWritesThroughCoreAndRefreshesToday() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" },
    now: { Date(timeIntervalSince1970: 1_779_562_800) }
  )

  await store.refresh()
  store.captureDraft = MobileCaptureDraft(
    title: "  Captured from iPhone  ",
    notes: "Use native mobile capture."
  )
  #expect(store.canSubmitCapture)

  await store.submitCaptureDraft()

  // Today keeps the canonical sort (priority first), so the new capture is
  // selected but not necessarily the pool's first row.
  let selectedID = try #require(store.selectedTaskID)
  let created = try #require(store.snapshot.today.tasks.first { $0.id == selectedID })
  #expect(created.title == "Captured from iPhone")
  #expect(created.notes == "Use native mobile capture.")
  #expect(store.selectedTab == .today)
  // Quick capture is a global action: it creates and selects the task but does NOT
  // push a detail route — it leaves the user on whatever surface they captured from.
  #expect(store.routePath == [])
  #expect(store.captureDraft == MobileCaptureDraft())
  #expect(store.errorMessage == nil)
  #expect(!store.isCapturing)
}

@MainActor
@Test
func mobileStoreCaptureCreatesMultipleTasksFromMultilineTitle() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  store.captureDraft = MobileCaptureDraft(
    title: " First mobile batch task \n\nSecond mobile batch task ",
    notes: "Captured together on mobile."
  )

  await store.submitCaptureDraft()

  let first = try #require(
    store.snapshot.today.tasks.first { $0.title == "First mobile batch task" }
  )
  let second = try #require(
    store.snapshot.today.tasks.first { $0.title == "Second mobile batch task" }
  )
  #expect(first.notes == "Captured together on mobile.")
  #expect(second.notes == "Captured together on mobile.")
  #expect(store.selectedTaskID == first.id)
  #expect(store.selectedTab == .today)
  // Global capture selects the first task but does not push a detail route.
  #expect(store.routePath == [])
  #expect(store.captureDraft == MobileCaptureDraft())
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreMutatesTasksThroughNativeMobileActions() async throws {
  let core = try await makeSeededInMemoryCore()
  let controlledTask = try await core.createTask(title: "Controlled mobile defer", notes: "")
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    now: { Date(timeIntervalSince1970: 1_779_562_800) }
  )

  await store.refresh()
  let expectedTomorrow = try #require(
    PlannedDayBridge.storageDate(
      forLogicalDay: store.logicalTodayString,
      addingDays: 1))
  let firstTask = try #require(store.snapshot.today.tasks.first)

  await store.toggleTaskFocus(firstTask.id)
  #expect(store.taskIsFocused(firstTask.id))
  #expect(store.snapshot.focusTasks.map(\.id).contains(firstTask.id))

  await store.toggleTaskFocus(firstTask.id)
  #expect(!store.taskIsFocused(firstTask.id))

  await store.deferTaskToTomorrow(controlledTask.id)
  let deferred = try #require(store.snapshot.today.tasks.first { $0.id == controlledTask.id })
  // Deferral pushes planned_date forward and keeps status open (there is no
  // `deferred` status).
  #expect(deferred.status == .open)
  // The loaded Today snapshot owns the synced product day; the constructor's
  // device-day closure is only a cold-start fallback before that snapshot.
  #expect(deferred.plannedDate == expectedTomorrow)

  let nextOpenTask = try #require(store.snapshot.openTasks.first)
  await store.completeTask(nextOpenTask.id)
  // Completed tasks leave the open-only Today snapshot.
  #expect(!store.snapshot.today.tasks.contains { $0.id == nextOpenTask.id })
  #expect(!store.isMutatingTask)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreTracksMutatingTaskIDsDuringTaskActions() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.completeTaskDelayNanoseconds = 150_000_000
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let mutatingTask = try #require(store.snapshot.openTasks.first)
  let unaffectedTask = try #require(store.snapshot.openTasks.first { $0.id != mutatingTask.id })

  let mutation = Task { await store.completeTask(mutatingTask.id) }
  for _ in 0..<30 where !store.taskIsMutating(mutatingTask.id) {
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(store.isMutatingTask)
  #expect(store.taskIsMutating(mutatingTask.id))
  #expect(!store.taskIsMutating(unaffectedTask.id))

  _ = await mutation.value
  #expect(!store.isMutatingTask)
  #expect(!store.taskIsMutating(mutatingTask.id))
  #expect(store.mutatingTaskIDs.isEmpty)
}

@MainActor
@Test
func mobileStoreAllowsDifferentTaskMutationsWhileRejectingSameTaskReentry() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.completeTaskDelayNanoseconds = 150_000_000
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let first = try #require(store.snapshot.openTasks.first)
  let second = try #require(store.snapshot.openTasks.first { $0.id != first.id })

  let firstMutation = Task { await store.completeTask(first.id) }
  for _ in 0..<30 where !store.taskIsMutating(first.id) {
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  let duplicateMutation = Task { await store.completeTask(first.id) }
  let secondMutation = Task { await store.completeTask(second.id) }
  for _ in 0..<30 where !store.taskIsMutating(second.id) {
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(store.taskIsMutating(first.id))
  #expect(store.taskIsMutating(second.id))
  #expect(store.isMutatingTask)

  let duplicateResult = await duplicateMutation.value
  let firstResult = await firstMutation.value
  let secondResult = await secondMutation.value

  #expect(duplicateResult == false)
  #expect(firstResult)
  #expect(secondResult)
  #expect(!store.isMutatingTask)
  #expect(store.mutatingTaskIDs.isEmpty)
}

@MainActor
@Test
func mobileStoreBatchTaskActionsUseUnscopedMutationGuard() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.batchTaskDelayNanoseconds = 150_000_000
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let first = try #require(store.snapshot.openTasks.first)
  let second = try #require(store.snapshot.openTasks.first { $0.id != first.id })

  let batch = Task { await store.completeTasks([first.id, second.id]) }
  for _ in 0..<30 where !store.isMutatingTask {
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(store.isMutatingTask)
  #expect(!store.taskIsMutating(first.id))
  #expect(!store.taskIsMutating(second.id))

  let duplicate = await store.completeTasks([first.id])
  let didBatch = await batch.value

  #expect(!duplicate)
  #expect(didBatch)
  #expect(core.batchCompleteTaskCallCount == 1)
  #expect(!store.isMutatingTask)
  // Completed tasks leave the open-only Today snapshot; the store rows carry
  // the completion evidence.
  #expect(!store.snapshot.today.tasks.contains { $0.id == first.id })
  #expect(!store.snapshot.today.tasks.contains { $0.id == second.id })
  #expect(try await core.preview.loadTask(id: first.id).status == .completed)
  #expect(try await core.preview.loadTask(id: second.id).status == .completed)
}

@MainActor
@Test
func mobileStoreTogglesChecklistItemFromDetailRoute() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let task = try #require(store.snapshot.openTasks.first)
  _ = try await core.addTaskChecklistItem(taskID: task.id, text: "Confirm mobile checklist")
  await store.refresh()
  store.openNavigationTarget(MobileNavigationTarget(selectedTab: .today, route: .task(task.id)))

  #expect(store.selectedTask?.id == task.id)

  // Find an incomplete checklist item (seed data may have pre-completed items).
  let checklistItem = try #require(
    store.selectedTask?.checklistItems.first { $0.completedAt == nil })
  await store.toggleChecklistItem(checklistItem)
  #expect(
    store.selectedTask?.checklistItems.first { $0.id == checklistItem.id }?.completedAt != nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreKeepsInvalidCaptureLocal() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    todayString: { "2026-05-23" }
  )
  store.captureDraft = MobileCaptureDraft(title: "   ", notes: "No title.")

  await store.submitCaptureDraft()

  #expect(store.captureDraft.notes == "No title.")
  #expect(store.snapshot.today == .empty)
  #expect(!store.isCapturing)
}
