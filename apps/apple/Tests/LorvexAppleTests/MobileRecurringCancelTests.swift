import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// Mobile parity with the macOS occurrence-vs-series cancel: a bare cancel on a
// recurring task spawns its successor, so cancelling a recurring task must ask
// the user whether to end one occurrence or the whole series.

@MainActor
@Test
func mobileRequestCancelRecurringTaskAwaitsScopeChoice() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let recurring = try await core.loadTask(id: LorvexPreviewSeedID.statusUpdateTask)
  #expect(recurring.recurrence != nil)

  await store.requestCancelTask(recurring)

  // No immediate cancel — the dialog is pending.
  #expect(store.pendingRecurringCancelTaskID == recurring.id)
  #expect((try await core.loadTask(id: recurring.id)).status == .open)
}

@MainActor
@Test
func mobileRequestCancelNonRecurringTaskCancelsImmediately() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let nonRecurring = try #require(
    store.snapshot.today.tasks.first { $0.recurrence == nil && $0.status == .open })

  await store.requestCancelTask(nonRecurring)

  #expect(store.pendingRecurringCancelTaskID == nil)
  #expect((try await core.loadTask(id: nonRecurring.id)).status == .cancelled)
}

@MainActor
@Test
func mobileCancelRecurringTaskAllOccurrencesEndsSeries() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let recurring = try await core.loadTask(id: LorvexPreviewSeedID.statusUpdateTask)
  store.pendingRecurringCancelTaskID = recurring.id

  await store.cancelRecurringTask(id: recurring.id, scope: .all)

  let cancelled = try await core.loadTask(id: recurring.id)
  #expect(cancelled.status == .cancelled)
  #expect(cancelled.recurrence == nil)
  #expect(store.pendingRecurringCancelTaskID == nil)
}

@MainActor
@Test
func mobileCancelRecurringTaskThisOccurrenceKeepsSeriesRule() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let recurring = try await core.loadTask(id: LorvexPreviewSeedID.statusUpdateTask)
  store.pendingRecurringCancelTaskID = recurring.id

  await store.cancelRecurringTask(id: recurring.id, scope: .thisOccurrence)

  let cancelled = try await core.loadTask(id: recurring.id)
  #expect(cancelled.status == .cancelled)
  #expect(cancelled.recurrence != nil)
  #expect(store.pendingRecurringCancelTaskID == nil)
}
