import Foundation
import LorvexCore
@testable import LorvexWatch
import LorvexWidgetKitSupport
import Testing

/// The wrist lists Today the way the phone does: every task still to do,
/// started tasks first, then by priority and due date. A saved time never
/// reorders the list; it only decides which task leads while it runs.
@Suite("LorvexWatch Today list")
@MainActor
struct LorvexWatchTodayListTests {
  @Test("core backend lists Today in Today's order without finished tasks")
  func coreBackendKeepsTodayOrder() async throws {
    let service = try makeInMemoryCore()
    let first = try await seedWatchTodayTask(
      in: service, date: "2026-05-24", title: "First watch task", priority: .p1)
    let finished = try await seedWatchTodayTask(
      in: service, date: "2026-05-24", title: "Finished watch task", priority: .p2)
    let last = try await seedWatchTodayTask(
      in: service, date: "2026-05-24", title: "Last watch task", priority: .p3)
    _ = try await service.completeTask(id: finished.id)

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    #expect(store.tasks.map(\.id) == [first.id, last.id])
    #expect(store.lead(at: Date()) == nil, "nothing is timed or started yet")

    // A started task leads whatever its priority.
    _ = try await service.startTask(id: last.id)
    await store.refresh()

    #expect(store.tasks.map(\.id) == [last.id, first.id])
    #expect(store.error == nil)
  }

  @Test("snapshot backend keeps every actionable task in the phone's order")
  func snapshotBackendKeepsPhoneOrder() async throws {
    let snapshotURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-watch-today-\(UUID().uuidString)")
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    try FileManager.default.createDirectory(
      at: snapshotURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: snapshotURL.deletingLastPathComponent()) }
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-05-24T12:00:00Z",
      workspaceInstanceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      localChangeSequence: 1,
      timezone: "America/Los_Angeles",
      stats: .init(todayCount: 2, overdueCount: 0, dueTodayCount: 2),
      briefing: nil,
      tasks: [
        .init(
          id: "watch-started",
          title: "Started snapshot task",
          status: LorvexTask.Status.inProgress.rawValue,
          dueDate: "2026-05-24",
          priority: 3,
          listID: nil,
          estimatedMinutes: 15
        ),
        .init(
          id: "watch-completed",
          title: "Completed snapshot task",
          status: LorvexTask.Status.completed.rawValue,
          dueDate: "2026-05-24",
          priority: 2,
          listID: nil,
          estimatedMinutes: 10
        ),
        .init(
          id: "watch-open",
          title: "Open snapshot task",
          status: LorvexTask.Status.open.rawValue,
          dueDate: "2026-05-24",
          priority: 1,
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

    #expect(store.tasks.map(\.id) == ["watch-started", "watch-open"])
    #expect(store.tasks.first?.status == .inProgress)
    #expect(store.moreCount == 0)
    #expect(store.snapshotStatusText == "Synced 3m ago")
    #expect(store.error == nil)
  }
}
