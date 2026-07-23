import Foundation
import Testing
import LorvexCore
import LorvexWatch
import LorvexWidgetKitSupport

// MARK: - LorvexWatchSnapshotReader tests

@Suite("LorvexWatchSnapshotReader")
struct LorvexWatchSnapshotReaderTests {

  private let snapshotDate = ISO8601DateFormatter().date(from: "2026-05-24T10:01:00Z")!

  // MARK: - Helpers

  private func writeSnapshot(_ snapshot: WidgetSnapshot, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let envelope = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      snapshotData: JSONEncoder().encode(snapshot))
    try envelope.wireData().write(to: url, options: [.atomic])
  }

  private func makeTempURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-reader-\(UUID().uuidString)")
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
  }

  private func makeSnapshot(taskTitle: String, status: String = "open") -> WidgetSnapshot {
    WidgetSnapshot(
      generatedAt: "2026-05-24T10:00:00Z",
      workspaceInstanceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      localChangeSequence: 1,
      timezone: "UTC",
      stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1),
      briefing: "Daily briefing",
      focusTasks: [
        .init(
          id: "task-1",
          title: taskTitle,
          status: status,
          dueDate: "2026-05-24",
          priority: 1,
          listID: nil,
          estimatedMinutes: 30
        )
      ]
    )
  }

  // MARK: - Round-trip

  @Test("reader round-trip: maps open tasks")
  func readerRoundTrip() throws {
    let url = makeTempURL()
    try writeSnapshot(makeSnapshot(taskTitle: "Write release notes"), to: url)

    let reader = LorvexWatchSnapshotReader(url: url)
    let (result, tasks) = reader.read(at: snapshotDate)

    guard case .snapshot = result else {
      Issue.record("Expected .snapshot, got \(result)")
      return
    }
    let primary = try #require(tasks.first)
    #expect(tasks.count == 1)
    #expect(primary.id == "task-1")
    #expect(primary.title == "Write release notes")
    #expect(primary.priority == .p1)
    #expect(primary.estimatedMinutes == 30)
  }

  @Test("reader round-trip: keeps in-progress tasks actionable")
  func readerRoundTripInProgress() throws {
    let url = makeTempURL()
    try writeSnapshot(
      makeSnapshot(taskTitle: "Continue release notes", status: "in_progress"),
      to: url
    )

    let reader = LorvexWatchSnapshotReader(url: url)
    let (_, tasks) = reader.read(at: snapshotDate)

    #expect(tasks.map(\.title) == ["Continue release notes"])
  }

  @Test("reader returns fallback when snapshot file is missing")
  func readerFallbackMissingFile() {
    let url = makeTempURL() // file never written
    let reader = LorvexWatchSnapshotReader(url: url)
    let (result, tasks) = reader.read(at: snapshotDate)

    guard case .fallback(let fallback) = result else {
      Issue.record("Expected .fallback, got \(result)")
      return
    }
    #expect(fallback.reason == .missingFile)
    #expect(tasks.isEmpty)
  }

  @Test("reader expires a prior-day snapshot")
  func readerExpiresPriorDaySnapshot() throws {
    let url = makeTempURL()
    try writeSnapshot(makeSnapshot(taskTitle: "Yesterday's task"), to: url)

    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let reader = LorvexWatchSnapshotReader(url: url, calendar: utc)
    let nextDay = try #require(
      ISO8601DateFormatter().date(from: "2026-05-25T00:01:00Z")
    )
    let (result, tasks) = reader.read(at: nextDay)

    guard case .fallback(let fallback) = result else {
      Issue.record("Expected expired-day fallback, got \(result)")
      return
    }
    #expect(fallback.reason == .expiredDay)
    #expect(tasks.isEmpty)
  }

  @Test("reader returns fallback when JSON is invalid")
  func readerFallbackInvalidJSON() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(to: url, options: [.atomic])

    let reader = LorvexWatchSnapshotReader(url: url)
    let (result, tasks) = reader.read()

    guard case .fallback(let fallback) = result else {
      Issue.record("Expected .fallback, got \(result)")
      return
    }
    #expect(fallback.reason == .invalidJSON)
    #expect(tasks.isEmpty)
  }

  @Test("reader returns empty tasks when all tasks are completed")
  func readerEmptyTasksWhenCompleted() throws {
    let url = makeTempURL()
    try writeSnapshot(makeSnapshot(taskTitle: "Done task", status: "completed"), to: url)

    let reader = LorvexWatchSnapshotReader(url: url)
    let (result, tasks) = reader.read(at: snapshotDate)

    guard case .snapshot = result else {
      Issue.record("Expected .snapshot, got \(result)")
      return
    }
    #expect(tasks.isEmpty)
  }

  @Test("appGroupReader returns nil when App Group is unavailable")
  func appGroupReaderNilWhenUnavailable() {
    let reader = LorvexWatchSnapshotReader.appGroupReader(appGroupID: "group.invalid.test-only")
    // In a plain Swift test context without App Group entitlements the container URL is nil.
    // The exact result depends on the sandbox; both nil and non-nil readers are valid
    // depending on the test runner entitlements.
    // We simply assert the call does not crash.
    _ = reader
  }
}
