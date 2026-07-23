import Foundation
import LorvexCore
@testable import LorvexWatch
import LorvexWidgetKitSupport
import Testing

@Suite("LorvexWatch focus queue")
@MainActor
struct LorvexWatchFocusQueueTests {
  @Test("core backend preserves current focus task order")
  func coreBackendPreservesFocusTaskOrder() async throws {
    let service = try await makeSeededInMemoryCore()
    let first = try await service.createTask(title: "First watch focus", notes: "")
    let second = try await service.createTask(title: "Second watch focus", notes: "")
    let completed = try await service.createTask(title: "Completed watch focus", notes: "")
    // A focus plan may only reference active tasks, so the middle task is
    // completed after the plan is saved.
    _ = try await service.setCurrentFocus(
      date: "2026-05-24",
      taskIDs: [first.id, completed.id, second.id],
      briefing: nil,
      timezone: "UTC"
    )
    _ = try await service.completeTask(id: completed.id)

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    #expect(store.focusTasks.map(\.id) == [first.id, second.id])
    #expect(store.primaryTask?.id == first.id)
    let focusIDs = try #require(store.currentFocus?.taskIDs)
    let firstIndex = try #require(focusIDs.firstIndex(of: first.id))
    let secondIndex = try #require(focusIDs.firstIndex(of: second.id))
    #expect(firstIndex < secondIndex)
    #expect(store.error == nil)
  }

  @Test("snapshot backend exposes all open focus tasks")
  func snapshotBackendExposesAllOpenFocusTasks() async throws {
    let snapshotURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-watch-queue-\(UUID().uuidString)")
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    try FileManager.default.createDirectory(
      at: snapshotURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-05-24T12:00:00Z",
      workspaceInstanceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      localChangeSequence: 1,
      timezone: "America/Los_Angeles",
      stats: .init(focusCount: 2, overdueCount: 0, dueTodayCount: 2),
      briefing: "Watch queue",
      focusTasks: [
        .init(
          id: "watch-first",
          title: "First snapshot focus",
          status: LorvexTask.Status.open.rawValue,
          dueDate: "2026-05-24",
          priority: 1,
          listID: nil,
          estimatedMinutes: 15
        ),
        .init(
          id: "watch-completed",
          title: "Completed snapshot focus",
          status: LorvexTask.Status.completed.rawValue,
          dueDate: "2026-05-24",
          priority: 2,
          listID: nil,
          estimatedMinutes: 10
        ),
        .init(
          id: "watch-second",
          title: "Second snapshot focus",
          status: LorvexTask.Status.open.rawValue,
          dueDate: "2026-05-24",
          priority: 3,
          listID: nil,
          estimatedMinutes: 25
        ),
      ]
    )
    let envelope = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      snapshotData: JSONEncoder().encode(snapshot))
    try envelope.wireData().write(to: snapshotURL, options: [.atomic])

    let store = LorvexWatchStore(
      snapshotURL: snapshotURL,
      now: { Date(timeIntervalSince1970: 1_779_624_180) }
    )
    await store.refresh()

    #expect(store.focusTasks.map(\.id) == ["watch-first", "watch-second"])
    #expect(store.primaryTask?.id == "watch-first")
    #expect(store.currentFocus?.taskIDs == ["watch-first", "watch-second"])
    #expect(store.snapshotStatusText == "Synced 3m ago")
    #expect(store.error == nil)
  }

  @Test("Crown queue selection clamps to available tasks")
  func crownQueueSelectionClampsToAvailableTasks() {
    #expect(LorvexWatchQueueSelection.clampedIndex(for: -2, count: 3) == 0)
    #expect(LorvexWatchQueueSelection.clampedIndex(for: 0.6, count: 3) == 1)
    #expect(LorvexWatchQueueSelection.clampedIndex(for: 4, count: 3) == 2)
    #expect(LorvexWatchQueueSelection.clampedIndex(for: 4, count: 0) == 0)
    #expect(LorvexWatchQueueSelection.clampedPosition(4, count: 3) == 2)
  }

  @Test("queue accessibility label includes selected position")
  func queueAccessibilityLabelIncludesSelectedPosition() {
    #expect(
      LorvexWatchQueueSelection.accessibilityLabel(
        title: "Review native watch",
        selectedIndex: 1,
        count: 3
      ) == "Next focus task 2 of 3: Review native watch"
    )
  }

  @Test("visible queue hides the primary task when no session is active")
  func visibleQueueHidesPrimaryTaskWithoutActiveSession() {
    #expect(
      LorvexWatchVisibleQueue.taskIDs(
        focusTaskIDs: ["primary", "second", "third"],
        activeTaskID: nil
      ) == ["second", "third"]
    )
  }

  @Test("visible queue removes the active task instead of blindly dropping the first task")
  func visibleQueueRemovesActiveTaskWhenSessionIsActive() {
    #expect(
      LorvexWatchVisibleQueue.taskIDs(
        focusTaskIDs: ["primary", "active", "third"],
        activeTaskID: "active"
      ) == ["primary", "third"]
    )
  }
}
