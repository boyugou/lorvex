import Foundation
import LorvexWidgetKitSupport
import Testing

@Test
func widgetSnapshotStatsDecodeMissingDueTodayAndAttentionCounts() throws {
  let payload = """
    {
      "version": 3,
      "generated_at": "2026-03-02T10:00:00Z",
      "storage_generation": 0,
      "focus_filter_revision": 0,
      "workspace_instance_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "local_change_sequence": 7,
      "timezone": null,
      "stats": {
        "focus_count": 1,
        "overdue_count": 2
      },
      "briefing": null,
      "focus_tasks": [],
      "habits": [],
      "today_tasks": [],
      "lists": [],
      "list_stats": []
    }
    """.data(using: .utf8)!

  let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: payload)

  #expect(snapshot.stats.focusCount == 1)
  #expect(snapshot.stats.overdueCount == 2)
  #expect(snapshot.stats.dueTodayCount == 0)
  #expect(snapshot.stats.attentionCount == 2)
  #expect(snapshot.logicalDay == nil)
}

@Test
func widgetSnapshotLoaderReturnsFallbacksForMissingAndUnsupportedSnapshots() throws {
  let loader = WidgetSnapshotLoader()
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-widget-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }

  let missing = loader.loadSnapshot(at: tempDirectory.appendingPathComponent("missing.json"))
  guard case .fallback(let missingFallback) = missing else {
    Issue.record("Expected missing snapshot fallback")
    return
  }
  #expect(missingFallback.reason == .missingFile)

  let unsupportedURL = tempDirectory.appendingPathComponent("widget_snapshot_v3.json")
  try """
  {
    "version": 999,
    "generated_at": "2026-03-02T10:00:00Z",
    "storage_generation": 0,
    "focus_filter_revision": 0,
    "workspace_instance_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    "local_change_sequence": 7,
    "timezone": null,
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
  """.write(to: unsupportedURL, atomically: true, encoding: .utf8)

  let unsupported = loader.loadSnapshot(at: unsupportedURL)
  guard case .fallback(let unsupportedFallback) = unsupported else {
    Issue.record("Expected unsupported snapshot fallback")
    return
  }
  #expect(unsupportedFallback.reason == .unsupportedVersion)
}

@Test
func widgetSnapshotLoaderBuildsAppGroupRelativeURL() {
  let loader = WidgetSnapshotLoader()
  let containerURL = URL(fileURLWithPath: "/tmp/group.com.lorvex.apple", isDirectory: true)

  let snapshotURL = loader.snapshotURL(inAppGroupContainer: containerURL)

  #expect(snapshotURL.path == "/tmp/group.com.lorvex.apple/Lorvex/widget_snapshot_v3.json")
}
