import Foundation
@testable import LorvexWidgetExtension
import LorvexWidgetKitSupport
import Testing

@Test
func widgetTimelineProviderBuildsFreshEntryFromSnapshotFile() async throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-widget-timeline-tests-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL = tempDirectory.appendingPathComponent(
    WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1),
    briefing: "Start here.",
    focusTasks: [
      .init(
        id: "task-widget-entry",
        title: "Render widget entry",
        status: "in_progress",
        dueDate: "2026-05-22",
        priority: 1,
        listID: nil,
        estimatedMinutes: 25
      )
    ]
  )
  let encoded = try JSONEncoder().encode(snapshot)
  try encoded.write(to: snapshotURL, options: [.atomic])
  let now = Date(timeIntervalSince1970: 1_779_465_900)
  let provider = WidgetTimelineProviderSupport(
    configuration: .init(snapshotURL: snapshotURL),
    now: { now }
  )

  let entry = provider.timelineEntry()

  #expect(entry.date == now)
  #expect(entry.refreshAfter == now.addingTimeInterval(115 * 60))
  #expect(provider.compactStatusText(for: entry) == "Updated now")
  guard case .snapshot(let loaded, let freshness) = entry.state else {
    Issue.record("Expected snapshot timeline entry")
    return
  }
  #expect(loaded == snapshot)
  #expect(freshness == .fresh(ageSeconds: 300))
}

@Test
func widgetTimelineProviderExpiresPriorLogicalDayInsteadOfShowingYesterdayAsToday() throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("expired-widget-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL = tempDirectory.appendingPathComponent(
    WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

  // Both instants are on May 23 in UTC, but they straddle midnight in the
  // snapshot's America/Los_Angeles logical day.
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-23T06:59:00Z",
    timezone: "America/Los_Angeles",
    stats: .init(focusCount: 1, overdueCount: 1, dueTodayCount: 1),
    briefing: "Yesterday's plan",
    focusTasks: []
  )
  try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: [.atomic])
  let now = try #require(ISO8601DateFormatter().date(from: "2026-05-23T07:01:00Z"))
  var utcCalendar = Calendar(identifier: .gregorian)
  utcCalendar.timeZone = try #require(TimeZone(identifier: "UTC"))
  let provider = WidgetTimelineProviderSupport(
    configuration: .init(snapshotURL: snapshotURL, calendar: utcCalendar),
    now: { now }
  )

  let entry = provider.timelineEntry()

  #expect(provider.compactStatusText(for: entry) == "Open Lorvex to refresh")
  guard case .fallback(let fallback) = entry.state else {
    Issue.record("Expected prior-day snapshot to expire")
    return
  }
  #expect(fallback.reason == .expiredDay)
}

@Test
func widgetTimelineProviderUsesFallbackCadenceWhenSnapshotIsMissing() {
  let snapshotURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("missing-widget-\(UUID().uuidString).json")
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let provider = WidgetTimelineProviderSupport(
    configuration: .init(snapshotURL: snapshotURL),
    now: { now }
  )

  let entry = provider.timelineEntry()

  #expect(
    entry.refreshAfter
      == WidgetTimelineRefreshPolicy().nextLocalMidnight(after: now, calendar: .current))
  #expect(provider.compactStatusText(for: entry) == "Open Lorvex to refresh")
  guard case .fallback(let fallback) = entry.state else {
    Issue.record("Expected fallback timeline entry")
    return
  }
  #expect(fallback.reason == .missingFile)
}

@Test
func widgetTimelineProviderReportsInvalidSnapshotData() throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("invalid-widget-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL = tempDirectory.appendingPathComponent(
    WidgetSnapshotLoader.defaultSnapshotFileName)
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }
  try Data("not json".utf8).write(to: snapshotURL, options: [.atomic])
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let provider = WidgetTimelineProviderSupport(
    configuration: .init(snapshotURL: snapshotURL),
    now: { now }
  )

  let entry = provider.timelineEntry()

  #expect(
    entry.refreshAfter
      == WidgetTimelineRefreshPolicy().nextLocalMidnight(after: now, calendar: .current))
  #expect(provider.compactStatusText(for: entry) == "Snapshot data damaged")
  guard case .fallback(let fallback) = entry.state else {
    Issue.record("Expected fallback timeline entry")
    return
  }
  #expect(fallback.reason == .invalidJSON)
}

@Test
func widgetTimelineProviderReportsUnsupportedSnapshotVersion() throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("unsupported-widget-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL = tempDirectory.appendingPathComponent(
    WidgetSnapshotLoader.defaultSnapshotFileName)
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }
  try """
  {
    "version": 999,
    "generated_at": "2026-05-22T16:00:00Z",
    "storage_generation": 0,
    "focus_filter_revision": 0,
    "workspace_instance_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    "local_change_sequence": 1,
    "timezone": "UTC",
    "stats": {
      "focus_count": 0,
      "overdue_count": 0,
      "due_today_count": 0
    },
    "briefing": null,
    "focus_tasks": [],
    "habits": [],
    "today_tasks": [],
    "lists": [],
    "list_stats": []
  }
  """.write(to: snapshotURL, atomically: true, encoding: .utf8)
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let provider = WidgetTimelineProviderSupport(
    configuration: .init(snapshotURL: snapshotURL),
    now: { now }
  )

  let entry = provider.timelineEntry()

  #expect(
    entry.refreshAfter
      == WidgetTimelineRefreshPolicy().nextLocalMidnight(after: now, calendar: .current))
  #expect(provider.compactStatusText(for: entry) == "Update Lorvex to refresh")
  guard case .fallback(let fallback) = entry.state else {
    Issue.record("Expected fallback timeline entry")
    return
  }
  #expect(fallback.reason == .unsupportedVersion)
}

@Test
func widgetTimelineProviderPlaceholderIsStableAndWidgetReady() {
  let snapshotURL = URL(fileURLWithPath: "/tmp/unused-widget-placeholder.json")
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let provider = WidgetTimelineProviderSupport(
    configuration: .init(snapshotURL: snapshotURL),
    now: { now }
  )

  let entry = provider.placeholderEntry()

  #expect(entry.date == now)
  #expect(
    entry.refreshAfter
      == WidgetTimelineRefreshPolicy().nextLocalMidnight(after: now, calendar: .current))
  #expect(provider.compactStatusText(for: entry) == "Update time unavailable")
  #expect(entry.state.snapshot?.briefing == "Lorvex is ready.")
}

@Test
func rawSnapshotEntryPreservesFallbackStatusText() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let timelineEntry = WidgetTimelineEntry(
    date: now,
    state: .fallback(.init(reason: .invalidJSON, detail: "broken")),
    refreshAfter: now.addingTimeInterval(5 * 60)
  )

  let entry = LorvexSnapshotEntry(
    timelineEntry: timelineEntry,
    statusText: "Snapshot data damaged"
  )

  #expect(entry.snapshot == nil)
  #expect(entry.statusText == "Snapshot data damaged")
  #expect(entry.freshness == .unknownTimestamp)
  #expect(entry.relevance == nil)
}

@Test
func rawSnapshotEntryExposesSmartStackRelevanceForTasks() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1),
    briefing: nil,
    focusTasks: [
      .init(
        id: "task-focus",
        title: "Focus",
        status: "open",
        dueDate: nil,
        priority: nil,
        listID: nil,
        estimatedMinutes: nil
      )
    ],
    todayTasks: [
      .init(
        id: "task-today",
        title: "Today",
        dueDate: "2026-05-22",
        priority: 1,
        estimatedMinutes: nil
      )
    ]
  )
  let entry = LorvexSnapshotEntry(
    timelineEntry: .init(
      date: now,
      state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
      refreshAfter: now.addingTimeInterval(30 * 60)
    ),
    statusText: "Updated now"
  )

  #expect(entry.snapshot == snapshot)
  #expect(entry.relevance?.score == 40)
}

@Test
func todayTaskBuildsCanonicalDeepLinkURL() {
  let task = WidgetSnapshot.TodayTask(
    id: "task with/slash",
    title: "Open me",
    dueDate: "2026-05-22",
    priority: 2,
    estimatedMinutes: 15
  )

  #expect(task.taskURL.absoluteString == "lorvex://task/task%20with%2Fslash")
}
