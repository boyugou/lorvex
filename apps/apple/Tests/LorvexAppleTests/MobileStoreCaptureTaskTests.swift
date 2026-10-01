import Foundation
import LorvexCore
@testable import LorvexMobile
import Testing

@MainActor
@Test
func mobileStoreCaptureWritesThroughCoreIntoTheInbox() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    now: { Date(timeIntervalSince1970: 1_779_562_800) }
  )

  await store.refresh()
  let selectionBefore = store.selectedTaskID
  store.captureDraft = MobileCaptureDraft(
    title: "  Captured from iPhone  ",
    notes: "Use native mobile capture."
  )
  #expect(store.canSubmitCapture)

  await store.submitCaptureDraft()

  // Captured work is undated, so it belongs to the inbox and not to the day pool.
  let open = try await core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Captured from iPhone" })
  #expect(created.notes == "Use native mobile capture.")
  #expect(created.plannedDate == nil)
  #expect(created.dueDate == nil)
  #expect(!store.snapshot.today.tasks.contains { $0.id == created.id })
  // The sheet closing is the confirmation: capture pushes no detail route, moves
  // no tab, and leaves the selection alone rather than pointing it at a task the
  // surfaces left on screen could not resolve.
  #expect(!store.isPresentingCapture)
  #expect(store.selectedTaskID == selectionBefore)
  #expect(store.routePath == [])
  #expect(store.captureDraft == MobileCaptureDraft())
  #expect(store.errorMessage == nil)
  #expect(!store.isCapturing)
}

@MainActor
@Test
func mobileStoreCaptureCreatesMultipleTasksFromMultilineTitle() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let selectionBefore = store.selectedTaskID
  store.captureDraft = MobileCaptureDraft(
    title: " First mobile batch task \n\nSecond mobile batch task ",
    notes: "Captured together on mobile."
  )

  await store.submitCaptureDraft()

  let open = try await core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let first = try #require(open.tasks.first { $0.title == "First mobile batch task" })
  let second = try #require(open.tasks.first { $0.title == "Second mobile batch task" })
  #expect(first.notes == "Captured together on mobile.")
  #expect(second.notes == "Captured together on mobile.")
  // Same inbox contract as the single capture: selection untouched, no route pushed.
  #expect(store.selectedTaskID == selectionBefore)
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
  let lastTask = try #require(store.snapshot.today.tasks.last)

  #expect(await store.startTask(lastTask.id))
  #expect(store.snapshot.today.tasks.first?.id == lastTask.id, "started work leads Today")
  #expect(store.snapshot.inProgressTasks.map(\.id).contains(lastTask.id))

  #expect(await store.pauseTask(lastTask.id))
  #expect(!store.snapshot.inProgressTasks.map(\.id).contains(lastTask.id))
  #expect(store.snapshot.today.tasks.contains { $0.id == lastTask.id }, "a paused task stays on Today")

  #expect(await store.deferTask(controlledTask.id, byDays: 1))
  // Deferral pushes planned_date to tomorrow, so the task leaves today's pool;
  // the stored row is what carries the result.
  let deferred = try await core.loadTask(id: controlledTask.id)
  #expect(!store.snapshot.today.tasks.contains { $0.id == controlledTask.id })
  #expect(deferred.status == .open)
  // The loaded Today snapshot owns the synced product day; the constructor's
  // device-day closure is only a cold-start fallback before that snapshot.
  #expect(deferred.plannedDate == expectedTomorrow)

  let nextOpenTask = try #require(store.snapshot.today.tasks.first)
  await store.completeTask(nextOpenTask.id)
  // Completed tasks leave the open-only Today snapshot.
  #expect(!store.snapshot.today.tasks.contains { $0.id == nextOpenTask.id })
  #expect(!store.isMutatingTask)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreTracksMutatingTaskIDsDuringTaskActions() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  core.completeTaskDelayNanoseconds = 150_000_000
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let mutatingTask = try #require(store.snapshot.today.tasks.first)
  let unaffectedTask = try #require(store.snapshot.today.tasks.first { $0.id != mutatingTask.id })

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
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  core.completeTaskDelayNanoseconds = 150_000_000
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let first = try #require(store.snapshot.today.tasks.first)
  let second = try #require(store.snapshot.today.tasks.first { $0.id != first.id })

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
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  core.batchTaskDelayNanoseconds = 150_000_000
  let store = MobileStore(
    core: core,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let first = try #require(store.snapshot.today.tasks.first)
  let second = try #require(store.snapshot.today.tasks.first { $0.id != first.id })

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
  let task = try #require(store.snapshot.today.tasks.first)
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

@MainActor
@Test
func mobileCaptureReadsDetailsOutOfEachLine() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let list = try #require(store.lists?.lists.first)
  let hashName = list.name.filter { $0.isLetter || $0.isNumber }

  let preview = store.capturePreview("Call the caterer tomorrow 20 min #\(hashName)")
  #expect(preview.title == "Call the caterer")
  #expect(preview.words.map(\.id) == ["when", "length", "list"])
  #expect(store.capturePreview("Water the plants") == .empty)

  store.captureDraft = MobileCaptureDraft(
    title: "Call the caterer tomorrow 20 min #\(hashName)\nSort photos low priority")
  await store.submitCaptureDraft()

  #expect(store.errorMessage == nil)
  let open = try await core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let caterer = try #require(open.tasks.first { $0.title == "Call the caterer" })
  #expect(caterer.plannedDate == (try store.captureStorageDate(daysFromLogicalToday: 1)))
  #expect(caterer.estimatedMinutes == 20)
  #expect(caterer.listID == list.id)
  #expect(caterer.rawInput == "Call the caterer tomorrow 20 min #\(hashName)")
  let photos = try #require(open.tasks.first { $0.title == "Sort photos" })
  #expect(photos.priority == .p3)
  #expect(photos.plannedDate == nil)
}

@Test
func batchCreateKeepsEveryDraftField() async throws {
  // The batch path writes the same fields as the single create, raw input and
  // hide-until included.
  let core = try await makeSeededInMemoryCore()
  let day = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-06-01"))
  var draft = TaskCreateDraft(title: "Batch with details")
  draft.rawInput = "Batch with details tomorrow"
  draft.availableFrom = day
  let created = try await core.batchCreateTasks([draft, TaskCreateDraft(title: "Second")])
  let task = try #require(created.first { $0.title == "Batch with details" })
  #expect(task.rawInput == "Batch with details tomorrow")
  #expect(task.availableFrom == day)
}

@MainActor
@Test
func mobileCaptureOfSeveralLinesKeepsTimesAndRepeats() async throws {
  let core = try await makeSeededInMemoryCore()
  // The core's own logical today: a repeating task's first occurrence is
  // never earlier than it.
  let store = MobileStore(core: core)
  await store.refresh()
  let firstOccurrence = try #require(store.captureParse("Standup every mon and thu 9:30am").resolvedDueDayOffset)

  #expect(
    store.capturePreview("Standup every mon and thu 9:30am").words.map(\.id) == ["when", "time", "repeats", "due"])

  store.captureDraft = MobileCaptureDraft(title: "Standup every mon and thu 9:30am\nDentist 4pm")
  await store.submitCaptureDraft()

  #expect(store.errorMessage == nil)
  let open = try await core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let standup = try #require(open.tasks.first { $0.title == "Standup" })
  #expect(standup.recurrence?.byDay == ["MO", "TH"])
  let monday = try store.captureStorageDate(daysFromLogicalToday: firstOccurrence)
  #expect(standup.dueDate == monday)
  #expect(standup.plannedDate == monday)
  #expect(standup.plannedTime == (9 * 60 + 30)..<(10 * 60))
  let dentist = try #require(open.tasks.first { $0.title == "Dentist" })
  #expect(dentist.plannedDate == (try store.captureStorageDate(daysFromLogicalToday: 0)))
  #expect(dentist.plannedTime == (16 * 60)..<(16 * 60 + 30))
  #expect(dentist.recurrence == nil)
}
