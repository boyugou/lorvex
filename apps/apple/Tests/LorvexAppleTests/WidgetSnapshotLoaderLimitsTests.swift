import Foundation
import Testing

@testable import LorvexWidgetKitSupport

/// Writes `data` to a fresh `widget_snapshot_v3.json` in a throwaway directory
/// and returns the load result. The caller owns nothing to clean up beyond the
/// process temp dir the OS reclaims.
private func loadSnapshot(writing data: Data) throws -> WidgetSnapshotLoadResult {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-widget-loader-limits-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  try data.write(to: url, options: [.atomic])
  return WidgetSnapshotLoader().loadSnapshot(at: url)
}

@Test
func widgetSnapshotLoaderRejectsOversizedFileBeforeDecoding() throws {
  // One byte over the cap; content need not be valid JSON — the size guard fires
  // before the decoder is ever reached.
  let oversized = Data(count: WidgetSnapshotLoader.maxSnapshotBytes + 1)
  let result = try loadSnapshot(writing: oversized)
  guard case let .fallback(fallback) = result else {
    Issue.record("expected an oversized file to fall back, got \(result)")
    return
  }
  #expect(fallback.reason == .unreadableFile)
}

@Test
func widgetSnapshotLoaderRejectsTooManyDecodedElements() throws {
  // Small on disk (well under the byte cap) but carrying more focus rows than any
  // widget renders: the decoded-element bound must reject it after a clean decode.
  let overCount = WidgetSnapshotLoader.maxDecodedElements + 1
  let focusTasks = (0..<overCount).map { index in
    WidgetSnapshot.FocusTask(
      id: "t\(index)",
      title: "t",
      status: "open",
      dueDate: nil,
      priority: nil,
      listID: nil,
      estimatedMinutes: nil
    )
  }
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: overCount, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: focusTasks
  )
  let encoded = try JSONEncoder().encode(snapshot)
  #expect(encoded.count <= WidgetSnapshotLoader.maxSnapshotBytes)

  let result = try loadSnapshot(writing: encoded)
  guard case let .fallback(fallback) = result else {
    Issue.record("expected an over-count snapshot to fall back, got \(result)")
    return
  }
  #expect(fallback.reason == .unreadableFile)
}

@Test
func widgetSnapshotLoaderAcceptsNormalSnapshot() throws {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1),
    briefing: "Start here.",
    focusTasks: [
      .init(
        id: "task-1",
        title: "Render",
        status: "open",
        dueDate: "2026-05-22",
        priority: 1,
        listID: nil,
        estimatedMinutes: 25
      )
    ]
  )
  let encoded = try JSONEncoder().encode(snapshot)
  let result = try loadSnapshot(writing: encoded)
  guard case let .snapshot(loaded) = result else {
    Issue.record("expected a valid snapshot to load, got \(result)")
    return
  }
  #expect(loaded.focusTasks.count == 1)
}
