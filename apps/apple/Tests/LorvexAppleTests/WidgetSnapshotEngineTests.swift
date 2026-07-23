import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

/// Unit tests for the shared `WidgetSnapshotPublisher` engine + its
/// `WidgetSnapshotFileStore`, over a temp directory — mirroring the per-platform
/// publisher tests but exercising the one engine every surface now routes
/// through.
@Suite("Widget snapshot engine")
struct WidgetSnapshotEngineTests {
  private func snapshotURL(in tempDirectory: URL) -> URL {
    tempDirectory
      .appendingPathComponent("Lorvex", isDirectory: true)
      .appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  }

  private func makeToday(taskID: String, title: String) -> TodaySnapshot {
    TodaySnapshot(
      focusTitle: "Today",
      summary: "",
      tasks: [
        makePublisherWidgetTask(
          id: taskID,
          title: title,
          priority: .p1,
          dueDate: nil,
          estimatedMinutes: 15
        )
      ],
      localChangeSequence: 1
    )
  }

  @Test("writes a readable snapshot atomically and reloads only after the write")
  func writesReadableSnapshotThenReloads() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-write-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let snapshotExistedAtReload = EngineLockedBox(false)
    let reloadCount = EngineLockedBox(0)
    let destination = WidgetSnapshotPublisher.Destination(
      snapshotURL: url,
      reload: {
        snapshotExistedAtReload.set(FileManager.default.fileExists(atPath: url.path))
        reloadCount.mutate { $0 += 1 }
      }
    )
    let engine = WidgetSnapshotPublisher(
      destination: destination,
      projector: WidgetSnapshotProjector(now: { Date(timeIntervalSince1970: 1_779_465_600) })
    )

    let published = try await engine.publish(
      today: makeToday(taskID: "task-engine", title: "Write via engine"),
      currentFocus: nil
    )

    guard case .snapshot(let loaded) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
      Issue.record("Expected the engine to write a readable snapshot")
      return
    }
    #expect(loaded == published)
    #expect(loaded.focusTasks.map(\.id) == ["task-engine"])
    #expect(reloadCount.value == 1)
    #expect(snapshotExistedAtReload.value)
  }

  @Test("a nil snapshot URL skips the write but still reloads and returns the projection")
  func nilURLSkipsWriteButReloads() async throws {
    let reloadCount = EngineLockedBox(0)
    let destination = WidgetSnapshotPublisher.Destination(
      snapshotURL: nil,
      reload: { reloadCount.mutate { $0 += 1 } }
    )
    let engine = WidgetSnapshotPublisher(
      destination: destination,
      projector: WidgetSnapshotProjector(now: { Date(timeIntervalSince1970: 1_779_465_600) })
    )

    let published = try await engine.publish(
      today: makeToday(taskID: "task-noop", title: "No disk write"),
      currentFocus: nil
    )

    #expect(published.focusTasks.map(\.id) == ["task-noop"])
    #expect(reloadCount.value == 1)
  }

  @Test("mirror receives the full projected snapshot value, carrying lists through")
  func mirrorReceivesSnapshotWithLists() async throws {
    let mirrored = EngineLockedBox<WidgetSnapshot?>(nil)
    let destination = WidgetSnapshotPublisher.Destination(
      snapshotURL: nil,
      reload: {},
      mirror: { snapshot in mirrored.set(snapshot) }
    )
    let engine = WidgetSnapshotPublisher(
      destination: destination,
      projector: WidgetSnapshotProjector(now: { Date(timeIntervalSince1970: 1_779_465_600) })
    )
    let lists = ListCatalogSnapshot(lists: [
      LorvexList(
        id: "list-1",
        name: "Home",
        color: nil,
        icon: "🏠",
        description: nil,
        openCount: 0,
        totalCount: 0,
        updatedAt: "2026-05-23T00:00:00Z"
      )
    ])

    let published = try await engine.publish(
      today: makeToday(taskID: "task-mirror", title: "Mirror me"),
      currentFocus: nil,
      habitCatalog: nil,
      lists: lists
    )

    let received = try #require(mirrored.value)
    #expect(received == published)
    #expect(received.lists.map(\.id) == ["list-1"])
  }

  @Test("refresh loads today/focus/habits/lists from core and reloads once")
  func refreshLoadsFromCore() async throws {
    let core = try await makeSeededInMemoryCore()
    let task = try await core.createTask(title: "Loaded from core", notes: "")
    _ = try await core.createHabit(name: "Stretch", cue: nil, targetCount: 1)

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-refresh-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let reloadCount = EngineLockedBox(0)
    let destination = WidgetSnapshotPublisher.Destination(
      snapshotURL: url,
      reload: { reloadCount.mutate { $0 += 1 } }
    )
    let engine = WidgetSnapshotPublisher(destination: destination)

    let published = try await engine.refresh(core: core, today: "2026-05-23")

    #expect(published.todayTasks.contains { $0.id == task.id })
    #expect(!published.habits.isEmpty)
    #expect(reloadCount.value == 1)
    guard case .snapshot(let loaded) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
      Issue.record("Expected refresh to write a readable snapshot")
      return
    }
    #expect(loaded == published)
  }

  private func snapshot(
    generatedAt: String,
    focusTaskID: String,
    storageGeneration: Int = 0,
    workspaceInstanceID: String = "11111111-1111-4111-8111-111111111111",
    logicalDay: String = "2026-05-23",
    localChangeSequence: Int
  ) -> WidgetSnapshot {
    WidgetSnapshot(
      generatedAt: generatedAt,
      storageGeneration: storageGeneration,
      workspaceInstanceID: workspaceInstanceID,
      localChangeSequence: localChangeSequence,
      timezone: "UTC",
      logicalDay: logicalDay,
      stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 0),
      briefing: nil,
      focusTasks: [
        .init(
          id: focusTaskID, title: "Focus", status: "open",
          dueDate: nil, priority: 1, listID: nil, estimatedMinutes: nil)
      ],
      habits: [],
      todayTasks: []
    )
  }

  @Test("an older logical day cannot overwrite a newer day at the same database revision")
  func logicalDayRejectsDelayedPreMidnightProjection() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-logical-day-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let store = WidgetSnapshotFileStore()
    let postMidnight = snapshot(
      generatedAt: "2026-05-24T00:00:01Z",
      focusTaskID: "new-day",
      logicalDay: "2026-05-24",
      localChangeSequence: 7)
    let delayedPreMidnight = snapshot(
      generatedAt: "2099-05-24T00:00:02Z",
      focusTaskID: "old-day",
      logicalDay: "2026-05-23",
      localChangeSequence: 7)

    _ = try await store.write(postMidnight, to: url)
    let winner = try await store.write(delayedPreMidnight, to: url)

    #expect(winner == postMidnight)
    guard case .snapshot(let loaded) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
      Issue.record("Expected the post-midnight snapshot to remain readable")
      return
    }
    #expect(loaded == postMidnight)
  }

  @Test("source publication uses its captured logical day rather than projection time")
  func sourcePublicationPreservesCapturedLogicalDay() async throws {
    let source = WidgetSnapshotSource(
      storageGeneration: 0,
      logicalDay: "2026-05-23",
      timezone: "Pacific/Kiritimati",
      today: makeToday(taskID: "captured-day", title: "Captured before midnight"),
      currentFocus: nil,
      habits: nil,
      lists: nil,
      stats: nil)
    let publisher = WidgetSnapshotPublisher(
      destination: .init(snapshotURL: nil, reload: {}),
      projector: WidgetSnapshotProjector(
        now: { Date(timeIntervalSince1970: 1_779_552_001) }))

    let snapshot = try await publisher.publish(source: source)

    #expect(snapshot.logicalDay == "2026-05-23")
    #expect(snapshot.timezone == "Pacific/Kiritimati")
  }

  /// A slow publish carrying older state must not overwrite a newer snapshot
  /// already committed to the same URL. Writing the older snapshot after the
  /// newer one — the reversed-completion race the per-URL write serializer
  /// guards against — leaves the newer snapshot on disk.
  @Test("a stale snapshot written after a newer one to the same URL is dropped")
  func staleWriteDoesNotClobberNewer() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-stale-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let store = WidgetSnapshotFileStore()
    let newer = snapshot(
      generatedAt: "2026-05-27T10:00:00Z", focusTaskID: "newer",
      localChangeSequence: 2)
    let older = snapshot(
      generatedAt: "2099-05-27T10:00:00Z", focusTaskID: "older",
      localChangeSequence: 1)

    _ = try await store.write(newer, to: url)
    let winner = try await store.write(older, to: url)

    guard case .snapshot(let loaded) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
      Issue.record("Expected a readable snapshot on disk")
      return
    }
    #expect(loaded.generatedAt == newer.generatedAt)
    #expect(loaded.focusTasks.map(\.id) == ["newer"])
    #expect(winner == newer)
  }

  /// The stale-check and atomic replace form one cross-process critical section.
  /// Proceeding without the lock would let an older process overwrite a newer
  /// derived cache, so lock acquisition is fail-closed and leaves disk untouched.
  @Test("a publish fails closed when another holder pins the publish lock")
  func publishFailsClosedWhenLockIsHeld() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-lock-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    let lockFd = open(url.path + ".publish-lock", O_CREAT | O_RDWR, 0o644)
    #expect(lockFd >= 0)
    #expect(flock(lockFd, LOCK_EX | LOCK_NB) == 0)
    defer { _ = close(lockFd) }

    let store = WidgetSnapshotFileStore(lockTimeout: 0.05, lockRetryInterval: 0.005)
    let published = snapshot(
      generatedAt: "2026-05-27T10:00:00Z", focusTaskID: "held-lock",
      localChangeSequence: 3)
    do {
      _ = try await store.write(published, to: url)
      Issue.record("Expected the publish to fail when its serialization lock is unavailable")
    } catch let error as WidgetSnapshotFileStoreError {
      #expect(error == .publishLockUnavailable)
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("a post-reset snapshot outranks every pre-reset workspace snapshot")
  func storageGenerationPreventsResetResurrection() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-generation-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let store = WidgetSnapshotFileStore()
    let postReset = snapshot(
      generatedAt: "2026-05-27T10:00:01Z",
      focusTaskID: "post-reset",
      storageGeneration: 8,
      workspaceInstanceID: "22222222-2222-4222-8222-222222222222",
      localChangeSequence: 0)
    let stalePreReset = snapshot(
      generatedAt: "2099-05-27T10:00:00Z",
      focusTaskID: "private-pre-reset-title",
      storageGeneration: 7,
      workspaceInstanceID: "11111111-1111-4111-8111-111111111111",
      localChangeSequence: 99_999)

    _ = try await store.write(postReset, to: url)
    let winner = try await store.write(stalePreReset, to: url)

    #expect(winner == postReset)
    guard case .snapshot(let loaded) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
      Issue.record("Expected the post-reset snapshot to remain readable")
      return
    }
    #expect(loaded == postReset)
    #expect(!loaded.focusTasks.contains { $0.title == "private-pre-reset-title" })
  }

  @Test("a malformed file cannot pin the cache with a forged high ordering key")
  func malformedExistingSnapshotIsReplaced() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-malformed-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(
      """
      {"version":3,"storage_generation":999,"focus_filter_revision":999,
       "workspace_instance_id":"11111111-1111-4111-8111-111111111111",
       "local_change_sequence":999999}
      """.utf8
    ).write(to: url, options: .atomic)

    let valid = snapshot(
      generatedAt: "2026-05-27T10:00:01Z", focusTaskID: "valid",
      localChangeSequence: 1)
    let winner = try await WidgetSnapshotFileStore().write(valid, to: url)

    #expect(winner == valid)
    guard case .snapshot(let loaded) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
      Issue.record("Expected the malformed high-key file to be replaced")
      return
    }
    #expect(loaded == valid)
  }

  @Test("a rejected stale projection reloads and mirrors the actual disk winner")
  func rejectedProjectionPropagatesCurrentWinner() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-winner-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let newer = snapshot(
      generatedAt: "2026-05-27T10:00:01Z", focusTaskID: "newer",
      localChangeSequence: 2)
    _ = try await WidgetSnapshotFileStore().write(newer, to: url)

    let mirrored = EngineLockedBox<WidgetSnapshot?>(nil)
    let reloadCount = EngineLockedBox(0)
    let engine = WidgetSnapshotPublisher(
      destination: .init(
        snapshotURL: url,
        reload: { reloadCount.mutate { $0 += 1 } },
        mirror: { mirrored.set($0) }),
      projector: WidgetSnapshotProjector(now: { Date(timeIntervalSince1970: 1_779_465_600) }))
    let staleSource = WidgetSnapshotSource(
      storageGeneration: 0,
      logicalDay: "2026-05-23",
      timezone: "UTC",
      today: TodaySnapshot(
        focusTitle: "Today", summary: "",
        tasks: [
          makePublisherWidgetTask(
            id: "older", title: "Older", priority: .p1,
            dueDate: nil, estimatedMinutes: nil)
        ],
        workspaceInstanceID: "11111111-1111-4111-8111-111111111111",
        localChangeSequence: 1),
      currentFocus: nil,
      habits: nil,
      lists: nil,
      stats: nil)

    let returned = try await engine.publish(source: staleSource)

    #expect(returned == newer)
    #expect(mirrored.value == newer)
    #expect(reloadCount.value == 1)
  }

  /// An equal-or-newer snapshot still overwrites: the guard drops only strictly
  /// older writes, so a re-emitted snapshot in the same second (equal timestamp)
  /// and a genuinely newer one both land.
  @Test("an equal-or-newer snapshot overwrites the one on disk")
  func equalOrNewerWriteOverwrites() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-newer-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let store = WidgetSnapshotFileStore()
    try await store.write(
      snapshot(
        generatedAt: "2026-05-27T10:00:00Z", focusTaskID: "first",
        localChangeSequence: 1),
      to: url)
    try await store.write(
      snapshot(
        generatedAt: "2026-05-27T10:00:00Z", focusTaskID: "same-second",
        localChangeSequence: 1),
      to: url)
    try await store.write(
      snapshot(
        generatedAt: "2026-05-27T10:00:05Z", focusTaskID: "later",
        localChangeSequence: 2),
      to: url)

    guard case .snapshot(let loaded) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
      Issue.record("Expected a readable snapshot on disk")
      return
    }
    #expect(loaded.focusTasks.map(\.id) == ["later"])
  }

  @Test("engine applies a persisted focus filter before projecting")
  func appliesPersistedFocusFilter() async throws {
    let core = try await makeSeededInMemoryCore()
    let focusTask = try await core.createTask(title: "Focused", notes: "")
    let otherTask = try await core.createTask(title: "Unfocused", notes: "")
    _ = try await core.addToCurrentFocus(
      date: "2026-05-23",
      taskIDs: [focusTask.id],
      briefing: nil,
      timezone: "UTC"
    )

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-focus-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }
    let store = FocusFilterStore(
      managedDatabasePath: tempDirectory.appendingPathComponent("db.sqlite").path)
    _ = try await store.save(
      FocusFilterConfiguration(activeProfileID: "Deep Work", showNonFocusTasks: false)
    )

    let destination = WidgetSnapshotPublisher.Destination(
      snapshotURL: nil,
      focusFilterStore: store,
      reload: {}
    )
    let engine = WidgetSnapshotPublisher(destination: destination)

    let published = try await engine.refresh(core: core, today: "2026-05-23")

    #expect(published.focusTasks.contains { $0.id == focusTask.id })
    #expect(!published.focusTasks.contains { $0.id == otherTask.id })
  }

  @Test("a delayed pre-Focus publisher cannot overwrite the newer Focus revision")
  func focusRevisionRejectsDelayedPreTransitionProjection() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-engine-focus-race-\(UUID().uuidString)", isDirectory: true)
    let url = snapshotURL(in: tempDirectory)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }
    let store = FocusFilterStore(
      managedDatabasePath: tempDirectory.appendingPathComponent("db.sqlite").path)
    let workspace = "11111111-1111-4111-8111-111111111111"
    let focusTask = makePublisherWidgetTask(
      id: "focus", title: "Focus", priority: .p1, dueDate: nil, estimatedMinutes: nil)
    let otherTask = makePublisherWidgetTask(
      id: "other", title: "Other", priority: .p2, dueDate: nil, estimatedMinutes: nil)
    let source = WidgetSnapshotSource(
      storageGeneration: 0,
      logicalDay: "2026-05-23",
      timezone: "UTC",
      today: TodaySnapshot(
        focusTitle: "Today", summary: "", tasks: [focusTask, otherTask],
        workspaceInstanceID: workspace, localChangeSequence: 7),
      currentFocus: CurrentFocusPlan(
        date: "2026-05-23", taskIDs: [focusTask.id], briefing: nil,
        timezone: "UTC", localChangeSequence: 7),
      habits: nil,
      lists: nil,
      stats: nil)

    // The old projection loads revision 0, then pauses inside projection. While
    // paused, the system Focus transition atomically mints revision 1 and a
    // second publisher commits that state for the same database revision.
    let oldProjectionPaused = EngineGate()
    let releaseOldProjection = EngineGate()
    let oldPublisher = WidgetSnapshotPublisher(
      destination: .init(snapshotURL: url, focusFilterStore: store, reload: {}),
      projector: WidgetSnapshotProjector(now: {
        oldProjectionPaused.signal()
        _ = releaseOldProjection.wait(timeout: 30)
        return Date(timeIntervalSince1970: 1_779_465_600)
      }))
    let oldTask = Task { try await oldPublisher.publish(source: source) }
    #expect(oldProjectionPaused.wait(timeout: 30))

    let active = try await store.save(
      FocusFilterConfiguration(activeProfileID: "Deep Work", showNonFocusTasks: true))
    #expect(active.revision == 1)
    let freshPublisher = WidgetSnapshotPublisher(
      destination: .init(snapshotURL: url, focusFilterStore: store, reload: {}),
      projector: WidgetSnapshotProjector(now: {
        Date(timeIntervalSince1970: 1_779_465_601)
      }))
    let fresh = try await freshPublisher.publish(source: source)
    #expect(fresh.focusFilterRevision == 1)
    #expect(fresh.focusTasks.map(\.id).contains("other"))

    releaseOldProjection.signal()
    let oldCallWinner = try await oldTask.value
    #expect(oldCallWinner == fresh)
    guard case .snapshot(let diskWinner) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
      Issue.record("Expected the revision-1 Focus snapshot to remain on disk")
      return
    }
    #expect(diskWinner == fresh)
    #expect(diskWinner.focusFilterRevision == 1)
  }
}

/// Minimal thread-safe box so the `@Sendable` engine closures can record what
/// they observed without tripping Swift 6 concurrency capture rules.
final class EngineLockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value

  init(_ value: Value) { stored = value }

  var value: Value {
    lock.lock(); defer { lock.unlock() }
    return stored
  }

  func set(_ newValue: Value) {
    lock.lock(); defer { lock.unlock() }
    stored = newValue
  }

  func mutate(_ transform: (inout Value) -> Void) {
    lock.lock(); defer { lock.unlock() }
    transform(&stored)
  }
}

/// Synchronous test gate wrapped behind a Sendable type so Swift 6 async tests
/// do not call `DispatchSemaphore.wait` (explicitly unavailable from async
/// contexts) directly. The projector callback itself is synchronous.
final class EngineGate: @unchecked Sendable {
  private let semaphore = DispatchSemaphore(value: 0)

  func signal() {
    semaphore.signal()
  }

  func wait(timeout: TimeInterval) -> Bool {
    semaphore.wait(timeout: .now() + timeout) == .success
  }
}
