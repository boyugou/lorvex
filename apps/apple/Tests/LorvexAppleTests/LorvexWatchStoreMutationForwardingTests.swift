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
  @Test("completeTask forwards completeTask mutation")
  func completeTaskForwards() async throws {
    let task = try await makeWatchTask(title: "Forward complete")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(tasks: [task], forwarder: forwarder, date: "2026-05-25")

    await store.completeTask(id: task.id)

    #expect(forwarder.forwarded == [.completeTask(id: task.id)])
    #expect(store.error == nil)
  }

  @Test("completeHabit forwards the mutation and bumps progress optimistically")
  func completeHabitForwards() async throws {
    let task = try await makeWatchTask(title: "Habit host")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(tasks: [task], forwarder: forwarder, date: "2026-05-25")
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

  @Test("cancelTask forwards cancelTask mutation")
  func cancelTaskForwards() async throws {
    let task = try await makeWatchTask(title: "Forward cancel")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(tasks: [task], forwarder: forwarder, date: "2026-05-25")

    await store.cancelTask(id: task.id)

    #expect(forwarder.forwarded == [.cancelTask(id: task.id)])
    #expect(store.error == nil)
  }

  @Test("deferTaskToTomorrow forwards deferTaskToTomorrow mutation")
  func deferTaskForwards() async throws {
    let task = try await makeWatchTask(title: "Forward defer")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(
      tasks: [task],
      forwarder: forwarder,
      date: "2026-05-25",
      now: { Date(timeIntervalSince1970: 1_779_735_600) })

    await store.deferTaskToTomorrow(id: task.id)

    #expect(
      forwarder.forwarded
        == [.deferTaskToTomorrow(id: task.id, plannedDate: "2026-05-26")])
    #expect(store.error == nil)
  }

  @Test("startTask and pauseTask forward and move the task within the list")
  func startAndPauseForward() async throws {
    let first = try await makeWatchTask(title: "Already first")
    let second = try await makeWatchTask(title: "Started from the wrist")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(
      tasks: [first, second], forwarder: forwarder, date: "2026-05-25")

    await store.startTask(id: second.id)

    #expect(forwarder.forwarded == [.startTask(id: second.id)])
    // Optimistic update: started tasks lead the list until the phone's next
    // snapshot settles the exact order.
    #expect(store.tasks.map(\.id) == [second.id, first.id])
    #expect(store.tasks.first?.status == .inProgress)

    await store.pauseTask(id: second.id)

    #expect(forwarder.forwarded == [.startTask(id: second.id), .pauseTask(id: second.id)])
    #expect(store.tasks.allSatisfy { $0.status == .open })
    #expect(store.error == nil)
  }

  @Test("captureTask forwards captureTask mutation")
  func captureTaskForwards() async throws {
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

  @Test("completeTask sets error when no forwarder on snapshot backend")
  func completeTaskErrorsWithoutForwarder() async throws {
    let task = try await makeWatchTask(title: "No forwarder")
    let store = makeSnapshotStore(tasks: [task], forwarder: nil, date: "2026-05-25")

    await store.completeTask(id: task.id)

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

  @Test("completeTask takes the task off the list immediately on snapshot backend")
  func completeTaskAppliesOptimisticUpdate() async throws {
    let task = try await makeWatchTask(title: "Optimistic complete")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(tasks: [task], forwarder: forwarder, date: "2026-05-25")

    await store.completeTask(id: task.id)

    // Optimistic update: the row leaves at once, no refresh needed.
    #expect(store.tasks.isEmpty)
    #expect(store.completedTodayCount == 1)
    #expect(store.error == nil)
  }

  @Test("cancelTask takes the task off the list immediately on snapshot backend")
  func cancelTaskAppliesOptimisticUpdate() async throws {
    let task = try await makeWatchTask(title: "Optimistic cancel")
    let forwarder = RecordingMutationForwarder()
    let store = makeSnapshotStore(tasks: [task], forwarder: forwarder, date: "2026-05-25")

    await store.cancelTask(id: task.id)

    #expect(store.tasks.isEmpty)
    #expect(store.completedTodayCount == 0)
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

/// A real task row for the forwarding tests, created in a throwaway core so
/// its fields have production shapes.
private func makeWatchTask(title: String) async throws -> LorvexTask {
  try await makeInMemoryCore().createTask(TaskCreateDraft(title: title))
}

/// Creates a snapshot-backend watch store listing `tasks` on the day `date`.
///
/// Uses `@testable import LorvexWatch` to set `internal(set)` properties directly,
/// bypassing the snapshot read path which requires a real file on disk.
@MainActor
private func makeSnapshotStore(
  tasks: [LorvexTask],
  forwarder: (any LorvexWatchMutationForwarding)?,
  date: String,
  now: @escaping @Sendable () -> Date = Date.init
) -> LorvexWatchStore {
  let url = URL(fileURLWithPath: "/tmp/test-snapshot-\(UUID().uuidString).json")
  let store = LorvexWatchStore(
    snapshotURL: url,
    now: now,
    mutationForwarder: forwarder
  )
  store.tasks = tasks
  store.logicalDay = date
  return store
}
