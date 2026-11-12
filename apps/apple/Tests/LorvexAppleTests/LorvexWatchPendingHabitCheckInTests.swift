import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWatch

private final class DroppingForwarder: LorvexWatchMutationForwarding, @unchecked Sendable {
  func forward(_ mutation: LorvexWatchMutation) async throws {}
}

/// A habit checked on the wrist while the phone is out of reach must stay
/// checked across the refresh every wrist raise runs. A check-in is not
/// idempotent, so it is put back only over a replica the watch received before
/// it journaled the check-in: that replica cannot hold it.
@Suite("Watch habit check-ins waiting for the phone")
@MainActor
struct LorvexWatchPendingHabitCheckInTests {
  private static let workspace = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  private static let habit = "33333333-3333-4333-8333-333333333333"
  /// 2026-05-25 12:00:00 UTC.
  private static let now = Date(timeIntervalSince1970: 1_779_710_400)
  private static let day = "2026-05-25"
  /// When the watch received the replica, a minute before `now`.
  private static let received = now.addingTimeInterval(-60)

  /// A store reading a replica that holds one habit counted `target` times a
  /// day with `completed` check-ins, received at ``received``.
  private func makeStore(completed: Int, target: Int) async throws -> (LorvexWatchStore, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("watch-habit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let snapshot = WidgetSnapshot(
      generatedAt: LorvexDateFormatters.iso8601.string(from: Self.received),
      workspaceInstanceID: Self.workspace, localChangeSequence: 1, timezone: "UTC",
      logicalDay: Self.day,
      stats: .init(todayCount: 0, overdueCount: 0, dueTodayCount: 0), briefing: nil, tasks: [],
      habits: [
        .init(id: Self.habit, name: "Water", icon: nil, completedToday: completed, target: target)
      ])
    let envelope = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: Self.workspace, snapshotData: JSONEncoder().encode(snapshot))
    let url = directory.appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    try envelope.wireData().write(to: url)
    try FileManager.default.setAttributes([.modificationDate: Self.received], ofItemAtPath: url.path)
    let now = Self.now
    let store = LorvexWatchStore(
      snapshotURL: url, now: { now }, mutationForwarder: DroppingForwarder())
    await store.refresh()
    return (store, directory)
  }

  private func checkIn(
    _ sequence: Int64, at createdAt: Date, date: String = day
  ) -> LorvexWatchPendingCommand {
    LorvexWatchPendingCommand(
      id: "c\(sequence)", sequence: sequence,
      mutation: .completeHabit(id: Self.habit, date: date), createdAt: createdAt)
  }

  @Test("a check-in journaled after the replica arrived stays across a refresh")
  func aCheckInNewerThanTheReplicaIsPutBack() async throws {
    let (store, directory) = try await makeStore(completed: 0, target: 3)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(store.habits.first?.completedToday == 0)

    store.updateDeliveryStatus(
      LorvexWatchDeliveryStatus(pendingCommands: [
        checkIn(1, at: Self.received.addingTimeInterval(20)),
        checkIn(2, at: Self.received.addingTimeInterval(30)),
      ]))
    await store.refresh()

    #expect(store.habits.first?.completedToday == 2)
  }

  @Test("check-ins put back never pass the habit's target")
  func checkInsPutBackStopAtTheTarget() async throws {
    let (store, directory) = try await makeStore(completed: 1, target: 2)
    defer { try? FileManager.default.removeItem(at: directory) }

    store.updateDeliveryStatus(
      LorvexWatchDeliveryStatus(pendingCommands: [
        checkIn(1, at: Self.received.addingTimeInterval(20)),
        checkIn(2, at: Self.received.addingTimeInterval(30)),
      ]))
    await store.refresh()

    #expect(store.habits.first?.completedToday == 2)
  }

  /// The replica may already hold this check-in (the phone applied it and its
  /// replica reached the watch before its ACK did), so adding it would count
  /// it twice.
  @Test("a check-in journaled before the replica arrived is not added again")
  func aCheckInOlderThanTheReplicaIsLeftToThePhone() async throws {
    let (store, directory) = try await makeStore(completed: 1, target: 3)
    defer { try? FileManager.default.removeItem(at: directory) }

    store.updateDeliveryStatus(
      LorvexWatchDeliveryStatus(pendingCommands: [
        checkIn(1, at: Self.received.addingTimeInterval(-20)),
        // A command whose time is unknown is older than any replica.
        LorvexWatchPendingCommand(
          id: "c2", sequence: 2, mutation: .completeHabit(id: Self.habit, date: Self.day)),
      ]))
    await store.refresh()

    #expect(store.habits.first?.completedToday == 1)
  }

  @Test("a check-in made for another day is not added to the day on screen")
  func aCheckInForAnotherDayIsNotAdded() async throws {
    let (store, directory) = try await makeStore(completed: 0, target: 3)
    defer { try? FileManager.default.removeItem(at: directory) }

    store.updateDeliveryStatus(
      LorvexWatchDeliveryStatus(pendingCommands: [
        checkIn(1, at: Self.received.addingTimeInterval(20), date: "2026-05-24")
      ]))
    await store.refresh()

    #expect(store.habits.first?.completedToday == 0)
  }

  /// Every launch offers the session's last application context again. The
  /// file must keep the date it was first received, or a check-in made since
  /// would read as older than the replica and drop off the screen.
  @Test("the replica already on disk, offered again, keeps its received date")
  func theSameReplicaOfferedAgainKeepsItsReceivedDate() async throws {
    let container = FileManager.default.temporaryDirectory
      .appendingPathComponent("watch-replica-same-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    let snapshot = WidgetSnapshot(
      generatedAt: LorvexDateFormatters.iso8601.string(from: Self.received),
      workspaceInstanceID: Self.workspace, localChangeSequence: 1, timezone: "UTC",
      logicalDay: Self.day,
      stats: .init(todayCount: 0, overdueCount: 0, dueTodayCount: 0), briefing: nil, tasks: [])
    let data = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: Self.workspace, snapshotData: JSONEncoder().encode(snapshot)
    ).wireData()
    let replicaStore = LorvexWatchReplicaStore(appGroupID: "unused")
    let url = try await replicaStore.replicaURL(containerURL: container)

    #expect(try await replicaStore.accept(data, containerURL: container))
    try FileManager.default.setAttributes([.modificationDate: Self.received], ofItemAtPath: url.path)

    #expect(try await replicaStore.accept(data, containerURL: container) == false)
    #expect(LorvexWatchReplicaFile.receivedDate(at: url) == Self.received)
  }
}
