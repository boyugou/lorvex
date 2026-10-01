import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexMobile
@testable import LorvexWatch

@MainActor
private final class RecordingReplicaPublisher: WatchReplicaPublishing {
  var envelopes: [LorvexWatchReplicaEnvelope] = []
  func publish(replicaEnvelope: LorvexWatchReplicaEnvelope) async {
    envelopes.append(replicaEnvelope)
  }
}

private final class SilentForwarder: LorvexWatchMutationForwarding, @unchecked Sendable {
  func forward(_ mutation: LorvexWatchMutation) async throws {}
}

/// The phone's replica, built from a real core the way the app builds it, must
/// decode on the watch. A core stores its instance id as an uppercase UUID while
/// the envelope fence is canonical lowercase; a replica pairing the two
/// spellings was rejected by the watch on every device, which showed "Today
/// unavailable" forever.
@Suite("Watch replica round trip")
struct WatchReplicaRoundTripTests {
  @Test @MainActor func realCoreReplicaDecodesOnTheWatch() async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    let source = try await core.loadWidgetSnapshotSource(date: nil)
    let snapshot = try await WidgetSnapshotPublisher(
      destination: .init(snapshotURL: nil, reload: {})
    ).publish(source: source)
    let recorder = RecordingReplicaPublisher()
    await WatchSnapshotReplicaMirror(commandService: core, publisher: recorder)
      .publish(snapshot: snapshot)

    let envelope = try #require(recorder.envelopes.last)
    let (_, decoded) = try LorvexWatchReplicaFile.decode(try envelope.wireData())
    #expect(decoded.workspaceInstanceID == envelope.workspaceInstanceID)
  }

  @Test func theWatchAcceptsAnIDSpelledInEitherCase() throws {
    let lower = "ce454839-1a2b-4c3d-8e9f-0123456789ab"
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-09-30T12:00:00.000Z", workspaceInstanceID: lower.uppercased(),
      localChangeSequence: 1, timezone: "UTC", logicalDay: "2026-09-30",
      stats: .init(todayCount: 0, overdueCount: 0, dueTodayCount: 0), briefing: nil, tasks: [])
    let envelope = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: lower, snapshotData: JSONEncoder().encode(snapshot))
    #expect(throws: Never.self) { try LorvexWatchReplicaFile.decode(try envelope.wireData()) }
  }

  /// A task completed on the wrist stays gone across the refresh every wrist
  /// raise runs, while its command still waits for the phone's ACK.
  @Test @MainActor func aPendingCompleteSurvivesTheNextRefresh() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("watch-replica-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let now = Date()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let parts = calendar.dateComponents([.year, .month, .day], from: now)
    let day = String(
      format: "%04d-%02d-%02d", try #require(parts.year), try #require(parts.month),
      try #require(parts.day))
    let workspace = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let first = "11111111-1111-4111-8111-111111111111"
    let second = "22222222-2222-4222-8222-222222222222"
    let snapshot = WidgetSnapshot(
      generatedAt: LorvexDateFormatters.iso8601.string(from: now),
      workspaceInstanceID: workspace, localChangeSequence: 1, timezone: "UTC", logicalDay: day,
      stats: .init(todayCount: 2, overdueCount: 0, dueTodayCount: 0), briefing: nil,
      tasks: [first, second].map {
        WidgetSnapshot.TodayTask(
          id: $0, title: $0, status: "open", dueDate: nil, priority: 1, listID: nil,
          estimatedMinutes: nil)
      })
    let envelope = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: workspace, snapshotData: JSONEncoder().encode(snapshot))
    let url = directory.appendingPathComponent("watch_replica_v1.json")
    try envelope.wireData().write(to: url)

    let store = LorvexWatchStore(snapshotURL: url, now: { now }, mutationForwarder: SilentForwarder())
    await store.refresh()
    #expect(store.tasks.count == 2)

    store.updateDeliveryStatus(LorvexWatchDeliveryStatus(pendingCommands: [
      LorvexWatchPendingCommand(id: "c1", sequence: 1, mutation: .completeTask(id: first))
    ]))
    await store.refresh()
    #expect(store.tasks.map(\.id) == [second])
  }
}
