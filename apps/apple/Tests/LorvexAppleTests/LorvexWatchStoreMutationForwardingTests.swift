import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWatch

/// A forwarder that records every mutation it receives, for use in unit tests.
final class RecordingMutationForwarder: LorvexWatchMutationForwarding, @unchecked Sendable {
  private let lock = NSLock()
  private var _forwarded: [LorvexWatchMutation] = []

  init() {}

  func forward(_ mutation: LorvexWatchMutation) async throws {
    lock.withLock { _forwarded.append(mutation) }
  }

  /// All mutations forwarded since construction, in order.
  var forwarded: [LorvexWatchMutation] {
    lock.withLock { _forwarded }
  }
}

// MARK: - Watch-side forwarding

@Suite("LorvexWatchStore forwards mutations on snapshot backend")
@MainActor
struct LorvexWatchStoreMutationForwardingTests {
  @Test("completePrimaryTask forwards completeTask mutation")
  func completePrimaryTaskForwards() async throws {
    let service = try await makeSeededInMemoryCore()
    let task = try await seedWatchFocus(in: service, date: "2026-05-25", title: "Forward complete")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(task: task, forwarder: forwarder, date: "2026-05-25")

    await store.completePrimaryTask()

    #expect(forwarder.forwarded == [.completeTask(id: task.id)])
    #expect(store.error == nil)
  }

  @Test("completeHabit forwards the mutation and bumps progress optimistically")
  func completeHabitForwards() async throws {
    let service = try await makeSeededInMemoryCore()
    let task = try await seedWatchFocus(in: service, date: "2026-05-25", title: "Habit host")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(task: task, forwarder: forwarder, date: "2026-05-25")
    store.habits = [
      WidgetSnapshot.HabitSummary(
        id: "h1", name: "Hydrate", icon: nil, completedToday: 0, target: 2)
    ]

    await store.completeHabit(id: "h1")

    #expect(forwarder.forwarded == [.completeHabit(id: "h1", date: "2026-05-25")])
    #expect(store.habits.first?.completedToday == 1)

    // A done habit ignores further taps.
    store.habits = [
      WidgetSnapshot.HabitSummary(
        id: "h1", name: "Hydrate", icon: nil, completedToday: 2, target: 2)
    ]
    await store.completeHabit(id: "h1")
    #expect(forwarder.forwarded.count == 1)
  }

  @Test("cancelPrimaryTask forwards cancelTask mutation")
  func cancelPrimaryTaskForwards() async throws {
    let service = try await makeSeededInMemoryCore()
    let task = try await seedWatchFocus(in: service, date: "2026-05-25", title: "Forward cancel")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(task: task, forwarder: forwarder, date: "2026-05-25")

    await store.cancelPrimaryTask()

    #expect(forwarder.forwarded == [.cancelTask(id: task.id)])
    #expect(store.error == nil)
  }

  @Test("deferPrimaryTaskToTomorrow forwards deferTaskToTomorrow mutation")
  func deferPrimaryTaskForwards() async throws {
    let service = try await makeSeededInMemoryCore()
    let task = try await seedWatchFocus(in: service, date: "2026-05-25", title: "Forward defer")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(
      task: task,
      forwarder: forwarder,
      date: "2026-05-25",
      now: { Date(timeIntervalSince1970: 1_779_735_600) })

    await store.deferPrimaryTaskToTomorrow()

    #expect(
      forwarder.forwarded
        == [.deferTaskToTomorrow(id: task.id, plannedDate: "2026-05-26")])
    #expect(store.error == nil)
  }

  @Test("removePrimaryTaskFromFocus forwards removeFromFocus mutation")
  func removePrimaryTaskForwards() async throws {
    let service = try await makeSeededInMemoryCore()
    let task = try await seedWatchFocus(in: service, date: "2026-05-25", title: "Forward remove")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(task: task, forwarder: forwarder, date: "2026-05-25")

    await store.removePrimaryTaskFromFocus()

    #expect(forwarder.forwarded == [.removeFromFocus(id: task.id, date: "2026-05-25")])
    #expect(store.error == nil)
  }

  @Test("captureTask forwards captureTask mutation")
  func captureTaskForwards() async throws {
    let service = try await makeSeededInMemoryCore()
    _ = try await service.createTask(title: "Seed", notes: "")
    let forwarder = RecordingMutationForwarder()
    let url = URL(fileURLWithPath: "/tmp/test-snapshot-capture.json")
    let store = LorvexWatchStore(
      snapshotURL: url,
      mutationForwarder: forwarder
    )
    store.captureTitle = "Captured on watch"

    await store.captureTask()

    #expect(forwarder.forwarded == [.captureTask(title: "Captured on watch")])
    #expect(store.captureTitle.isEmpty)
    #expect(store.error == nil)
  }

  @Test("rapid capture taps enqueue only one command while persistence is in flight")
  func rapidCaptureTapsAreSingleFlight() async {
    let forwarder = BlockingMutationForwarder()
    let store = LorvexWatchStore(
      snapshotURL: URL(fileURLWithPath: "/tmp/test-snapshot-capture-single-flight.json"),
      mutationForwarder: forwarder)
    store.captureTitle = "One durable capture"

    let first = Task { await store.captureTask() }
    await forwarder.waitUntilForwardStarted()
    #expect(store.isLoading)

    await store.captureTask()
    #expect(await forwarder.forwardedMutations() == [.captureTask(title: "One durable capture")])

    await forwarder.release()
    await first.value
    #expect(store.captureTitle.isEmpty)
    #expect(!store.isLoading)
  }

  @Test("pending capture label derives only from authoritative journal status")
  func pendingCaptureTitleFollowsDeliveryStatus() {
    let store = LorvexWatchStore(
      snapshotURL: URL(fileURLWithPath: "/tmp/test-snapshot-capture-status.json"),
      mutationForwarder: RecordingMutationForwarder())
    store.updateDeliveryStatus(
      LorvexWatchDeliveryStatus(pendingCommands: [
        LorvexWatchPendingCommand(
          id: "11111111-1111-4111-8111-111111111111",
          sequence: 1,
          mutation: .captureTask(title: "Earlier")),
        LorvexWatchPendingCommand(
          id: "22222222-2222-4222-8222-222222222222",
          sequence: 2,
          mutation: .completeTask(id: "33333333-3333-4333-8333-333333333333")),
        LorvexWatchPendingCommand(
          id: "44444444-4444-4444-8444-444444444444",
          sequence: 3,
          mutation: .captureTask(title: "Latest")),
      ]))

    #expect(store.pendingCaptureTitle == "Latest")
    store.updateDeliveryStatus(.empty)
    #expect(store.pendingCaptureTitle == nil)
  }

  @Test("completePrimaryTask sets error when no forwarder on snapshot backend")
  func completePrimaryTaskErrorsWithoutForwarder() async throws {
    let service = try await makeSeededInMemoryCore()
    let task = try await seedWatchFocus(in: service, date: "2026-05-25", title: "No forwarder")
    let store = makeSnapshotStore(task: task, forwarder: nil, date: "2026-05-25")

    await store.completePrimaryTask()

    #expect(
      store.error?.localizedDescription
        == String(
          localized: "watch.error.forwarder_required",
          defaultValue: "Open Lorvex on iPhone or Mac to apply this action.",
          table: "Localizable",
          bundle: WatchL10n.bundle))
  }

  @Test("captureTask sets localized error when no forwarder on snapshot backend")
  func captureTaskErrorsWithoutForwarder() async throws {
    let store = LorvexWatchStore(
      snapshotURL: URL(fileURLWithPath: "/tmp/test-snapshot-no-forwarder-capture.json"),
      mutationForwarder: nil)
    store.captureTitle = "Captured without forwarder"

    await store.captureTask()

    #expect(
      store.error?.localizedDescription
        == String(
          localized: "watch.error.capture_forwarder_required",
          defaultValue: "Open Lorvex on iPhone or Mac to capture new tasks.",
          table: "Localizable",
          bundle: WatchL10n.bundle))
  }

  @Test("canWrite is true when forwarder present on snapshot backend")
  func canWriteWithForwarder() throws {
    let url = URL(fileURLWithPath: "/tmp/test-snapshot.json")
    let store = LorvexWatchStore(
      snapshotURL: url,
      mutationForwarder: RecordingMutationForwarder()
    )
    #expect(store.canWrite == true)
  }

  @Test("canWrite is false when no forwarder on snapshot backend")
  func canWriteWithoutForwarder() throws {
    let url = URL(fileURLWithPath: "/tmp/test-snapshot.json")
    let store = LorvexWatchStore(snapshotURL: url, mutationForwarder: nil)
    #expect(store.canWrite == false)
  }

  // MARK: - Optimistic update (item 1)

  @Test("completePrimaryTask removes task from focusTasks immediately on snapshot backend")
  func completePrimaryTaskAppliesOptimisticUpdate() async throws {
    let service = try await makeSeededInMemoryCore()
    let task = try await seedWatchFocus(
      in: service, date: "2026-05-25", title: "Optimistic complete")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(task: task, forwarder: forwarder, date: "2026-05-25")

    await store.completePrimaryTask()

    // Optimistic update: primaryTask is nil immediately, no refresh needed.
    #expect(store.primaryTask == nil)
    #expect(store.focusTasks.isEmpty)
    #expect(store.error == nil)
  }

  @Test("cancelPrimaryTask removes task from focusTasks immediately on snapshot backend")
  func cancelPrimaryTaskAppliesOptimisticUpdate() async throws {
    let service = try await makeSeededInMemoryCore()
    let task = try await seedWatchFocus(in: service, date: "2026-05-25", title: "Optimistic cancel")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(task: task, forwarder: forwarder, date: "2026-05-25")

    await store.cancelPrimaryTask()

    #expect(store.primaryTask == nil)
    #expect(store.focusTasks.isEmpty)
    #expect(store.error == nil)
  }
}

private actor BlockingMutationForwarder: LorvexWatchMutationForwarding {
  private var forwarded: [LorvexWatchMutation] = []
  private var didStart = false
  private var released = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func forward(_ mutation: LorvexWatchMutation) async throws {
    forwarded.append(mutation)
    didStart = true
    let waiters = startWaiters
    startWaiters = []
    for waiter in waiters { waiter.resume() }
    guard !released else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func waitUntilForwardStarted() async {
    if didStart { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func release() {
    released = true
    let waiters = releaseWaiters
    releaseWaiters = []
    for waiter in waiters { waiter.resume() }
  }

  func forwardedMutations() -> [LorvexWatchMutation] { forwarded }
}

// MARK: - Helpers

/// Creates a snapshot-backend watch store with `primaryTask` pre-seeded for forwarding tests.
///
/// Uses `@testable import LorvexWatch` to set `internal(set)` properties directly,
/// bypassing the snapshot read path which requires a real file on disk.
@MainActor
private func makeSnapshotStore(
  task: LorvexTask,
  forwarder: (any LorvexWatchMutationForwarding)?,
  date: String,
  now: @escaping @Sendable () -> Date = Date.init
) -> LorvexWatchStore {
  let url = URL(fileURLWithPath: "/tmp/test-snapshot-\(task.id).json")
  let store = LorvexWatchStore(
    snapshotURL: url,
    now: now,
    mutationForwarder: forwarder
  )
  store.primaryTask = task
  store.focusTasks = [task]
  store.logicalDay = date
  return store
}
