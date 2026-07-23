import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// A task-search indexer that blocks the FIRST `replaceIndexedTasks` call until
/// released, so a test can hold one `AppStore.refresh()` fan-out in flight while
/// it fires a second trigger. Counts calls so the coalesced rerun is observable.
private actor GatingTaskSearchIndexer: TaskSearchIndexing {
  private var count = 0
  private var reached = false
  private var released = false
  private var reachedContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func replaceIndexedTasks(_ tasks: [LorvexTask]) async throws {
    count += 1
    guard count == 1 else { return }
    reached = true
    reachedContinuation?.resume()
    reachedContinuation = nil
    if !released {
      await withCheckedContinuation { releaseContinuation = $0 }
    }
  }

  /// Suspends until the first index call is reached (the first refresh is in
  /// flight and parked here).
  func waitUntilFirstIndexReached() async {
    if reached { return }
    await withCheckedContinuation { reachedContinuation = $0 }
  }

  /// Releases the parked first index call so the first refresh can complete.
  func release() {
    released = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }

  func indexCallCount() -> Int { count }
}

@MainActor
@Test("a refresh trigger arriving mid-refresh reruns exactly once instead of being dropped")
func appStoreCoalescesConcurrentRefreshTriggers() async throws {
  let indexer = GatingTaskSearchIndexer()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: indexer,
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
  )

  // Refresh #1: runs until it parks inside the gated indexer, mid-fan-out.
  let firstRefresh = Task { await store.refresh() }
  await indexer.waitUntilFirstIndexReached()

  // A second trigger (Darwin DB-change / didBecomeActive / background mutation)
  // arrives while #1 is still in flight. The old drop-guard discarded it; the
  // coalescing guard records it as pending and returns immediately.
  await store.refresh()

  // Let #1 finish; it must rerun once for the pending trigger.
  await indexer.release()
  await firstRefresh.value

  #expect(await indexer.indexCallCount() == 2)
}
