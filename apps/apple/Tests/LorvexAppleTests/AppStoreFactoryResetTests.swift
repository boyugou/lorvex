import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexRuntime
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

/// The factory-reset erase contract, now carried by the storage-generation
/// cutover (`SwiftLorvexCoreService.resetManagedStorage`) `performFactoryReset`
/// calls: the managed database delete must surface a real failure (so "Erase
/// Everything" never reports a false success while the DB survives), tolerate
/// a legitimately-absent file and `-wal`/`-shm` sidecars, and bump the durable
/// storage generation so concurrent processes reconnect instead of writing the
/// deleted inode.
@Suite("AppStore factory-reset erase")
struct AppStoreFactoryResetTests {

  private func makeTempDir() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-reset-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  @Test("removes the database and sidecars and bumps the storage generation")
  func removesFilesAndBumpsGeneration() throws {
    let fm = FileManager.default
    let dir = try makeTempDir()
    defer { try? fm.removeItem(at: dir) }
    let db = dir.appendingPathComponent("lorvex.sqlite")
    for path in [db.path, db.path + "-wal", db.path + "-shm"] {
      #expect(fm.createFile(atPath: path, contents: Data("x".utf8)))
    }
    let focusFilterSidecar = db.path + LorvexProductMetadata.focusFilterStateFileSuffix
    #expect(fm.createFile(atPath: focusFilterSidecar, contents: Data("private profile".utf8)))

    try SwiftLorvexCoreService.resetManagedStorage(at: db)

    #expect(!fm.fileExists(atPath: db.path))
    #expect(!fm.fileExists(atPath: db.path + "-wal"))
    #expect(!fm.fileExists(atPath: db.path + "-shm"))
    #expect(!fm.fileExists(atPath: focusFilterSidecar))
    #expect(ManagedStorageGeneration.read(forDatabase: db.path) == 1)
  }

  @Test("factory reset writes a generation-dominating empty widget snapshot")
  func resetSnapshotBarrierRejectsDelayedPrivateWriter() async throws {
    let fm = FileManager.default
    let dir = try makeTempDir()
    defer { try? fm.removeItem(at: dir) }
    let db = dir.appendingPathComponent("db.sqlite")
    let snapshotURL = dir.appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
    #expect(fm.createFile(atPath: db.path, contents: Data("database".utf8)))

    let privateSnapshot = WidgetSnapshot(
      generatedAt: "2026-05-23T23:59:59Z",
      storageGeneration: 0,
      workspaceInstanceID: "11111111-1111-4111-8111-111111111111",
      localChangeSequence: 99,
      timezone: "UTC",
      logicalDay: "2026-05-23",
      stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 0),
      briefing: "private briefing",
      focusTasks: [
        .init(
          id: "private", title: "private title", status: "open",
          dueDate: nil, priority: 1, listID: nil, estimatedMinutes: nil)
      ])
    let fileStore = WidgetSnapshotFileStore()
    _ = try await fileStore.write(privateSnapshot, to: snapshotURL)

    let outcome = try await fileStore.replaceForFactoryReset(
      at: snapshotURL,
      managedDatabasePath: db.path,
      logicalDay: "2026-05-24"
    ) {
      try SwiftLorvexCoreService.resetManagedStorage(at: db)
    }
    let barrier = outcome.barrier

    #expect(outcome.publicationSucceeded)
    #expect(barrier.storageGeneration == 1)
    #expect(barrier.logicalDay == "2026-05-24")
    #expect(barrier.focusTasks.isEmpty)
    #expect(barrier.todayTasks.isEmpty)
    #expect(barrier.habits.isEmpty)
    #expect(barrier.lists.isEmpty)
    #expect(barrier.briefing == nil)

    let delayedWinner = try await fileStore.write(
      privateSnapshot, to: snapshotURL, managedDatabasePath: db.path)
    #expect(delayedWinner == barrier)
    guard case .snapshot(let loaded) = WidgetSnapshotLoader().loadSnapshot(at: snapshotURL) else {
      Issue.record("Expected the reset barrier to remain readable")
      return
    }
    #expect(loaded == barrier)
    #expect(!loaded.focusTasks.contains { $0.title == "private title" })
  }

  @Test("a widget barrier failure is post-reset and cannot roll back the canonical wipe")
  func barrierFailureReturnsOutcomeAfterStorageReset() async throws {
    let fm = FileManager.default
    let dir = try makeTempDir()
    defer { try? fm.removeItem(at: dir) }
    let db = dir.appendingPathComponent("db.sqlite")
    #expect(fm.createFile(atPath: db.path, contents: Data("database".utf8)))
    // Data cannot atomically replace a directory. This injects the publication
    // failure after `resetStorage` has returned without relying on permissions.
    let invalidSnapshotDestination = dir.appendingPathComponent(
      "snapshot-is-a-directory", isDirectory: true)
    try fm.createDirectory(at: invalidSnapshotDestination, withIntermediateDirectories: true)

    let outcome = try await WidgetSnapshotFileStore().replaceForFactoryReset(
      at: invalidSnapshotDestination,
      managedDatabasePath: db.path,
      logicalDay: "1970-01-01"
    ) {
      try SwiftLorvexCoreService.resetManagedStorage(at: db)
    }

    #expect(!outcome.publicationSucceeded)
    #expect(outcome.barrier.storageGeneration == 1)
    #expect(!fm.fileExists(atPath: db.path))
    #expect(ManagedStorageGeneration.read(forDatabase: db.path) == 1)
  }

  @MainActor
  @Test("post-reset widget failure still resets settings replaces core and refreshes")
  func postResetWidgetFailureCompletesLifecycle() async throws {
    let fm = FileManager.default
    let dir = try makeTempDir()
    defer { try? fm.removeItem(at: dir) }
    let db = dir.appendingPathComponent("db.sqlite")
    let originalCore = SwiftLorvexCoreService(databasePath: db.path)
    _ = try await originalCore.createTask(title: "Private task", notes: "")
    #expect(fm.fileExists(atPath: db.path))

    let invalidSnapshotDestination = dir.appendingPathComponent(
      "snapshot-is-a-directory", isDirectory: true)
    try fm.createDirectory(at: invalidSnapshotDestination, withIntermediateDirectories: true)
    let reloadCounter = FactoryResetCounter()
    let publisher = FactoryResetFailingWidgetPublisher(
      target: WidgetSnapshotFactoryResetTarget(
        snapshotURL: invalidSnapshotDestination,
        managedDatabasePath: db.path,
        reload: { reloadCounter.increment() }))
    let replacementCore = try makeInMemoryCore()
    let store = AppStore(
      core: originalCore,
      widgetSnapshotPublisher: publisher,
      cloudSyncMode: .live)

    let suite = "lorvex.factory-reset.lifecycle.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettingsStore(defaults: defaults, environment: [:])
    settings.cloudSyncMode = .live
    settings.setupCompleted = true
    settings.eventKitEnabled = true

    await AppStore.$factoryResetDependencies.withValue(
      .init(databaseURL: db, makeReplacementCore: { replacementCore })
    ) {
      await store.performFactoryReset(settings: settings)
    }

    #expect(!fm.fileExists(atPath: db.path))
    #expect(settings.cloudSyncMode == .off)
    #expect(settings.setupCompleted == false)
    #expect(settings.eventKitEnabled == false)
    #expect(store.cloudSyncMode == .off)
    #expect(store.core as? SwiftLorvexCoreService === replacementCore)
    #expect(store.isLocalFactoryResetRunning == false)
    #expect(store.errorMessage?.contains("widget cache") == true)
    #expect(reloadCounter.value == 1)
  }

  @MainActor
  @Test("an unresolved managed path does not silently disable live sync")
  func unresolvedPathPreservesRuntimeSyncMode() async throws {
    let core = try makeInMemoryCore()
    let store = AppStore(core: core, cloudSyncMode: .live)
    let suite = "lorvex.factory-reset.path-failure.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettingsStore(defaults: defaults, environment: [:])
    settings.cloudSyncMode = .live

    await AppStore.$factoryResetDependencies.withValue(
      .init(databaseURL: nil, makeReplacementCore: { core })
    ) {
      await store.performFactoryReset(settings: settings)
    }

    #expect(store.cloudSyncMode == .live)
    #expect(settings.cloudSyncMode == .live)
    #expect(store.core as? SwiftLorvexCoreService === core)
    #expect(store.isLocalFactoryResetRunning == false)
  }

  @MainActor
  @Test("pre-reset derived cleanup failure rebuilds surfaces from the intact database")
  func cleanupFailureRestoresClearedSurfaces() async throws {
    let fm = FileManager.default
    let dir = try makeTempDir()
    defer { try? fm.removeItem(at: dir) }
    let db = dir.appendingPathComponent("db.sqlite")
    let core = SwiftLorvexCoreService(databasePath: db.path)
    let privateTask = try await core.createTask(title: "Still canonical", notes: "")
    let taskIndexer = FactoryResetTaskIndexer()
    let store = AppStore(
      core: core,
      taskSearchIndexer: taskIndexer,
      contentSearchIndexer: FactoryResetFailingContentIndexer(),
      cloudSyncMode: .live)
    let suite = "lorvex.factory-reset.cleanup-failure.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettingsStore(defaults: defaults, environment: [:])
    settings.cloudSyncMode = .live
    settings.setupCompleted = true

    await AppStore.$factoryResetDependencies.withValue(
      .init(databaseURL: db, makeReplacementCore: { core })
    ) {
      await store.performFactoryReset(settings: settings)
    }

    #expect(fm.fileExists(atPath: db.path))
    #expect(settings.cloudSyncMode == .live)
    #expect(settings.setupCompleted)
    #expect(store.cloudSyncMode == .live)
    let replacements = await taskIndexer.replacements
    #expect(replacements.first == [])
    #expect(replacements.last == [privateTask.id])
  }

  @MainActor
  @Test("factory-reset derived cleanup clears Spotlight notifications snoozes and badge")
  func clearsEveryLocalDerivedSurface() async throws {
    let taskIndexer = FactoryResetTaskIndexer()
    let contentIndexer = FactoryResetContentIndexer()
    let taskReminders = FactoryResetTaskReminderScheduler()
    let habitReminders = FactoryResetHabitReminderScheduler()
    let deliveredNotifications = FactoryResetDeliveredNotificationRecorder()
    let badge = FactoryResetBadgeRecorder()
    let store = AppStore(
      core: try makeInMemoryCore(),
      taskSearchIndexer: taskIndexer,
      contentSearchIndexer: contentIndexer,
      taskReminderScheduler: taskReminders,
      habitReminderScheduler: habitReminders,
      widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
      clearDeliveredNotificationsForFactoryReset: {
        await deliveredNotifications.recordClear()
      },
      setBadge: { await badge.record($0) })

    try await store.clearDerivedSurfacesForFactoryReset()

    #expect(await taskIndexer.replacements == [[]])
    #expect(await contentIndexer.listReplacements == [[]])
    #expect(await contentIndexer.habitReplacements == [[]])
    #expect(await contentIndexer.reviewReplacementCount == 1)
    #expect(await contentIndexer.calendarReplacements == [[]])
    #expect(await taskReminders.replacements == [[]])
    let snoozeKeepSets = await taskReminders.snoozeKeepSets
    #expect(snoozeKeepSets.count == 1)
    #expect(snoozeKeepSets.first?.isEmpty == true)
    #expect(await habitReminders.replacements == [[]])
    #expect(await deliveredNotifications.clearCount == 1)
    #expect(await badge.values == [0])
  }

  @Test("a missing main file is not an erase failure, but still cuts over")
  func missingMainFileDoesNotThrow() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let db = dir.appendingPathComponent("absent.sqlite")

    // Nothing created: an already-erased / fresh install must not fail the
    // erase — and the generation still advances so any process that created
    // the file concurrently reconnects.
    try SwiftLorvexCoreService.resetManagedStorage(at: db)
    #expect(ManagedStorageGeneration.read(forDatabase: db.path) == 1)
  }

  @Test("a main file that cannot be deleted surfaces the failure by throwing")
  func lockedMainFileThrows() throws {
    let fm = FileManager.default
    let dir = try makeTempDir()
    let db = dir.appendingPathComponent("lorvex.sqlite")
    #expect(fm.createFile(atPath: db.path, contents: Data("x".utf8)))
    // Removing a file needs write permission on its parent directory; a
    // read-only parent makes the erase fail deterministically.
    try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
    defer {
      try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
      try? fm.removeItem(at: dir)
    }

    #expect(throws: (any Error).self) {
      try SwiftLorvexCoreService.resetManagedStorage(at: db)
    }
    // The file must still be there — a false-success erase is exactly the bug.
    #expect(fm.fileExists(atPath: db.path))
  }

  /// H7: `performFactoryReset` wipes the DB and then rebuilds the core, whose
  /// `replaceCore → refresh → publishAppleSyncSurfaces → runCloudSyncCycle` runs
  /// against the freshly-empty database. `runCloudSyncCycle` guards on the
  /// RUNTIME `cloudSyncMode`; `settings.resetToDefaults()` flips only the
  /// PERSISTED mode. Without turning the runtime mode off, the fresh database has
  /// no SQLite traversal state, so the cycle starts a nil-token baseline against
  /// the still-existing CloudKit generation and repopulates the data the user
  /// just erased. The fix sets the runtime
  /// mode to `.off` before the cutover, so the post-reset refresh's cycle no-ops.
  ///
  /// This drives that runtime-mode guard directly: with sync off a refresh must
  /// not start a cycle (nothing can repopulate), and the same refresh with the
  /// runtime mode left live DOES start one — proving the runtime mode, not the
  /// persisted one, is the gate the fix flips. The end-to-end managed-storage
  /// cutover is covered by the `resetManagedStorage` cases above and cannot be
  /// driven hermetically against the real managed store.
  @MainActor
  @Test("runtime cloudSyncMode .off makes the post-reset refresh a no-op that cannot repopulate")
  func factoryResetRuntimeSyncOffPreventsPostResetRepopulatingCycle() async throws {
    func makeCoordinator() -> CloudSyncEngineCoordinator {
      CloudSyncEngineCoordinator(
        accountChecker: StubAccountStatusChecker(availability: .available),
        pusher: RecordingRecordPusher(),
        fetcher: StubRemoteChangeFetcher(records: []),
        accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
        accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
    }

    // Post-reset runtime state the fix installs: sync OFF. A refresh (the
    // post-reset trigger) must not start a cloud sync cycle.
    let offStore = AppStore(
      core: try makeInMemoryCore(),
      widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
      cloudSyncMode: .off,
      cloudSyncCoordinator: makeCoordinator())

    await offStore.refresh()

    #expect(
      offStore.cloudSyncPacing.lastAttemptAt == nil,
      "with runtime sync off, the post-reset refresh must not start a cloud sync cycle")
    #expect(offStore.lastCloudSyncCycleReport == nil)

    // Discriminator: with the runtime mode left `.live` (the pre-fix state), the
    // guarded cycle DOES run — so it is the runtime mode, not the persisted one,
    // that gates repopulation.
    let liveStore = AppStore(
      core: try makeInMemoryCore(),
      widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
      cloudSyncMode: .live,
      cloudSyncCoordinator: makeCoordinator())

    await liveStore.runCloudSyncCycle()

    #expect(
      liveStore.cloudSyncPacing.lastAttemptAt != nil,
      "with runtime sync live the cycle starts — exactly the state the fix turns off before the wipe")
  }
}

private struct FactoryResetInjectedWidgetFailure: Error {}

private final class FactoryResetCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}

private struct FactoryResetFailingWidgetPublisher: WidgetSnapshotPublishing {
  let target: WidgetSnapshotFactoryResetTarget

  var factoryResetTarget: WidgetSnapshotFactoryResetTarget? { target }

  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    throw FactoryResetInjectedWidgetFailure()
  }

  func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?
  ) async throws -> WidgetSnapshot {
    throw FactoryResetInjectedWidgetFailure()
  }
}

private actor FactoryResetTaskIndexer: TaskSearchIndexing {
  private(set) var replacements: [[String]] = []
  func replaceIndexedTasks(_ tasks: [LorvexTask]) async throws {
    replacements.append(tasks.map(\.id))
  }
}

private actor FactoryResetContentIndexer: ContentSearchIndexing {
  private(set) var listReplacements: [[String]] = []
  private(set) var habitReplacements: [[String]] = []
  private(set) var reviewReplacementCount = 0
  private(set) var calendarReplacements: [[String]] = []

  func replaceIndexedLists(_ lists: [LorvexList]) async throws {
    listReplacements.append(lists.map(\.id))
  }
  func replaceIndexedHabits(_ habits: [LorvexHabit]) async throws {
    habitReplacements.append(habits.map(\.id))
  }
  func replaceIndexedDailyReview(_ review: DailyReviewEntry?) async throws {
    #expect(review == nil)
    reviewReplacementCount += 1
  }
  func replaceIndexedCalendarEvents(_ events: [CalendarTimelineEvent]) async throws {
    calendarReplacements.append(events.map(\.eventID))
  }
}

private struct FactoryResetInjectedCleanupFailure: Error {}

private actor FactoryResetFailingContentIndexer: ContentSearchIndexing {
  func replaceIndexedLists(_ lists: [LorvexList]) async throws {
    throw FactoryResetInjectedCleanupFailure()
  }
  func replaceIndexedHabits(_ habits: [LorvexHabit]) async throws {}
  func replaceIndexedDailyReview(_ review: DailyReviewEntry?) async throws {}
  func replaceIndexedCalendarEvents(_ events: [CalendarTimelineEvent]) async throws {}
}

private actor FactoryResetTaskReminderScheduler: TaskReminderScheduling {
  private(set) var replacements: [[String]] = []
  private(set) var snoozeKeepSets: [Set<String>] = []

  func scheduleReminders(_ reminders: [ScheduledTaskReminder]) async
    -> TaskReminderScheduleReport
  {
    replacements.append(reminders.map(\.identifier))
    return .scheduled(reminders.count)
  }

  func cancelSnoozes(keepingActiveTaskIDs activeTaskIDs: Set<LorvexTask.ID>) async {
    snoozeKeepSets.append(activeTaskIDs)
  }
}

private actor FactoryResetHabitReminderScheduler: HabitReminderScheduling {
  private(set) var replacements: [[String]] = []
  func replaceScheduledHabitReminders(
    for occurrences: [DueHabitReminderOccurrence]
  ) async -> TaskReminderScheduleReport {
    replacements.append(occurrences.map(\.policy.id))
    return .scheduled(occurrences.count)
  }
}

private actor FactoryResetBadgeRecorder {
  private(set) var values: [Int] = []
  func record(_ value: Int) { values.append(value) }
}

private actor FactoryResetDeliveredNotificationRecorder {
  private(set) var clearCount = 0
  func recordClear() { clearCount += 1 }
}
