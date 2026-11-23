import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

/// A widget publisher whose first publish waits until the test releases it, so
/// a test can hold one publish in flight while a newer one runs.
@MainActor
private final class GatingWidgetSnapshotPublisher: WidgetSnapshotPublishing {
  private let recorder = RecordingWidgetSnapshotPublisher()
  private var calls = 0
  private var hasEntered = false
  private var released = false
  private var entered: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?

  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    calls += 1
    if calls == 1 {
      hasEntered = true
      entered?.resume()
      entered = nil
      if !released { await withCheckedContinuation { release = $0 } }
    }
    return try await recorder.publish(source: source)
  }

  func waitUntilFirstPublishEntered() async {
    if hasEntered { return }
    await withCheckedContinuation { entered = $0 }
  }

  func releaseFirstPublish() {
    released = true
    release?.resume()
    release = nil
  }
}

@MainActor
@Test("a widget publish that a newer one overtook does not put its older badge count back")
func overtakenWidgetPublishLeavesTheBadgeToTheNewerOne() async throws {
  let core = try makeInMemoryCore()
  let pastDay = try #require(LorvexDateFormatters.ymdUTC.date(from: "2020-01-02"))
  let done = try await core.createTask(
    TaskCreateDraft(title: "Overdue one", priority: .p1, dueDate: pastDay))
  _ = try await core.createTask(TaskCreateDraft(title: "Overdue two", priority: .p1, dueDate: pastDay))
  let publisher = GatingWidgetSnapshotPublisher()
  let badge = RecordingBadgeSetter()
  let store = AppStore(core: core, widgetSnapshotPublisher: publisher, setBadge: { await badge.set($0) })

  // The older publish has read two overdue tasks and waits inside its write.
  let older = Task { await store.publishWidgetSnapshotAndUpdateBadge() }
  await publisher.waitUntilFirstPublishEntered()

  // One is completed, and a newer publish reads and counts the one left.
  _ = try await core.completeTask(id: done.id)
  await store.publishWidgetSnapshotAndUpdateBadge()
  #expect(await badge.lastCount() == 1)

  publisher.releaseFirstPublish()
  await older.value
  #expect(await badge.lastCount() == 1, "the older publish set its count of two")
  #expect(store.menuBarAttentionCount == 1)
}
