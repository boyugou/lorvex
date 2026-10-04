import Foundation
import LorvexCore
@testable import LorvexWatch
import LorvexWidgetKitSupport
import Testing

// MARK: - Tests

@Suite("LorvexWatchStore")
@MainActor
struct LorvexWatchStoreTests {

  @Test("refresh lists Today's tasks from a live core")
  func refreshListsTodayTasks() async throws {
    let service = try makeInMemoryCore()
    let title = "Design watch UI"
    let task = try await seedWatchTodayTask(in: service, date: "2026-05-24", title: title)

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    #expect(store.tasks.map(\.id) == [task.id])
    #expect(store.lead(at: Date()) == nil, "an untimed, unstarted task is listed, not led")
    #expect(store.moreCount == 0)
    #expect(store.snapshotStatusText == "Live from Lorvex")
    #expect(store.error == nil)
  }

  @Test("refresh with nothing on Today leaves the list empty")
  func refreshWithEmptyToday() async throws {
    let store = LorvexWatchStore(core: try makeInMemoryCore(), logicalDayOverride: "2026-05-24")

    await store.refresh()

    #expect(store.tasks.isEmpty)
    #expect(store.lead(at: Date()) == nil)
    #expect(store.error == nil)
  }

  @Test("refresh lists the habits that are on for the day and leaves a resting one out")
  func refreshLeavesOutAHabitOnItsRestDay() async throws {
    let service = try makeInMemoryCore()
    _ = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily,
      milestoneTarget: nil)
    _ = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2, 4]),
      milestoneTarget: nil)

    // 2026-05-26 is a Tuesday.
    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-26")
    await store.refresh()

    #expect(store.habits.map(\.name) == ["Water"])
  }

  @Test("refresh lists a monthly habit from its day and a times-per-week habit until its quota is met")
  func refreshListsPeriodHabitsWhileTheyAreOpen() async throws {
    let service = try makeInMemoryCore()
    _ = try await service.createHabit(
      name: "Rent", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly", dayOfMonth: 20),
      milestoneTarget: nil)
    _ = try await service.createHabit(
      name: "Taxes", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly", dayOfMonth: 28),
      milestoneTarget: nil)
    _ = try await service.createHabit(
      name: "Run", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 2),
      milestoneTarget: nil)
    let swim = try await service.createHabit(
      name: "Swim", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 1),
      milestoneTarget: nil)
    // The week of Monday 2026-05-25 already holds Swim's one check-in.
    _ = try await service.completeHabit(id: swim.id, date: "2026-05-25")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-26")
    await store.refresh()

    #expect(store.habits.map(\.name) == ["Rent", "Run"])
  }

  @Test("isLoading is false after refresh completes")
  func isLoadingFalseAfterRefresh() async throws {
    let service = try await makeSeededInMemoryCore()
    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")

    await store.refresh()

    #expect(store.isLoading == false)
  }

  @Test("snapshot backend loads Today's list read-only")
  func snapshotBackendLoadsTodayReadOnly() async throws {
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
      stats: .init(todayCount: 3, overdueCount: 0, dueTodayCount: 1),
      briefing: nil,
      tasks: [
        .init(
          id: "watch-task",
          title: "Review Apple companion",
          status: LorvexTask.Status.open.rawValue,
          dueDate: "2026-05-24",
          priority: 1,
          listID: nil,
          estimatedMinutes: 25,
          scheduledStart: "09:00",
          scheduledEnd: "09:30"
        )
      ]
    )
    try writeWatchStoreReplica(snapshot, to: snapshotURL)

    let store = LorvexWatchStore(
      snapshotURL: snapshotURL,
      now: { Date(timeIntervalSince1970: 1_779_624_180) }
    )
    await store.refresh()

    let task = try #require(store.tasks.first)
    #expect(store.tasks.count == 1)
    #expect(task.id == "watch-task")
    #expect(task.title == "Review Apple companion")
    #expect(task.priority == .p1)
    #expect(task.estimatedMinutes == 25)
    #expect(store.savedTimes["watch-task"] == 540..<570)
    // The phone sends the head of a long list with the whole list's length.
    #expect(store.moreCount == 2)
    // The snapshot is three minutes old; the system words the age.
    let synced = "Synced \(LorvexDateFormatters.elapsed(seconds: 180))"
    #expect(store.snapshotStatusText == synced)
    #expect(
      LorvexWatchStore.snapshotStatusLabel(
        snapshot,
        now: Date(timeIntervalSince1970: 1_779_624_180)
      ) == synced)
    #expect(store.canMutateTasks == false)
    #expect(store.canCaptureTask == false)
    #expect(store.taskActionUnavailableReason == "Open Lorvex on iPhone to change tasks.")
    #expect(store.captureUnavailableReason == "Open Lorvex on iPhone or Mac to capture new tasks.")
    #expect(store.error == nil)

    await store.completeTask(id: task.id)
    #expect(store.error != nil)
    await store.startTask(id: task.id)
    #expect(store.error != nil)
    await store.cancelTask(id: task.id)
    #expect(store.error != nil)
    await store.deferTaskToTomorrow(id: task.id)
    #expect(store.error != nil)
    // Nothing was forwarded, so nothing changed optimistically either.
    #expect(store.tasks.map(\.id) == ["watch-task"])
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

    #expect(store.tasks.isEmpty)
    #expect(store.snapshotStatusText == "Open Lorvex to sync")
    #expect(store.error is LorvexWatchSnapshotError)
    #expect(store.canMutateTasks == false)
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

    #expect(store.tasks.isEmpty)
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
          defaultValue: "Watch data unavailable: %@",
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
          "today_count": 0,
          "overdue_count": 0,
          "due_today_count": 0
        },
        "briefing": null,
        "tasks": [],
        "habits": [],
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

    #expect(store.tasks.isEmpty)
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
    try await seedWatchTodayTask(in: service, date: "2026-05-24", title: "Idempotent task")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()
    let first = store.tasks.map(\.id)

    await store.refresh()

    #expect(!first.isEmpty)
    #expect(store.tasks.map(\.id) == first)
  }

  @Test("core backend offers task actions without an unavailable reason")
  func coreBackendTaskActionsHaveNoUnavailableReason() async throws {
    let service = try await makeSeededInMemoryCore()
    try await seedWatchTodayTask(in: service, date: "2026-05-24", title: "Writable watch task")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    #expect(store.canMutateTasks == true)
    #expect(store.taskActionUnavailableReason == nil)
  }

  @Test("core backend captures a new inbox task")
  func coreBackendCapturesTask() async throws {
    let service = try await makeSeededInMemoryCore()
    let store = LorvexWatchStore(core: service)

    store.captureTitle = "  Capture from watch  "
    #expect(store.canCaptureTask == true)

    await store.captureTask()
    // Captured work is undated, so it lands in the inbox rather than the day pool.
    let open = try await service.listTasks(
      status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)

    #expect(open.tasks.contains { $0.title == "Capture from watch" })
    #expect(store.captureTitle == "")
    #expect(store.error == nil)
  }

  @Test("core refresh failure clears stale watch state")
  func coreRefreshFailureClearsStaleState() async throws {
    let service = StubCoreService(preview: try await makeSeededInMemoryCore())
    let task = try await seedWatchTodayTask(
      in: service, date: "2026-05-24", title: "Do not show a stale watch list")
    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    #expect(store.tasks.contains { $0.id == task.id })

    service.loadTodayError = .unsupportedOperation("Today unavailable.")
    await store.refresh()

    #expect(store.tasks.isEmpty)
    #expect(store.savedTimes.isEmpty)
    #expect(store.logicalDay == nil)
    #expect(store.snapshotStatusText == "Snapshot unavailable")
    #expect(store.error != nil)
  }

  @Test("overlapping refresh coalesces and does not clobber succeeded state")
  func overlappingRefreshCoalescesWithoutClobber() async throws {
    let service = StubCoreService(preview: try await makeSeededInMemoryCore())
    let task = try await seedWatchTodayTask(
      in: service, date: "2026-05-24", title: "Keep me visible")

    let gate = WatchRefreshGate()
    service.loadTodayGate = { await gate.gate() }

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")

    // Refresh A enters `loadToday` and blocks on the gate.
    let a = Task { await store.refresh() }
    await gate.waitUntilEntered()

    // A is mid-flight. B must coalesce (record pending) rather than run a second
    // concurrent body — so only A has entered `loadToday` so far.
    await store.refresh()
    #expect(service.loadTodayCallCount == 1)

    // Releasing A lets it finish; `refreshPending` reruns the body exactly once,
    // producing clean populated state rather than a clobbered mix.
    await gate.release()
    await a.value

    #expect(service.loadTodayCallCount == 2)
    #expect(store.tasks.contains { $0.id == task.id })
    #expect(store.error == nil)
    #expect(store.isLoading == false)
  }

  @Test("snapshot backend reads which tasks wait on an unfinished task")
  func snapshotBackendReadsBlockedTasks() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-watch-\(UUID().uuidString)")
    let snapshotURL = directory.appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-05-24T12:00:00Z",
      timezone: "America/Los_Angeles",
      stats: .init(todayCount: 2, overdueCount: 0, dueTodayCount: 0),
      briefing: nil,
      tasks: [
        .init(
          id: "waiting", title: "Book the venue", status: LorvexTask.Status.open.rawValue,
          dueDate: nil, priority: 2, listID: nil, estimatedMinutes: nil, isBlocked: true),
        .init(
          id: "free", title: "Draft the agenda", status: LorvexTask.Status.open.rawValue,
          dueDate: nil, priority: 2, listID: nil, estimatedMinutes: nil),
      ]
    )
    try writeWatchStoreReplica(snapshot, to: snapshotURL)

    let store = LorvexWatchStore(
      snapshotURL: snapshotURL,
      now: { Date(timeIntervalSince1970: 1_779_624_180) }
    )
    await store.refresh()

    #expect(store.tasks.map(\.id) == ["waiting", "free"])
    #expect(store.blockedTaskIDs == ["waiting"])
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
    tasks: snapshot.tasks,
    habits: snapshot.habits,
    lists: snapshot.lists,
    listStats: snapshot.listStats)
  let envelope = try LorvexWatchReplicaEnvelope(
    workspaceInstanceID: workspace,
    snapshotData: JSONEncoder().encode(reboundSnapshot))
  try envelope.wireData().write(to: url, options: [.atomic])
}

/// Async barrier for the overlapping-refresh test: blocks the *first*
/// `loadToday` at a controllable point (signaling entry first) so the
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
