import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

/// How long the Mac and iPhone stores take over the work a person waits on,
/// on an on-disk store of two sizes: one like the owner's (about 130 tasks)
/// and a heavy one (4,400 tasks, a year of history for 20 habits, 1,000
/// events). It measures the stores' data work on the main actor, not
/// SwiftUI's rendering. Each figure is printed as
/// `[BENCH] <path> @ <profile>: <ms> ms (<method>)`.
///
/// Runs only with `LORVEX_BENCH=1`, like the core package's benchmarks:
/// `LORVEX_BENCH=1 script/verify_swift.sh --filter StoreLatencyBenchmarks`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LORVEX_BENCH"] == "1"), .serialized)
@MainActor
struct StoreLatencyBenchmarks {
  struct Profile: Sendable {
    let name: String
    let openTasks: Int
    let completedTasks: Int
    let habits: Int
    let habitDays: Int
    let events: Int
  }

  static let owner = Profile(
    name: "owner", openTasks: 90, completedTasks: 40, habits: 5, habitDays: 60, events: 60)
  static let heavy = Profile(
    name: "heavy", openTasks: 400, completedTasks: 4_000, habits: 20, habitDays: 365,
    events: 1_000)

  private static let runs = 7

  @Test("store latency on a store like the owner's")
  func ownerSized() async throws { try await measure(Self.owner) }

  @Test("store latency on a heavy store")
  func heavy() async throws { try await measure(Self.heavy) }

  /// Each step of the Mac's refresh and of the work after a completion, timed
  /// alone on the heavy store, to say where the totals above go.
  @Test("Mac refresh steps on a heavy store")
  func macRefreshSteps() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-store-bench-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("db.sqlite").path
    _ = try await seed(SwiftLorvexCoreService(databasePath: path), Self.heavy)
    let core = SwiftLorvexCoreService(databasePath: path)
    let store = AppStore(core: core)
    await store.refresh()
    let date = store.logicalTodayDateString

    let steps: [(String, () async throws -> Void)] = [
      ("core.loadToday", { _ = try await core.loadToday() }),
      ("core.loadDailyReview", { _ = try await core.loadDailyReview(date: date) }),
      ("core.loadDaySummary", { _ = try await core.loadDaySummary(date: date) }),
      ("core.getWeeklyReviewSnapshot", { _ = try await core.getWeeklyReviewSnapshot(weekOf: nil) }),
      ("core.loadLists", { _ = try await core.loadLists() }),
      ("core.loadArchivedLists", { _ = try await core.loadArchivedLists() }),
      ("core.loadHabits", { _ = try await core.loadHabits(date: date) }),
      ("core.loadRuntimeDiagnostics", { _ = try await core.loadRuntimeDiagnostics() }),
      ("store.reloadWeekReviewDigest", { await store.reloadWeekReviewDigestKeepingOnFailure() }),
      ("store.refreshCurrentCalendarTimeline", {
        try await store.refreshCurrentCalendarTimeline(ingestingEventKit: false)
      }),
      ("store.loadSelectedListDetail", { try await store.loadSelectedListDetail() }),
      ("store.loadAllHabitStats", { await store.loadAllHabitStats() }),
      ("store.reloadTaskWorkspaceIfLoaded", { await store.reloadTaskWorkspaceIfLoaded() }),
      ("store.refreshSelectedTaskRecord", { await store.refreshSelectedTaskRecord() }),
      ("store.reindexContentForSpotlight", { await store.reindexContentForSpotlight() }),
      ("store.reindexTasksForSpotlight", { await store.reindexTasksForSpotlight() }),
      ("store.rescheduleReminders", { await store.rescheduleReminders() }),
      ("store.updateBadge", { await store.updateBadge() }),
      ("store.publishWidgetSnapshot", { try await store.publishWidgetSnapshot() }),
      ("store.refreshListSurfaces", { try await store.refreshListSurfaces() }),
      ("store.reloadSelectedTaskAfterMutation", { await store.reloadSelectedTaskAfterMutation() }),
      ("store.republishSurfacesAfterLocalMutation", {
        await store.republishSurfacesAfterLocalMutation()
      }),
    ]
    for (name, step) in steps {
      var samples: [Double] = []
      for _ in 0..<5 { samples.append(try await time(step)) }
      report("step.\(name)", Self.heavy, median(samples), "median/5")
    }
  }

  private func measure(_ profile: Profile) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-store-bench-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("db.sqlite").path

    let open = try await seed(SwiftLorvexCoreService(databasePath: path), profile)
    #expect(open.count >= 3 * Self.runs)

    // Each store opens the database afresh, as a launch does.
    do {
      let core = SwiftLorvexCoreService(databasePath: path)
      let store = AppStore(core: core)
      report("mac.refresh.first", profile, await time { await store.refresh() }, "single run")
      var refreshes: [Double] = []
      var refreshStalls: [Double] = []
      for _ in 0..<Self.runs {
        let (total, stall) = await timeWithStall { await store.refresh() }
        refreshes.append(total)
        refreshStalls.append(stall)
      }
      report("mac.refresh", profile, median(refreshes), "median/\(Self.runs)")
      report("mac.refresh.mainStall", profile, median(refreshStalls), "median/\(Self.runs)")

      var writes: [Double] = []
      for id in open[0..<Self.runs] {
        writes.append(try await time { _ = try await core.completeTask(id: id) })
      }
      report("core.complete+today", profile, median(writes), "median/\(Self.runs)")

      var actions: [Double] = []
      var actionStalls: [Double] = []
      for id in open[Self.runs..<(2 * Self.runs)] {
        let task = try await core.loadTask(id: id)
        let (total, stall) = await timeWithStall { await store.toggleTaskCompletion(task) }
        actions.append(total)
        actionStalls.append(stall)
      }
      report("mac.complete.action", profile, median(actions), "median/\(Self.runs)")
      report("mac.complete.mainStall", profile, median(actionStalls), "median/\(Self.runs)")
    }

    do {
      let store = MobileStore(core: SwiftLorvexCoreService(databasePath: path))
      report("ios.refresh.first", profile, await time { _ = await store.refresh() }, "single run")
      var refreshes: [Double] = []
      var refreshStalls: [Double] = []
      for _ in 0..<Self.runs {
        let (total, stall) = await timeWithStall { _ = await store.refresh() }
        refreshes.append(total)
        refreshStalls.append(stall)
      }
      report("ios.refresh", profile, median(refreshes), "median/\(Self.runs)")
      report("ios.refresh.mainStall", profile, median(refreshStalls), "median/\(Self.runs)")

      var actions: [Double] = []
      var actionStalls: [Double] = []
      for id in open[(2 * Self.runs)..<(3 * Self.runs)] {
        let (total, stall) = await timeWithStall { _ = await store.completeTask(id) }
        actions.append(total)
        actionStalls.append(stall)
      }
      report("ios.complete.action", profile, median(actions), "median/\(Self.runs)")
      report("ios.complete.mainStall", profile, median(actionStalls), "median/\(Self.runs)")
    }
  }

  /// Fills `core` and returns the open tasks' ids. Daily backups are off so a
  /// backup pass started by a refresh does not run beside the measurements.
  private func seed(_ core: SwiftLorvexCoreService, _ profile: Profile) async throws
    -> [LorvexTask.ID]
  {
    _ = try await core.setPreference(key: "timezone", value: "America/Los_Angeles")
    try await core.setDailyBackupsEnabled(false)
    var lists: [LorvexList.ID] = []
    for index in 0..<6 {
      lists.append(try await core.createList(name: "List \(index)", description: nil).id)
    }
    var open: [LorvexTask.ID] = []
    for index in 0..<profile.openTasks {
      let task = try await core.createTask(
        TaskCreateDraft(
          title: "Open task \(index)",
          notes: index % 4 == 0 ? "Notes for task \(index), a line or two long." : "",
          listID: lists[index % lists.count],
          estimatedMinutes: index % 2 == 0 ? 30 : nil,
          dueDate: index % 3 == 0 ? Self.day(offset: index % 45 - 15) : nil,
          plannedDate: index % 5 == 0 ? Self.day(offset: 0) : nil,
          tags: index % 3 == 0 ? ["tag\(index % 7)"] : nil))
      open.append(task.id)
    }
    for index in 0..<profile.completedTasks {
      let task = try await core.createTask(
        TaskCreateDraft(title: "Done task \(index)", listID: lists[index % lists.count]))
      _ = try await core.completeTask(id: task.id)
    }
    for index in 0..<profile.habits {
      let habit = try await core.createHabit(name: "Habit \(index)", cue: nil, targetCount: 1)
      for offset in 1...profile.habitDays where (offset + index) % 3 != 0 {
        _ = try await core.completeHabit(id: habit.id, date: Self.ymd(offset: -offset))
      }
    }
    for index in 0..<profile.events {
      let hour = 8 + index % 9
      _ = try await core.createCalendarEvent(
        title: "Event \(index)", startDate: Self.ymd(offset: index % 120 - 60), endDate: nil,
        startTime: String(format: "%02d:00", hour), endTime: String(format: "%02d:45", hour),
        allDay: false, location: nil, notes: nil, recurrence: nil, timezone: nil, url: nil,
        color: nil, eventType: nil, personName: nil, attendees: nil)
    }
    return open
  }

  private static func day(offset: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let today = calendar.startOfDay(for: Date())
    return calendar.date(byAdding: .day, value: offset, to: today) ?? today
  }

  private static func ymd(offset: Int) -> String {
    LorvexDateFormatters.ymdUTC.string(from: day(offset: offset))
  }

  private func time(_ body: () async throws -> Void) async rethrows -> Double {
    let clock = ContinuousClock()
    let start = clock.now
    try await body()
    let elapsed = start.duration(to: clock.now)
    return Double(elapsed.components.seconds) * 1_000
      + Double(elapsed.components.attoseconds) / 1e15
  }

  /// The time `body` takes, and the longest stretch the main actor was busy
  /// meanwhile: a main-actor ticker that sleeps 1 ms between wakes records the
  /// longest gap between them. Over about 16 ms, a 60 Hz screen drops a frame.
  private func timeWithStall(_ body: () async -> Void) async -> (total: Double, stall: Double) {
    let ticker = MainActorTicker()
    let tick = Task { await ticker.run() }
    let total = await time { await body() }
    ticker.stop()
    await tick.value
    return (total, ticker.longestGapMs)
  }

  private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
  }

  private func report(_ path: String, _ profile: Profile, _ ms: Double, _ method: String) {
    print("[BENCH] \(path) @ \(profile.name): \(String(format: "%.1f", ms)) ms (\(method))")
  }
}

/// Wakes on the main actor every millisecond and keeps the longest gap between
/// two wakes, which is the longest time other main-actor work held it.
@MainActor
private final class MainActorTicker {
  private var running = true
  private(set) var longestGapMs: Double = 0

  func run() async {
    let clock = ContinuousClock()
    var last = clock.now
    while running {
      try? await Task.sleep(for: .milliseconds(1))
      let now = clock.now
      let gap = last.duration(to: now)
      let ms = Double(gap.components.seconds) * 1_000 + Double(gap.components.attoseconds) / 1e15
      longestGapMs = max(longestGapMs, ms)
      last = now
    }
  }

  func stop() { running = false }
}
