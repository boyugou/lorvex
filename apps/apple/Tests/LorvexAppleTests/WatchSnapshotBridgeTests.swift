import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWatch

@Suite("Watch replica bridge")
struct WatchSnapshotBridgeTests {
  private let workspaceA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  private let workspaceB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

  private func snapshot(
    generatedAt: String, title: String, localChangeSequence: Int = 1,
    storageGeneration: Int = 0,
    workspaceInstanceID: String? = nil
  ) -> WidgetSnapshot {
    WidgetSnapshot(
      generatedAt: generatedAt,
      storageGeneration: storageGeneration,
      workspaceInstanceID: workspaceInstanceID ?? workspaceA,
      localChangeSequence: localChangeSequence,
      timezone: "UTC",
      stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 0),
      briefing: nil,
      focusTasks: [
        .init(
          id: "11111111-1111-4111-8111-111111111111",
          title: title,
          status: "open",
          dueDate: nil,
          priority: 1,
          listID: nil,
          estimatedMinutes: nil)
      ])
  }

  private func replicaData(
    snapshot: WidgetSnapshot,
    workspaceInstanceID: String? = nil
  ) throws -> Data {
    let workspace = workspaceInstanceID ?? snapshot.workspaceInstanceID
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
    return try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: workspace,
      snapshotData: JSONEncoder().encode(reboundSnapshot)
    ).wireData()
  }

  private func tempContainer() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("WatchReplicaBridge-\(UUID().uuidString)", isDirectory: true)
  }

  private func replicaURL(in container: URL) -> URL {
    container
      .appendingPathComponent("Lorvex", isDirectory: true)
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
  }

  @Test("receiver atomically persists one strict replica envelope")
  func receiverWritesEnvelope() async throws {
    let temp = tempContainer()
    defer { try? FileManager.default.removeItem(at: temp) }
    let receiver = LorvexWatchSnapshotReceiver(reloadAllTimelines: {})
    let data = try replicaData(
      snapshot: snapshot(generatedAt: "2026-05-27T10:00:00Z", title: "Ship feature"))

    #expect(try await receiver.writeReplicaEnvelope(data, to: temp))

    let committed = try LorvexWatchReplicaEnvelope.decodeWireData(
      Data(contentsOf: replicaURL(in: temp)))
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: committed.snapshotData)
    #expect(committed.workspaceInstanceID == workspaceA)
    #expect(decoded.focusTasks.map(\.title) == ["Ship feature"])
  }

  @Test("accepted replica refreshes complication and foreground store")
  func applyingReplicaNotifiesForegroundSurfaces() async throws {
    let temp = tempContainer()
    defer { try? FileManager.default.removeItem(at: temp) }
    let counters = LockedCounters()
    let receiver = LorvexWatchSnapshotReceiver(
      onSnapshotWritten: { counters.incrementStoreRefreshes() },
      reloadAllTimelines: { counters.incrementTimelineReloads() })

    try await receiver.applyReplicaData(
      replicaData(
        snapshot: snapshot(generatedAt: "2026-05-27T10:00:00Z", title: "Ship")),
      to: temp)

    #expect(counters.timelineReloads == 1)
    #expect(counters.storeRefreshes == 1)
  }

  @Test("older snapshot in the same workspace cannot overwrite newer")
  func staleSnapshotDoesNotOverwriteNewer() async throws {
    let temp = tempContainer()
    defer { try? FileManager.default.removeItem(at: temp) }
    let receiver = LorvexWatchSnapshotReceiver(reloadAllTimelines: {})
    let newer = try replicaData(
      snapshot: snapshot(
        generatedAt: "2026-05-27T10:00:00Z", title: "Newer",
        localChangeSequence: 2))
    let older = try replicaData(
      snapshot: snapshot(
        generatedAt: "2099-05-27T10:00:00Z", title: "Older",
        localChangeSequence: 1))

    #expect(try await receiver.writeReplicaEnvelope(newer, to: temp))
    #expect(try await receiver.writeReplicaEnvelope(older, to: temp) == false)

    let envelope = try LorvexWatchReplicaEnvelope.decodeWireData(
      Data(contentsOf: replicaURL(in: temp)))
    let committed = try JSONDecoder().decode(WidgetSnapshot.self, from: envelope.snapshotData)
    #expect(committed.focusTasks.map(\.title) == ["Newer"])
  }

  @Test("replacement workspace advances fence even with an older snapshot timestamp")
  func replacementWorkspaceWinsTimestampOrdering() async throws {
    let temp = tempContainer()
    defer { try? FileManager.default.removeItem(at: temp) }
    let receiver = LorvexWatchSnapshotReceiver(reloadAllTimelines: {})
    let oldWorkspace = try replicaData(
      snapshot: snapshot(
        generatedAt: "2026-05-27T10:00:05Z", title: "Old DB",
        workspaceInstanceID: workspaceA),
      workspaceInstanceID: workspaceA)
    let replacement = try replicaData(
      snapshot: snapshot(
        generatedAt: "2026-05-27T09:00:00Z", title: "Reset DB",
        workspaceInstanceID: workspaceB),
      workspaceInstanceID: workspaceB)

    #expect(try await receiver.writeReplicaEnvelope(oldWorkspace, to: temp))
    #expect(try await receiver.writeReplicaEnvelope(replacement, to: temp))

    let committed = try LorvexWatchReplicaEnvelope.decodeWireData(
      Data(contentsOf: replicaURL(in: temp)))
    #expect(committed.workspaceInstanceID == workspaceB)
  }

  @Test("a pre-reset replica cannot overwrite a newer storage generation")
  func preResetReplicaCannotResurrectOnWatch() async throws {
    let temp = tempContainer()
    defer { try? FileManager.default.removeItem(at: temp) }
    let receiver = LorvexWatchSnapshotReceiver(reloadAllTimelines: {})
    let postReset = try replicaData(
      snapshot: snapshot(
        generatedAt: "2026-05-27T09:00:00Z", title: "Fresh empty generation",
        localChangeSequence: 0, storageGeneration: 8,
        workspaceInstanceID: workspaceB),
      workspaceInstanceID: workspaceB)
    let stalePreReset = try replicaData(
      snapshot: snapshot(
        generatedAt: "2099-05-27T10:00:00Z", title: "Erased private title",
        localChangeSequence: 99_999, storageGeneration: 7,
        workspaceInstanceID: workspaceA),
      workspaceInstanceID: workspaceA)

    #expect(try await receiver.writeReplicaEnvelope(postReset, to: temp))
    #expect(try await receiver.writeReplicaEnvelope(stalePreReset, to: temp) == false)

    let envelope = try LorvexWatchReplicaEnvelope.decodeWireData(
      Data(contentsOf: replicaURL(in: temp)))
    let committed = try JSONDecoder().decode(WidgetSnapshot.self, from: envelope.snapshotData)
    #expect(committed.storageGeneration == 8)
    #expect(committed.focusTasks.map(\.title) == ["Fresh empty generation"])
  }

  @Test("an older callback task cannot roll back a newer workspace")
  func callbackTaskReorderingCannotRollBackWorkspace() async throws {
    let temp = tempContainer()
    defer { try? FileManager.default.removeItem(at: temp) }
    let receiver = LorvexWatchSnapshotReceiver(reloadAllTimelines: {})
    let oldWorkspace = try replicaData(
      snapshot: snapshot(
        generatedAt: "2026-05-27T10:00:05Z", title: "Old callback",
        workspaceInstanceID: workspaceA),
      workspaceInstanceID: workspaceA)
    let newWorkspace = try replicaData(
      snapshot: snapshot(
        generatedAt: "2026-05-27T09:00:00Z", title: "Current callback",
        workspaceInstanceID: workspaceB),
      workspaceInstanceID: workspaceB)

    // Simulate unstructured task scheduling entering the actor in reverse
    // callback order: callback 2 lands before callback 1 begins its actor work.
    #expect(
      try await receiver.applyReplicaData(
        newWorkspace, ingressSequence: 2, to: temp))
    #expect(
      try await receiver.applyReplicaData(
        oldWorkspace, ingressSequence: 1, to: temp) == false)

    let committed = try LorvexWatchReplicaEnvelope.decodeWireData(
      Data(contentsOf: replicaURL(in: temp)))
    let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: committed.snapshotData)
    #expect(committed.workspaceInstanceID == workspaceB)
    #expect(snapshot.focusTasks.map(\.title) == ["Current callback"])
  }

  @Test("dropped stale replica does not refresh either surface")
  func staleReplicaSkipsSideEffects() async throws {
    let temp = tempContainer()
    defer { try? FileManager.default.removeItem(at: temp) }
    let counters = LockedCounters()
    let receiver = LorvexWatchSnapshotReceiver(
      onSnapshotWritten: { counters.incrementStoreRefreshes() },
      reloadAllTimelines: { counters.incrementTimelineReloads() })

    try await receiver.applyReplicaData(
      replicaData(snapshot: snapshot(generatedAt: "2026-05-27T10:00:05Z", title: "Newer")),
      to: temp)
    try await receiver.applyReplicaData(
      replicaData(
        snapshot: snapshot(
          generatedAt: "2099-05-27T10:00:00Z", title: "Older",
          localChangeSequence: 0)),
      to: temp)

    #expect(counters.timelineReloads == 1)
    #expect(counters.storeRefreshes == 1)
  }

  @Test("receiver ignores foreign application context")
  func receiverIgnoresForeignApplicationContext() async {
    let receiver = LorvexWatchSnapshotReceiver(reloadAllTimelines: {})
    #expect(await receiver.handle(applicationContext: ["mutation": "anything"]) == false)
  }

  @Test("receiver fails closed when App Group is unavailable")
  func receiverDoesNotConsumeWithoutContainer() async throws {
    let receiver = LorvexWatchSnapshotReceiver(
      fileManager: FixedContainerFileManager(containerURL: nil),
      reloadAllTimelines: {})
    let data = try replicaData(
      snapshot: snapshot(generatedAt: "2026-05-27T10:00:00Z", title: "No container"))

    #expect(
      await receiver.handle(applicationContext: [
        LorvexWatchConnectivityKey.replicaEnvelopeV1: data
      ]) == false)
  }

  @Test("receiver does not consume a replica when atomic write fails")
  func receiverDoesNotConsumeWhenWriteFails() async throws {
    let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("WatchReplicaBridge-file-\(UUID().uuidString)")
    try Data().write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }
    let receiver = LorvexWatchSnapshotReceiver(
      fileManager: FixedContainerFileManager(containerURL: tempFile),
      reloadAllTimelines: {})
    let data = try replicaData(
      snapshot: snapshot(generatedAt: "2026-05-27T10:00:00Z", title: "Write fails"))

    #expect(
      await receiver.handle(applicationContext: [
        LorvexWatchConnectivityKey.replicaEnvelopeV1: data
      ]) == false)
  }

  @Test("replica transport key is shared and versioned")
  func keyConstantIsShared() {
    #expect(
      LorvexWatchConnectivityKey.replicaEnvelopeV1
        == "lorvex.watchReplicaEnvelope.v1")
  }
}

private final class LockedCounters: @unchecked Sendable {
  private let lock = NSLock()
  private var timelineReloadCount = 0
  private var storeRefreshCount = 0

  var timelineReloads: Int { lock.withLock { timelineReloadCount } }
  var storeRefreshes: Int { lock.withLock { storeRefreshCount } }

  func incrementTimelineReloads() {
    lock.withLock { timelineReloadCount += 1 }
  }

  func incrementStoreRefreshes() {
    lock.withLock { storeRefreshCount += 1 }
  }
}

private final class FixedContainerFileManager: FileManager, @unchecked Sendable {
  private let fixedContainerURL: URL?

  init(containerURL: URL?) {
    self.fixedContainerURL = containerURL
    super.init()
  }

  override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL?
  {
    fixedContainerURL
  }
}
