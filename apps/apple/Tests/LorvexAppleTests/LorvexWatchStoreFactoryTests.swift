import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWatch

@Suite("LorvexWatchStoreFactory")
@MainActor
struct LorvexWatchStoreFactoryTests {
  @Test("factory prefers App Group snapshot when available")
  func factoryPrefersSnapshotWhenAvailable() async throws {
    let snapshotURL = try makeWatchFactorySnapshotURL(title: "Snapshot task")
    let factory = LorvexWatchStoreFactory(
      snapshotURLProvider: { _ in snapshotURL },
      now: { Date(timeIntervalSince1970: 1_779_624_180) }
    )

    let store = factory.makeStore()
    await store.refresh()

    #expect(store.tasks.first?.title == "Snapshot task")
    #expect(store.snapshotStatusText == "Synced 3m ago")
  }

  @Test("factory does not fall back to a writable core when snapshot is unavailable")
  func factoryReturnsUnavailableSnapshotWhenSnapshotURLIsUnavailable() async throws {
    let factory = LorvexWatchStoreFactory(
      snapshotURLProvider: { _ in nil }
    )

    let store = factory.makeStore()
    await store.refresh()

    #expect(store.tasks.isEmpty)
    #expect(store.canWrite == false)
    #expect(store.snapshotStatusText == "Open Lorvex to sync")
    #expect(store.error != nil)
  }
}

private func makeWatchFactorySnapshotURL(title: String) throws -> URL {
  let snapshotURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-watch-factory-\(UUID().uuidString)")
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
    stats: .init(todayCount: 1, overdueCount: 0, dueTodayCount: 1),
    briefing: nil,
    tasks: [
      .init(
        id: "watch-factory-task",
        title: title,
        status: LorvexTask.Status.open.rawValue,
        dueDate: "2026-05-24",
        priority: 1,
        listID: nil,
        estimatedMinutes: 25
      )
    ]
  )
  let envelope = try LorvexWatchReplicaEnvelope(
    workspaceInstanceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    snapshotData: JSONEncoder().encode(snapshot))
  try envelope.wireData().write(to: snapshotURL, options: [.atomic])
  return snapshotURL
}
