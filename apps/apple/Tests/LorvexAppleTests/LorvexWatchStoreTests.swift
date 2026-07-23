import Foundation
import LorvexCore
@testable import LorvexWatch
import LorvexWidgetKitSupport
import Testing

// MARK: - Tests

@Suite("LorvexWatchStore")
@MainActor
struct LorvexWatchStoreTests {

  @Test("refresh with active focus populates primaryTask")
  func refreshPopulatesPrimaryTask() async throws {
    let service = try await makeSeededInMemoryCore()
    let title = "Design watch UI"
    try await seedWatchFocus(in: service, date: "2026-05-24", title: title)

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    #expect(store.primaryTask != nil)
    #expect(store.primaryTask?.title == title)
    #expect(store.snapshotStatusText == "Live from Lorvex")
    #expect(store.error == nil)
  }

  @Test("refresh with no focus plan leaves primaryTask nil")
  func refreshWithoutFocusPlan() async throws {
    let service = try await makeSeededInMemoryCore()
    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")

    await store.refresh()

    #expect(store.primaryTask == nil)
    #expect(store.currentFocus == nil)
    #expect(store.error == nil)
  }

  @Test("isLoading is false after refresh completes")
  func isLoadingFalseAfterRefresh() async throws {
    let service = try await makeSeededInMemoryCore()
    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")

    await store.refresh()

    #expect(store.isLoading == false)
  }

  @Test("snapshot backend loads primary focus task read-only")
  func snapshotBackendLoadsPrimaryTaskReadOnly() async throws {
    let snapshotURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-watch-\(UUID().uuidString)")
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    try FileManager.default.createDirectory(
      at: snapshotURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-05-24T12:00:00Z",
      timezone: "America/Los_Angeles",
      stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1),
      briefing: "Watch focus",
      focusTasks: [
        .init(
          id: "watch-task",
          title: "Review Apple companion",
          status: LorvexTask.Status.open.rawValue,
          dueDate: "2026-05-24",
          priority: 1,
          listID: nil,
          estimatedMinutes: 25
        )
      ]
    )
    try writeWatchStoreReplica(snapshot, to: snapshotURL)

    let store = LorvexWatchStore(
      snapshotURL: snapshotURL,
      now: { Date(timeIntervalSince1970: 1_779_624_180) }
    )
    await store.refresh()

    #expect(store.primaryTask?.id == "watch-task")
    #expect(store.primaryTask?.title == "Review Apple companion")
    #expect(store.primaryTask?.priority == .p1)
    #expect(store.primaryTask?.estimatedMinutes == 25)
    #expect(store.currentFocus?.taskIDs == ["watch-task"])
    #expect(store.currentFocus?.briefing == "Watch focus")
    #expect(store.snapshotStatusText == "Synced 3m ago")
    #expect(
      LorvexWatchStore.snapshotStatusLabel(
        snapshot,
        now: Date(timeIntervalSince1970: 1_779_624_180)
      ) == "Synced 3m ago")
    #expect(store.canCompletePrimaryTask == false)
    #expect(store.canCancelPrimaryTask == false)
    #expect(store.canDeferPrimaryTask == false)
    #expect(store.canRemovePrimaryTaskFromFocus == false)
    #expect(store.canCaptureTask == false)
    #expect(
      store.completionUnavailableReason == "Open Lorvex on iPhone or Mac to complete this task.")
    #expect(store.focusMutationUnavailableReason == "Open Lorvex on iPhone or Mac to change focus.")
    #expect(store.captureUnavailableReason == "Open Lorvex on iPhone or Mac to capture new tasks.")
    #expect(store.error == nil)

    await store.completePrimaryTask()
    #expect(store.error != nil)
    await store.cancelPrimaryTask()
    #expect(store.error != nil)
    await store.deferPrimaryTaskToTomorrow()
    #expect(store.error != nil)
    await store.removePrimaryTaskFromFocus()
    #expect(store.error != nil)
    store.captureTitle = "Snapshot capture"
    await store.captureTask()
    #expect(store.error != nil)
  }

  @Test("snapshot backend reports missing snapshot")
  func snapshotBackendReportsMissingSnapshot() async throws {
    let snapshotURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("missing-watch-\(UUID().uuidString)")
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    let store = LorvexWatchStore(snapshotURL: snapshotURL)

    await store.refresh()

    #expect(store.primaryTask == nil)
    #expect(store.currentFocus == nil)
    #expect(store.snapshotStatusText == "Open Lorvex to sync")
    #expect(store.error is LorvexWatchSnapshotError)
    #expect(store.canCompletePrimaryTask == false)
    #expect(store.canCancelPrimaryTask == false)
    #expect(store.canDeferPrimaryTask == false)
    #expect(store.canRemovePrimaryTaskFromFocus == false)
    #expect(store.completionUnavailableReason == nil)
    #expect(store.focusMutationUnavailableReason == nil)
  }

  @Test("snapshot backend reports invalid snapshot data")
  func snapshotBackendReportsInvalidSnapshotData() async throws {
    let snapshotURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("invalid-watch-\(UUID().uuidString)")
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    try FileManager.default.createDirectory(
      at: snapshotURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(to: snapshotURL, options: [.atomic])
    defer { try? FileManager.default.removeItem(at: snapshotURL.deletingLastPathComponent()) }
    let store = LorvexWatchStore(snapshotURL: snapshotURL)

    await store.refresh()

    #expect(store.primaryTask == nil)
    #expect(store.currentFocus == nil)
    #expect(store.snapshotStatusText == "Snapshot data damaged")
    guard
      let error = store.error as? LorvexWatchSnapshotError,
      case .unavailable(let fallback) = error
    else {
      Issue.record("Expected snapshot fallback error")
      return
    }
    #expect(fallback.reason == .invalidJSON)
    #expect(
      error.localizedDescription == String(
        format: String(
          localized: "watch.error.snapshot_unavailable",
          defaultValue: "Focus snapshot unavailable: %@",
          table: "Localizable",
          bundle: WatchL10n.bundle),
        "Snapshot data damaged")
    )
    #expect(!error.localizedDescription.contains(fallback.detail))
  }

  @Test("snapshot backend reports unsupported snapshot version")
  func snapshotBackendReportsUnsupportedSnapshotVersion() async throws {
    let snapshotURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("unsupported-watch-\(UUID().uuidString)")
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    try FileManager.default.createDirectory(
      at: snapshotURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let unsupportedSnapshot = Data("""
      {
        "version": 999,
        "generated_at": "2026-05-24T12:00:00Z",
        "storage_generation": 0,
        "focus_filter_revision": 0,
        "workspace_instance_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "local_change_sequence": 1,
        "timezone": "UTC",
        "stats": {
          "focus_count": 0,
          "overdue_count": 0,
          "due_today_count": 0
        },
        "briefing": null,
        "focus_tasks": [],
        "habits": [],
        "today_tasks": [],
        "lists": [],
        "list_stats": []
      }
      """.utf8)
    let envelope = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      snapshotData: unsupportedSnapshot)
    try envelope.wireData().write(to: snapshotURL, options: [.atomic])
    defer { try? FileManager.default.removeItem(at: snapshotURL.deletingLastPathComponent()) }
    let store = LorvexWatchStore(snapshotURL: snapshotURL)

    await store.refresh()

    #expect(store.primaryTask == nil)
    #expect(store.currentFocus == nil)
    #expect(store.snapshotStatusText == "Update Lorvex to sync")
    guard
      let error = store.error as? LorvexWatchSnapshotError,
      case .unavailable(let fallback) = error
    else {
      Issue.record("Expected snapshot fallback error")
      return
    }
    #expect(fallback.reason == .unsupportedVersion)
  }

  @Test("multiple refreshes are idempotent")
  func multipleRefreshesAreIdempotent() async throws {
    let service = try await makeSeededInMemoryCore()
    try await seedWatchFocus(in: service, date: "2026-05-24", title: "Idempotent task")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()
    let firstTitle = store.primaryTask?.title

    await store.refresh()
    let secondTitle = store.primaryTask?.title

    #expect(firstTitle == secondTitle)
  }

  @Test("core backend exposes writable completion without unavailable reason")
  func coreBackendCompletionHasNoUnavailableReason() async throws {
    let service = try await makeSeededInMemoryCore()
    try await seedWatchFocus(in: service, date: "2026-05-24", title: "Writable watch task")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    #expect(store.canCompletePrimaryTask == true)
    #expect(store.canDeferPrimaryTask == true)
    #expect(store.canRemovePrimaryTaskFromFocus == true)
    #expect(store.completionUnavailableReason == nil)
    #expect(store.focusMutationUnavailableReason == nil)
  }

  @Test("core backend captures a new inbox task")
  func coreBackendCapturesTask() async throws {
    let service = try await makeSeededInMemoryCore()
    let store = LorvexWatchStore(core: service)

    store.captureTitle = "  Capture from watch  "
    #expect(store.canCaptureTask == true)

    await store.captureTask()
    let today = try await service.loadToday()

    #expect(today.tasks.contains { $0.title == "Capture from watch" })
    #expect(store.captureTitle == "")
    #expect(store.error == nil)
  }

  @Test("core refresh failure clears stale watch state")
  func coreRefreshFailureClearsStaleState() async throws {
    let service = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    let task = try await service.createTask(title: "Do not show stale watch focus", notes: "")
    _ = try await service.addToCurrentFocus(
      date: "2026-05-24",
      taskIDs: [task.id],
      briefing: nil,
      timezone: "UTC"
    )
    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    #expect(store.primaryTask?.id == task.id)

    service.loadCurrentFocusError = .unsupportedOperation("Current focus unavailable.")
    await store.refresh()

    #expect(store.currentFocus == nil)
    #expect(store.primaryTask == nil)
    #expect(store.focusTasks.isEmpty)
    #expect(store.snapshotStatusText == "Snapshot unavailable")
    #expect(store.error != nil)
  }

  @Test("overlapping refresh coalesces and does not clobber succeeded state")
  func overlappingRefreshCoalescesWithoutClobber() async throws {
    let service = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    let task = try await service.createTask(title: "Keep me visible", notes: "")
    _ = try await service.addToCurrentFocus(
      date: "2026-05-24", taskIDs: [task.id], briefing: nil, timezone: "UTC")

    let gate = WatchRefreshGate()
    service.loadCurrentFocusGate = { await gate.gate() }

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")

    // Refresh A enters `loadCurrentFocus` and blocks on the gate.
    let a = Task { await store.refresh() }
    await gate.waitUntilEntered()

    // A is mid-flight. B must coalesce (record pending) rather than run a second
    // concurrent body — so only A has entered `loadCurrentFocus` so far.
    await store.refresh()
    #expect(service.loadCurrentFocusCallCount == 1)

    // Releasing A lets it finish; `refreshPending` reruns the body exactly once,
    // producing clean populated state rather than a clobbered mix.
    await gate.release()
    await a.value

    #expect(service.loadCurrentFocusCallCount == 2)
    #expect(store.primaryTask?.id == task.id)
    #expect(store.currentFocus != nil)
    #expect(store.error == nil)
    #expect(store.isLoading == false)
  }

  @Test("blank watch capture draft does not write")
  func blankCaptureDraftDoesNotWrite() async throws {
    let service = try await makeSeededInMemoryCore()
    let before = try await service.loadToday().tasks.count
    let store = LorvexWatchStore(core: service)

    store.captureTitle = "   "
    await store.captureTask()
    let after = try await service.loadToday().tasks.count

    #expect(store.canCaptureTask == false)
    #expect(after == before)
    #expect(store.error == nil)
  }
}

private func writeWatchStoreReplica(_ snapshot: WidgetSnapshot, to url: URL) throws {
  let workspace = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  let reboundSnapshot = WidgetSnapshot(
    version: snapshot.version,
    generatedAt: snapshot.generatedAt,
    storageGeneration: snapshot.storageGeneration,
    focusFilterRevision: snapshot.focusFilterRevision,
    workspaceInstanceID: workspace,
    localChangeSequence: snapshot.localChangeSequence,
    timezone: snapshot.timezone,
    logicalDay: snapshot.logicalDay,
    stats: snapshot.stats,
    briefing: snapshot.briefing,
    focusTasks: snapshot.focusTasks,
    habits: snapshot.habits,
    todayTasks: snapshot.todayTasks,
    lists: snapshot.lists,
    listStats: snapshot.listStats)
  let envelope = try LorvexWatchReplicaEnvelope(
    workspaceInstanceID: workspace,
    snapshotData: JSONEncoder().encode(reboundSnapshot))
  try envelope.wireData().write(to: url, options: [.atomic])
}

/// Async barrier for the overlapping-refresh test: blocks the *first*
/// `loadCurrentFocus` at a controllable point (signaling entry first) so the
/// test can request a second refresh while the first is provably in flight.
/// Later invocations pass through so the coalesced rerun is not blocked.
private actor WatchRefreshGate {
  private var invocations = 0
  private var didEnter = false
  private var released = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var blockedContinuation: CheckedContinuation<Void, Never>?

  func gate() async {
    invocations += 1
    guard invocations == 1 else { return }
    didEnter = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    guard !released else { return }
    await withCheckedContinuation { blockedContinuation = $0 }
  }

  func waitUntilEntered() async {
    if didEnter { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func release() {
    released = true
    blockedContinuation?.resume()
    blockedContinuation = nil
  }
}
