import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWidgetExtension

/// A widget that reloads after midnight finds the snapshot the app wrote the
/// day before. It rebuilds the file for the new day from the shared database
/// instead of asking the user to open Lorvex, and leaves every other kind of
/// file, and a failed rebuild, as it found them.
@Suite("Widget snapshot day rollover")
struct WidgetSnapshotDayRolloverTests {
  /// 2026-05-23T12:00:00Z: the same calendar day in every zone from UTC-11
  /// to UTC+11, so the expectations hold for the seed's Los Angeles zone.
  private static let noonMay23 = Date(timeIntervalSince1970: 1_779_537_600)

  private static var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }

  private static func ymd(_ date: Date) -> String {
    let components = utc.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  /// A temporary snapshot location, removed when `body` returns.
  private static func withSnapshotURL<T>(_ body: (URL) async throws -> T) async throws -> T {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-widget-rollover-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory.appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName))
  }

  private static func writeSnapshot(day: String, title: String, to url: URL) throws {
    let snapshot = WidgetSnapshot(
      generatedAt: "\(day)T09:00:00Z",
      timezone: "UTC",
      logicalDay: day,
      stats: .init(todayCount: 1, overdueCount: 0, dueTodayCount: 0),
      briefing: nil,
      tasks: [
        .init(
          id: "task-\(title)", title: title, status: LorvexTask.Status.open.rawValue,
          dueDate: nil, priority: 2, listID: nil, estimatedMinutes: nil,
          scheduledStart: nil, scheduledEnd: nil)
      ])
    try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic])
  }

  private static func rollover(
    now: Date,
    rebuild: @escaping @Sendable (URL) async throws -> Void
  ) -> WidgetSnapshotDayRollover {
    WidgetSnapshotDayRollover(calendar: utc, now: { now }, rebuild: rebuild)
  }

  // MARK: - When it rebuilds

  @Test("rebuilds a snapshot from an earlier day and nothing else")
  func rebuildsOnlyAnExpiredDay() async throws {
    try await Self.withSnapshotURL { url in
      let rebuilds = LockedBox(0)
      let rollover = Self.rollover(now: Self.noonMay23) { _ in rebuilds.mutate { $0 += 1 } }

      // No file: the app may never have run, so the store is not opened.
      #expect(await rollover.rollOverIfExpired(snapshotURL: url) == false)
      #expect(await rollover.rollOverIfExpired(snapshotURL: nil) == false)

      // A damaged file is the app's to replace.
      try "{ invalid json".write(to: url, atomically: true, encoding: .utf8)
      #expect(await rollover.rollOverIfExpired(snapshotURL: url) == false)

      // Today's file is current.
      try Self.writeSnapshot(day: "2026-05-23", title: "Today", to: url)
      #expect(await rollover.rollOverIfExpired(snapshotURL: url) == false)
      #expect(rebuilds.value == 0)

      // Yesterday's file is rebuilt.
      try Self.writeSnapshot(day: "2026-05-22", title: "Yesterday", to: url)
      #expect(await rollover.rollOverIfExpired(snapshotURL: url))
      #expect(rebuilds.value == 1)
    }
  }

  @Test("a failed rebuild leaves the file and reports no rollover")
  func failedRebuildLeavesTheFile() async throws {
    struct Locked: Error {}
    try await Self.withSnapshotURL { url in
      try Self.writeSnapshot(day: "2026-05-22", title: "Yesterday", to: url)
      let before = try Data(contentsOf: url)

      let rollover = Self.rollover(now: Self.noonMay23) { _ in throw Locked() }

      #expect(await rollover.rollOverIfExpired(snapshotURL: url) == false)
      #expect(try Data(contentsOf: url) == before)
    }
  }

  // MARK: - What the rebuild writes

  @Test("the rebuild writes the new day's Today from the database")
  func rebuildWritesTheNewDayFromTheDatabase() async throws {
    let core = try await makeSeededInMemoryCore()
    let task = try await core.createTask(title: "Water the plants", notes: "")
    try await planTask(core, task.id, on: "2026-05-23")

    try await Self.withSnapshotURL { url in
      _ = try await WidgetSnapshotLiveRefresher(reloadTimelines: {}, todayString: { "2026-05-22" })
        .refresh(core: core, snapshotURL: url)
      guard case .snapshot(let yesterday) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
        Issue.record("Expected yesterday's snapshot on disk")
        return
      }
      #expect(yesterday.tasks.contains { $0.id == task.id } == false)

      let rollover = WidgetSnapshotDayRollover(
        calendar: Self.utc, now: { Self.noonMay23 },
        rebuild: { snapshotURL in
          _ = try await WidgetSnapshotLiveRefresher(
            reloadTimelines: {}, todayString: { "2026-05-23" }
          ).refresh(core: core, snapshotURL: snapshotURL)
        })
      #expect(await rollover.rollOverIfExpired(snapshotURL: url))

      guard case .snapshot(let today) = WidgetSnapshotLoader().loadSnapshot(at: url) else {
        Issue.record("Expected the rebuilt snapshot on disk")
        return
      }
      #expect(today.logicalDay == "2026-05-23")
      #expect(today.tasks.contains { $0.id == task.id })
    }
  }

  // MARK: - The surfaces

  /// Every surface that would show "Open Lorvex to refresh" for yesterday's
  /// file rolls it over first: the Today widget, the raw-snapshot widgets
  /// (Progress, Habits), and the Control Center button.
  @Test("each widget surface shows the new day instead of the expired fallback")
  func surfacesRollOverBeforeReading() async throws {
    let now = Date()
    let today = Self.ymd(now)
    let yesterday = Self.ymd(now.addingTimeInterval(-86_400))
    let rollover = WidgetSnapshotDayRollover(
      calendar: Self.utc,
      rebuild: { url in try Self.writeSnapshot(day: today, title: "Today", to: url) })

    try await Self.withSnapshotURL { url in
      try Self.writeSnapshot(day: yesterday, title: "Yesterday", to: url)
      let timeline = await LorvexTodayWidgetTimelineProvider(
        configuration: LorvexWidgetConfiguration(), dayRollover: rollover
      ).timeline(family: .systemSmall, listID: nil, snapshotURL: url)
      #expect(timeline.entries.first?.model.state != .fallback)
    }

    try await Self.withSnapshotURL { url in
      try Self.writeSnapshot(day: yesterday, title: "Yesterday", to: url)
      let timeline = await LorvexSnapshotTimelineProvider(
        configuration: LorvexWidgetConfiguration(), dayRollover: rollover
      ).timeline(snapshotURL: url)
      #expect(timeline.entries.first?.snapshot?.logicalDay == today)
    }

    if #available(iOS 18.0, macOS 26.0, *) {
      try await Self.withSnapshotURL { url in
        try Self.writeSnapshot(day: yesterday, title: "Yesterday", to: url)
        let value = await LorvexTodayControlProvider(dayRollover: rollover)
          .value(snapshotURL: url)
        #expect(value.availability == .content)
      }
    }
  }

  @Test("without a rollover the surfaces keep the expired-day fallback")
  func surfacesKeepTheFallbackWhenTheRebuildFails() async throws {
    struct Locked: Error {}
    let now = Date()
    let yesterday = Self.ymd(now.addingTimeInterval(-86_400))
    let rollover = WidgetSnapshotDayRollover(calendar: Self.utc, rebuild: { _ in throw Locked() })

    try await Self.withSnapshotURL { url in
      try Self.writeSnapshot(day: yesterday, title: "Yesterday", to: url)
      let timeline = await LorvexTodayWidgetTimelineProvider(
        configuration: LorvexWidgetConfiguration(), dayRollover: rollover
      ).timeline(family: .systemSmall, listID: nil, snapshotURL: url)
      #expect(timeline.entries.first?.model.state == .fallback)
    }
  }
}
