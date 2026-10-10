import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// Mobile parity with the macOS occurrence-vs-series cancel: a bare cancel on a
// recurring task spawns its successor, so cancelling a recurring task must ask
// the user whether to end one occurrence or the whole series.

@MainActor
@Test
func mobileCancelOfRecurringTaskAsksForScope() async throws {
  let core = try await makeSeededInMemoryCore()
  let recurring = try await core.loadTask(id: LorvexPreviewSeedID.statusUpdateTask)

  #expect(recurring.recurrence != nil)
  #expect(MobileTaskActionSection.cancelAsksForScope(recurring))
  // Asking cancels nothing by itself.
  #expect((try await core.loadTask(id: recurring.id)).status == .open)
}

@MainActor
@Test
func mobileCancelOfNonRecurringTaskDoesNotAsk() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let nonRecurring = try #require(
    store.snapshot.today.tasks.first { $0.recurrence == nil && $0.status == .open })

  #expect(!MobileTaskActionSection.cancelAsksForScope(nonRecurring))

  await store.cancelTask(nonRecurring.id)

  #expect((try await core.loadTask(id: nonRecurring.id)).status == .cancelled)
}

@MainActor
@Test
func mobileCancelRecurringTaskAllOccurrencesEndsSeries() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let recurring = try await core.loadTask(id: LorvexPreviewSeedID.statusUpdateTask)

  await store.cancelRecurringTask(id: recurring.id, scope: .all)

  let cancelled = try await core.loadTask(id: recurring.id)
  #expect(cancelled.status == .cancelled)
  #expect(cancelled.recurrence == nil)
}

@MainActor
@Test
func mobileCancelRecurringTaskThisOccurrenceKeepsSeriesRule() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let recurring = try await core.loadTask(id: LorvexPreviewSeedID.statusUpdateTask)

  await store.cancelRecurringTask(id: recurring.id, scope: .thisOccurrence)

  let cancelled = try await core.loadTask(id: recurring.id)
  #expect(cancelled.status == .cancelled)
  #expect(cancelled.recurrence != nil)
}
