import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import MCP
import Testing

@testable import LorvexApple
@testable import LorvexMCPHost

// MARK: - Helpers

/// Wall-clock benchmarks are gated behind `LORVEX_BENCH` (matching the core
/// package's convention) so an ordinary `swift test` — which runs the suite in
/// parallel and contends for the machine — never flakes on a load-sensitive
/// median. Set `LORVEX_BENCH=1` to run them.
private let benchmarksEnabled = ProcessInfo.processInfo.environment["LORVEX_BENCH"] != nil


/// Runs `operation` `runs` times, drops the first result (warmup), and returns the median
/// of the remaining runs in milliseconds.
private func medianMs(runs: Int = 11, operation: @Sendable () async throws -> Void) async rethrows -> Double {
  var samples: [Double] = []
  for _ in 0 ..< runs {
    let start = Date()
    try await operation()
    samples.append(Date().timeIntervalSince(start) * 1000)
  }
  return medianFromSamples(samples)
}

private func nonThrowingMedianMs(runs: Int = 11, operation: @Sendable () async -> Void) async -> Double {
  var samples: [Double] = []
  for _ in 0 ..< runs {
    let start = Date()
    await operation()
    samples.append(Date().timeIntervalSince(start) * 1000)
  }
  return medianFromSamples(samples)
}

@MainActor
private func mainActorMedianMs(runs: Int = 11, operation: () async -> Void) async -> Double {
  var samples: [Double] = []
  for _ in 0 ..< runs {
    let start = Date()
    await operation()
    samples.append(Date().timeIntervalSince(start) * 1000)
  }
  return medianFromSamples(samples)
}

private func medianFromSamples(_ samples: [Double]) -> Double {
  // Drop first run (cold cache), median the rest.
  let warm = samples.dropFirst().sorted()
  let mid = warm.count / 2
  return warm.count % 2 == 0
    ? (warm[warm.index(warm.startIndex, offsetBy: mid - 1)] + warm[warm.index(warm.startIndex, offsetBy: mid)]) / 2
    : warm[warm.index(warm.startIndex, offsetBy: mid)]
}

// MARK: - Fixtures

private func benchTask(index i: Int) -> LorvexTask {
  let priorities: [LorvexTask.Priority] = [.p1, .p2, .p3]
  return LorvexTask(
    id: "bench-task-\(i)",
    title: "Benchmark Task \(i)",
    notes: "Notes for task \(i) covering work items and details.",
    priority: priorities[i % 3],
    status: i % 5 == 0 ? .completed : .open,
    dueDate: i % 7 == 0 ? Date(timeIntervalSinceNow: Double(i) * 86400) : nil,
    estimatedMinutes: i % 3 == 0 ? 30 : nil,
    tags: i % 4 == 0 ? ["work", "urgent"] : ["personal"]
  )
}

private func make1000Tasks() -> [LorvexTask] {
  (0 ..< 1000).map { benchTask(index: $0) }
}

private func make1000ExportTasks() -> [ExportTask] {
  make1000Tasks().map(ExportTask.init(from:))
}

private func makeTodaySnapshotWith1000Tasks() -> TodaySnapshot {
  TodaySnapshot(
    focusTitle: "Benchmark Day",
    summary: "Benchmark snapshot",
    tasks: make1000Tasks(),
    localChangeSequence: 1
  )
}

// MARK: - Benchmarks

@Test("AppStore.refresh reuses one all-task corpus for Apple system surfaces")
func appStoreRefreshReusesSingleAppleSurfaceTaskCorpus() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Stores/AppStoreRuntimeLifecycle.swift"),
    encoding: .utf8
  )

  // Content indexing is independent of the bulk task read, so it runs regardless;
  // the three task-derived surfaces share one appleSurfaceTasks() corpus and are
  // skipped together when that read fails (keeping the prior index/reminders).
  #expect(source.contains("async let contentIndex: Void = reindexContentForSpotlight()"))
  #expect(source.contains("if let surfaceTasks = await appleSurfaceTasks() {"))
  #expect(source.contains("async let taskIndex: Void = reindexTasksForSpotlight(tasks: surfaceTasks)"))
  #expect(source.contains("async let reminderSchedule: Void = rescheduleReminders(tasks: surfaceTasks)"))
  #expect(source.contains("async let badge: Void = updateBadge(tasks: surfaceTasks)"))
  #expect(source.contains("_ = await (taskIndex, reminderSchedule, badge)"))
  #expect(source.contains("await contentIndex"))
}

@Test("AppStore.refresh parallelizes independent core loads")
func appStoreRefreshParallelizesIndependentCoreLoads() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Stores/AppStoreRuntimeLifecycle.swift"),
    encoding: .utf8
  )

  // Today must load first because it owns the product logical day/timezone used
  // to key every independent day-scoped read in the parallel fan-out below.
  #expect(source.contains("today = try await core.loadToday()"))
  #expect(source.contains("let date = logicalTodayDateString"))
  for load in [
    "async let loadedCurrentFocus",
    "async let loadedFocusSchedule",
    "async let loadedDailyReview",
    "async let loadedWeeklyReview",
    "async let loadedLists",
    "async let loadedHabits",
  ] {
    #expect(source.contains(load), "Missing parallel refresh load: \(load)")
  }
}

@Test("Calendar refresh uses due-bounded scheduled task queries")
func calendarRefreshUsesDueBoundedScheduledTaskQueries() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let mobile = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStorePlanningActions.swift"),
    encoding: .utf8
  )
  let mobileCalendar = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreCalendarActions.swift"),
    encoding: .utf8
  )
  let mac = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Stores/AppStoreCalendarActions.swift"),
    encoding: .utf8
  )

  #expect(mobile.contains("core.getScheduledTasks("))
  #expect(mobileCalendar.contains("core.getScheduledTasks("))
  #expect(mac.contains("core.getScheduledTasks("))
  #expect(!mobile.contains("limit: 5000"))
  #expect(!mobileCalendar.contains("limit: 5000"))
  #expect(!mac.contains("limit: 5000"))
}

@Test("Mobile reminder scheduling avoids all-task fallback queries")
func mobileReminderSchedulingAvoidsAllTaskFallbackQueries() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreNotificationActions.swift"),
    encoding: .utf8
  )

  #expect(source.contains("core.getTasksWithUpcomingReminders("))
  #expect(!source.contains("core.listTasks("))
  #expect(!source.contains("limit: 5000"))
}

@MainActor
@Test("Benchmark: AppStore.refresh() against the in-memory core under 200ms median", .enabled(if: benchmarksEnabled, "set LORVEX_BENCH=1 to run wall-clock benchmarks"))
func benchmarkAppStoreRefresh() async throws {
  // The refresh runs real SQLite queries (the seeded in-memory GRDB store),
  // and the benchmark executes amid the parallel suite; ~70ms medians are
  // normal under load, so the guardrail bounds regressions, not the idle
  // fast path.
  let store = AppStore(core: try await makeSeededInMemoryCore())
  let elapsed = await mainActorMedianMs { await store.refresh() }
  #expect(elapsed < 200, "AppStore.refresh() median \(String(format: "%.1f", elapsed))ms exceeded 200ms threshold")
}

@Test("Benchmark: WidgetSnapshotProjector.snapshot on 1000-task today under 30ms median", .enabled(if: benchmarksEnabled, "set LORVEX_BENCH=1 to run wall-clock benchmarks"))
func benchmarkWidgetSnapshotProjector() async throws {
  let projector = WidgetSnapshotProjector(now: { Date(timeIntervalSince1970: 1_779_465_600) })
  let today = makeTodaySnapshotWith1000Tasks()
  let elapsed = await nonThrowingMedianMs {
    _ = projector.snapshot(today: today, currentFocus: nil, timezone: "UTC")
  }
  #expect(elapsed < 30, "WidgetSnapshotProjector.snapshot median \(String(format: "%.1f", elapsed))ms exceeded 30ms threshold")
}

@Test("Benchmark: LorvexDataExporter.render(.json) on 1000-task payload under 100ms median", .enabled(if: benchmarksEnabled, "set LORVEX_BENCH=1 to run wall-clock benchmarks"))
func benchmarkDataExporterJSON() async throws {
  let payload = LorvexDataExportPayload(tasks: make1000ExportTasks())
  let elapsed = await nonThrowingMedianMs {
    _ = try? LorvexDataExporter.render(payload: payload, format: .json)
  }
  #expect(elapsed < 100, "LorvexDataExporter.render(.json) median \(String(format: "%.1f", elapsed))ms exceeded 100ms threshold")
}

@Test("Benchmark: LorvexDataExporter.render(.csv) on 1000-task payload under 100ms median", .enabled(if: benchmarksEnabled, "set LORVEX_BENCH=1 to run wall-clock benchmarks"))
func benchmarkDataExporterCSV() async throws {
  let payload = LorvexDataExportPayload(tasks: make1000ExportTasks())
  let elapsed = await nonThrowingMedianMs {
    _ = try? LorvexDataExporter.render(payload: payload, format: .csv)
  }
  #expect(elapsed < 100, "LorvexDataExporter.render(.csv) median \(String(format: "%.1f", elapsed))ms exceeded 100ms threshold")
}

@Test("Benchmark: ToolRegistry dispatch list_tasks under 20ms median", .enabled(if: benchmarksEnabled, "set LORVEX_BENCH=1 to run wall-clock benchmarks"))
func benchmarkMCPToolRegistryListTasks() async throws {
  let registry = try mcpInMemoryRegistry()
  let params = CallTool.Parameters(name: "list_tasks", arguments: [:])
  let elapsed = try await medianMs {
    _ = try await registry.call(params)
  }
  #expect(elapsed < 20, "ToolRegistry list_tasks dispatch median \(String(format: "%.1f", elapsed))ms exceeded 20ms threshold")
}

@Test("Benchmark: Spotlight document creation for 100 tasks/lists/habits under 50ms median", .enabled(if: benchmarksEnabled, "set LORVEX_BENCH=1 to run wall-clock benchmarks"))
func benchmarkSpotlightDocumentCreation() async throws {
  let tasks = (0 ..< 100).map { i in
    LorvexTask(
      id: "spot-task-\(i)", title: "Spotlight Task \(i)", notes: "Spotlight notes",
      priority: .p2, status: .open, dueDate: nil, estimatedMinutes: nil, tags: ["spotlight"]
    )
  }
  let lists = (0 ..< 100).map { i in
    LorvexList(
      id: "spot-list-\(i)", name: "Spotlight List \(i)", color: nil, icon: nil,
      description: "A spotlight test list", openCount: 5, totalCount: 10, updatedAt: "2026-05-24"
    )
  }
  let habits = (0 ..< 100).map { i in
    LorvexHabit(
      id: "spot-habit-\(i)", name: "Spotlight Habit \(i)", icon: nil, color: nil,
      cue: nil, frequencyType: "daily", targetCount: 1, completionsToday: 0,
      totalCompletions: i, completionRate30d: 0.8, archived: false
    )
  }
  let elapsed = await nonThrowingMedianMs {
    _ = tasks.map(SpotlightTaskDocument.init(task:))
    _ = lists.map(SpotlightListDocument.init(list:))
    _ = habits.map(SpotlightHabitDocument.init(habit:))
  }
  #expect(elapsed < 50, "Spotlight document creation median \(String(format: "%.1f", elapsed))ms exceeded 50ms threshold")
}
