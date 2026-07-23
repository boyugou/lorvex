import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore

@MainActor
@Test("normal-Quit flush persists root, detached, and daily-review autosave drafts")
func terminationFlushPersistsEveryAutosaveSurface() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()

  let rootTaskID: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
  store.selectTaskFromList(rootTaskID)
  await store.loadSelectedTaskDetail()
  store.taskDetailTitle = "Root draft saved at Quit"

  let detachedTaskID: LorvexTask.ID = LorvexPreviewSeedID.venueTask
  let detached = store.makeDetachedWindowStore()
  await detached.loadDetachedTaskWindow(taskID: detachedTaskID)
  detached.taskDetailNotes = "Sticky note saved at Quit"

  store.dailyReviewSummaryDraft = "Review saved at Quit"

  #expect(store.hasPendingAutosaveDraftForTermination)
  let didFlush = await store.flushPendingAutosaveDraftsForTermination()

  #expect(didFlush)
  #expect(try await core.loadTask(id: rootTaskID).title == "Root draft saved at Quit")
  #expect(try await core.loadTask(id: detachedTaskID).notes == "Sticky note saved at Quit")
  #expect(
    try await core.loadDailyReview(date: store.logicalTodayDateString)?.summary
      == "Review saved at Quit")
  #expect(!store.hasPendingAutosaveDraftForTermination)
}

@MainActor
@Test("termination flush preserves a valid scalar edit when estimate text is malformed")
func terminationFlushDoesNotDropOtherFieldsForMalformedEstimate() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  let taskID: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
  store.selectTaskFromList(taskID)
  await store.loadSelectedTaskDetail()
  let originalEstimate = try await core.loadTask(id: taskID).estimatedMinutes

  store.taskDetailNotes = "Keep this even with an invalid estimate"
  store.taskDetailEstimatedMinutesText = "not a number"

  let didFlush = await store.flushPendingAutosaveDraftsForTermination()

  #expect(didFlush)
  let saved = try await core.loadTask(id: taskID)
  #expect(saved.notes == "Keep this even with an invalid estimate")
  #expect(saved.estimatedMinutes == originalEstimate)
}

@MainActor
@Test("termination flush persists a started task available only in the uncapped Today pool")
func terminationFlushPersistsStartedOnlyTaskDraft() async throws {
  let core = try await makeSeededInMemoryCore()
  let future = try #require(LorvexDateFormatters.ymdUTC.date(from: "2099-01-01"))
  let created = try await core.createTask(
    TaskCreateDraft(title: "Started outside the day pool", availableFrom: future))
  _ = try await core.startTask(id: created.id)

  let store = AppStore(core: core)
  await store.refresh()
  #expect(store.today.inProgressTasks.contains { $0.id == created.id })
  #expect(!store.today.tasks.contains { $0.id == created.id })

  store.selectTaskFromList(created.id)
  store.taskDetailTitle = "Started draft saved at Quit"

  #expect(store.hasPendingAutosaveDraftForTermination)
  #expect(await store.flushPendingAutosaveDraftsForTermination())
  #expect(try await core.loadTask(id: created.id).title == "Started draft saved at Quit")
  #expect(!store.hasPendingAutosaveDraftForTermination)
}
