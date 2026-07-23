import Foundation
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import Testing

@Suite("Widget intent snapshot refresher")
struct WidgetIntentSnapshotRefresherTests {
  @Test("writes a fresh snapshot and reloads timelines after an intent mutation")
  func writesFreshSnapshotAndReloads() async throws {
    let core = try await makeSeededInMemoryCore()
    let task = try await core.createTask(title: "Refresh widget intent snapshot", notes: "")
    _ = try await core.completeTask(id: task.id)

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "lorvex-widget-intent-refresh-\(UUID().uuidString)", isDirectory: true)
    let snapshotURL =
      tempDirectory
      .appendingPathComponent("Lorvex", isDirectory: true)
      .appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let reloadCount = LockedBox(0)
    let refresher = WidgetIntentSnapshotRefresher(
      reloadTimelines: { reloadCount.mutate { $0 += 1 } },
      todayString: { "2026-05-23" }
    )

    let published = try await refresher.refresh(core: core, snapshotURL: snapshotURL)

    let loaded = WidgetSnapshotLoader().loadSnapshot(at: snapshotURL)
    guard case .snapshot(let snapshot) = loaded else {
      Issue.record("Expected widget intent refresher to write a readable snapshot")
      return
    }
    #expect(snapshot == published)
    #expect(snapshot.todayTasks.contains { $0.id == task.id } == false)
    #expect(reloadCount.value == 1)
  }

  @Test("includes habits so an interactive tap doesn't blank the Habits widget")
  func refreshIncludesHabits() async throws {
    let core = try await makeSeededInMemoryCore()
    _ = try await core.createHabit(name: "Stretch", cue: nil, targetCount: 1)

    let reloadCount = LockedBox(0)
    let refresher = WidgetIntentSnapshotRefresher(
      reloadTimelines: { reloadCount.mutate { $0 += 1 } },
      todayString: { "2026-05-23" }
    )

    // The refresher rewrites the App-Group snapshot every interactive tap; it
    // must carry the habit catalog or the Habits widget reads back an empty set.
    let snapshot = try await refresher.refresh(core: core, snapshotURL: nil)

    #expect(!snapshot.habits.isEmpty)
    #expect(reloadCount.value == 1)
  }

  @Test("refresh applies persisted focus filter before writing snapshot")
  func refreshAppliesPersistedFocusFilter() async throws {
    let core = try await makeSeededInMemoryCore()
    let focusTask = try await core.createTask(title: "Focus-filtered task", notes: "")
    let otherTask = try await core.createTask(title: "Non-focus task", notes: "")
    _ = try await core.addToCurrentFocus(
      date: "2026-05-23",
      taskIDs: [focusTask.id],
      briefing: nil,
      timezone: "UTC"
    )

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "lorvex-widget-intent-focus-filter-\(UUID().uuidString)", isDirectory: true)
    let focusFilterStore = FocusFilterStore(
      managedDatabasePath: tempDirectory.appendingPathComponent("db.sqlite").path)
    _ = try await focusFilterStore.save(
      FocusFilterConfiguration(activeProfileID: "Deep Work", showNonFocusTasks: false))
    let snapshotURL =
      tempDirectory
      .appendingPathComponent("Lorvex", isDirectory: true)
      .appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let refresher = WidgetIntentSnapshotRefresher(
      focusFilterStore: focusFilterStore,
      reloadTimelines: {},
      todayString: { "2026-05-23" }
    )

    let snapshot = try await refresher.refresh(core: core, snapshotURL: snapshotURL)

    #expect(snapshot.focusTasks.contains { $0.id == focusTask.id })
    #expect(!snapshot.focusTasks.contains { $0.id == otherTask.id })
    guard case .snapshot(let written) = WidgetSnapshotLoader().loadSnapshot(at: snapshotURL) else {
      Issue.record("Expected widget intent refresher to write filtered snapshot")
      return
    }
    #expect(written.focusTasks.map(\.id) == snapshot.focusTasks.map(\.id))
  }

  @Test("widget write intents refresh snapshots and invalidate open app windows")
  func widgetWriteIntentsRefreshSnapshotsAndBroadcastCommittedChanges() throws {
    let files = [
      "Sources/LorvexWidgetIntents/WidgetCompleteTaskIntent.swift",
      "Sources/LorvexWidgetIntents/WidgetDeferTaskIntent.swift",
      "Sources/LorvexWidgetIntents/WidgetCompleteHabitIntent.swift",
    ]

    for path in files {
      let source = try String(contentsOfFile: path, encoding: .utf8)
      #expect(source.contains("WidgetIntentPostCommitCoordinator.live().finish(core: core)"))
    }
  }

  @Test("a post-commit snapshot failure cannot turn an applied habit increment into an error")
  func postCommitSnapshotFailurePreservesAppliedMutation() async throws {
    struct SnapshotFailure: Error, CustomStringConvertible {
      var description: String { "injected snapshot failure" }
    }

    let core = try await makeSeededInMemoryCore()
    let habit = try await core.createHabit(name: "Drink water", cue: nil, targetCount: 3)
    let date = "2026-05-23"
    _ = try await core.completeHabit(id: habit.id, date: date)

    let broadcastCount = LockedBox(0)
    let finisher = WidgetIntentPostCommitCoordinator(
      refresh: { _ in throw SnapshotFailure() },
      broadcast: { broadcastCount.mutate { $0 += 1 } })

    // Nonthrowing by contract: the App Intent must return the already-applied
    // success rather than inviting a retry of the non-idempotent increment.
    await finisher.finish(core: core)

    let stats = try await core.getHabitStats(id: habit.id)
    #expect(stats.totalCompletions == 1)
    #expect(broadcastCount.value == 1)
    let logs = try await core.loadRecentLogs(
      limit: 20, offset: 0, since: nil, levels: nil,
      sources: ["error_log"], redact: false)
    #expect(
      logs.entries.contains {
        $0.origin == "widget.intent.snapshot_refresh"
          && $0.details?.contains("injected snapshot failure") == true
      })
  }

  @Test("mobile file widget publisher wires App Group focus filter store")
  func mobileFileWidgetPublisherWiresFocusFilterStore() throws {
    let source = try String(
      contentsOfFile: "Sources/LorvexMobile/MobileWidgetSnapshotPublishing.swift",
      encoding: .utf8
    )

    #expect(source.contains("SwiftLorvexCoreService.managedDatabasePath()"))
    #expect(source.contains("managedDatabasePath.map(FocusFilterStore.init(managedDatabasePath:))"))
    #expect(source.contains("managedDatabasePath: managedDatabasePath"))
    #expect(source.contains("focusFilterStore: store"))
  }
}
