import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexSystemIntents

@Test
func reopenTaskIntentUsesReopenableTaskEntity() {
  let intent = ReopenLorvexTaskIntent(
    task: LorvexReopenableTaskEntity(id: "closed-task-id", title: "Closed task", status: "cancelled")
  )
  #expect(intent.task.id == "closed-task-id")
  #expect(intent.task.title == "Closed task")
  #expect(ReopenLorvexTaskIntent.openAppWhenRun == false)
}

@Test
func reopenableTaskEntityQuerySuggestsOnlyClosedTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let open = try await core.createTask(title: "Open shortcut task", notes: "")
  let completed = try await core.createTask(title: "Completed shortcut task", notes: "")
  let cancelled = try await core.createTask(title: "Cancelled shortcut task", notes: "")
  let deferred = try await core.createTask(title: "Deferred shortcut task", notes: "")
  _ = try await core.completeTask(id: completed.id)
  _ = try await core.cancelTask(id: cancelled.id)
  _ = try await core.deferTask(id: deferred.id, until: Date(timeIntervalSince1970: 1_779_494_400))

  let suggested = try await LorvexReopenableTaskEntityQuery.suggestedEntities(core: core)

  #expect(!suggested.contains { $0.id == open.id })
  #expect(suggested.contains { $0.id == completed.id && $0.status == "completed" })
  #expect(suggested.contains { $0.id == cancelled.id && $0.status == "cancelled" })
  // A deferred task stays open (defer pushes planned_date), so it is not
  // reopenable and never appears in suggestions.
  #expect(!suggested.contains { $0.id == deferred.id })
}

@Test
func reopenableTaskEntityQueryUsesFullCorpusInsteadOfTodaySnapshot() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.loadTodayError = .unsupportedOperation("loadToday must not feed reopenable task suggestions")
  let completed = try await core.createTask(title: "Completed offscreen shortcut task", notes: "")
  let cancelled = try await core.createTask(title: "Cancelled offscreen shortcut task", notes: "")
  let deferred = try await core.createTask(title: "Deferred offscreen shortcut task", notes: "")
  _ = try await core.completeTask(id: completed.id)
  _ = try await core.cancelTask(id: cancelled.id)
  _ = try await core.deferTask(id: deferred.id, until: Date(timeIntervalSince1970: 1_779_494_400))

  let suggested = try await LorvexReopenableTaskEntityQuery.suggestedEntities(core: core)
  let matches = try await LorvexReopenableTaskEntityQuery.entities(matching: "offscreen", core: core)

  #expect(suggested.contains { $0.id == completed.id && $0.status == "completed" })
  #expect(suggested.contains { $0.id == cancelled.id && $0.status == "cancelled" })
  // The deferred task stays open and is not reopenable.
  #expect(!suggested.contains { $0.id == deferred.id })
  #expect(matches.map(\.id).contains(completed.id))
  #expect(matches.map(\.id).contains(cancelled.id))
  #expect(!matches.map(\.id).contains(deferred.id))
}
