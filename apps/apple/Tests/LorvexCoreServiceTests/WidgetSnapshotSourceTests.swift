import Foundation
import GRDB
import XCTest

@testable import LorvexCore

final class WidgetSnapshotSourceTests: XCTestCase {
  func testWidgetStatsAreNotTruncatedAtFiveHundredRows() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let firstBatch = (0..<500).map { TaskCreateDraft(title: "Open \($0)") }
    let first = try await service.batchCreateTasks(firstBatch)
    let last = try await service.batchCreateTasks([TaskCreateDraft(title: "Open 500")])
    let ids = (first + last).map(\.id)

    let openStats = try await service.loadWidgetStatsSource()
    XCTAssertEqual(openStats.actionableTasks.count, 501)

    let completion = try await service.batchCompleteTasks(ids: ids)
    XCTAssertEqual(completion.changedIDs.count, 501)
    let completedStats = try await service.loadWidgetStatsSource()
    XCTAssertEqual(completedStats.actionableTasks.count, 0)
    XCTAssertEqual(completedStats.completedTodayTasks.count, 501)
  }

  func testCompletedTodayUsesExactProductTimezoneSpringForwardWindow() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    _ = try await service.setPreference(key: "timezone", value: "America/Los_Angeles")
    let tasks = try await service.batchCreateTasks([
      TaskCreateDraft(title: "Immediately before product day"),
      TaskCreateDraft(title: "At inclusive product-day start"),
      TaskCreateDraft(title: "At exclusive product-day end"),
    ])
    _ = try await service.batchCompleteTasks(ids: tasks.map(\.id))

    // 2026-03-08 is the 23-hour spring-forward day in Los Angeles. Its exact
    // UTC interval is [08:00Z, 07:00Z next day); pin both boundaries so a
    // device-zone or unbounded query cannot satisfy this test accidentally.
    try service.write { db in
      try db.execute(
        sql: "UPDATE tasks SET completed_at = ? WHERE id = ?",
        arguments: ["2026-03-08T07:59:59.999Z", tasks[0].id])
      try db.execute(
        sql: "UPDATE tasks SET completed_at = ? WHERE id = ?",
        arguments: ["2026-03-08T08:00:00.000Z", tasks[1].id])
      try db.execute(
        sql: "UPDATE tasks SET completed_at = ? WHERE id = ?",
        arguments: ["2026-03-09T07:00:00.000Z", tasks[2].id])
    }

    let source = try await service.loadWidgetSnapshotSource(date: "2026-03-08")
    XCTAssertEqual(source.timezone, "America/Los_Angeles")
    let completedIDs = Set(try XCTUnwrap(source.stats).completedTodayTasks.map(\.id))
    XCTAssertEqual(completedIDs, Set([tasks[1].id]))
  }

  func testRequestedLogicalDayAnchorsTodayAndEveryWidgetSubdomain() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    // Keep this safely in the future so the fixture exercises an actual
    // unavailable-until boundary regardless of when the suite is run.
    let nextDay = try XCTUnwrap(LorvexDateFormatters.ymdUTC.date(from: "2099-05-24"))
    let hiddenUntilNextDay = try await service.createTask(
      TaskCreateDraft(
        title: "Hidden until the next logical day",
        availableFrom: nextDay))

    let before = try await service.loadWidgetSnapshotSource(date: "2099-05-23")
    let after = try await service.loadWidgetSnapshotSource(date: "2099-05-24")

    XCTAssertEqual(before.logicalDay, "2099-05-23")
    XCTAssertFalse(before.today.tasks.contains { $0.id == hiddenUntilNextDay.id })
    XCTAssertFalse(before.stats?.actionableTasks.contains { $0.id == hiddenUntilNextDay.id } == true)
    XCTAssertEqual(after.logicalDay, "2099-05-24")
    XCTAssertTrue(after.today.tasks.contains { $0.id == hiddenUntilNextDay.id })
    XCTAssertTrue(after.stats?.actionableTasks.contains { $0.id == hiddenUntilNextDay.id } == true)
  }

  func testProductionLogicalDayComesFromPersistedProductTimezone() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    _ = try await service.setPreference(key: "timezone", value: "Pacific/Kiritimati")
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
    formatter.dateFormat = "yyyy-MM-dd"
    let before = formatter.string(from: Date())

    let source = try await service.loadWidgetSnapshotSource(date: nil)

    let after = formatter.string(from: Date())
    XCTAssertTrue(
      source.logicalDay == before || source.logicalDay == after,
      "production source should use the persisted product timezone, not the caller's system day")
  }

  func testAllWidgetProjectionInputsComeFromOneSQLiteSnapshot() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lorvex-widget-source-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databasePath = directory.appendingPathComponent("lorvex.sqlite").path
    let schema = try schemaSQL()
    let source = SwiftLorvexCoreService(databasePath: databasePath, schemaSQL: schema)
    let peer = SwiftLorvexCoreService(databasePath: databasePath, schemaSQL: schema)
    _ = try await source.createList(name: "Before snapshot", description: nil)

    let afterTodayRead = expectation(description: "widget source read Today")
    let continueProjection = DispatchSemaphore(value: 0)
    let sourceTask = Task {
      try await SwiftLorvexCoreService.$afterWidgetTodayReadForTesting.withValue({
        afterTodayRead.fulfill()
        _ = continueProjection.wait(timeout: .now() + 5)
      }) {
        try await source.loadWidgetSnapshotSource(date: "2026-05-23")
      }
    }

    await fulfillment(of: [afterTodayRead], timeout: 5)
    let peerState = WidgetSourceOperationState()
    let peerTask = Task.detached {
      peerState.markStarted()
      defer { peerState.markCompleted() }
      return try await peer.createList(name: "Committed during projection", description: nil)
    }
    XCTAssertTrue(peerState.waitUntilStarted())
    XCTAssertFalse(
      peerState.waitUntilCompleted(timeout: 0.2),
      "a peer write committed while the widget projection transaction was paused")

    continueProjection.signal()
    let projected = try await sourceTask.value
    let committed = try await peerTask.value

    XCTAssertEqual(projected.logicalDay, "2026-05-23")
    XCTAssertFalse(projected.lists?.lists.contains { $0.id == committed.id } == true)
    let fresh = try await source.loadWidgetSnapshotSource(date: "2026-05-23")
    XCTAssertEqual(fresh.logicalDay, "2026-05-23")
    XCTAssertTrue(fresh.lists?.lists.contains { $0.id == committed.id } == true)
  }

  private func schemaSQL() throws -> String {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    return try String(contentsOf: schemaURL, encoding: .utf8)
  }
}

private final class WidgetSourceOperationState: @unchecked Sendable {
  private let condition = NSCondition()
  private var started = false
  private var completed = false

  func markStarted() {
    condition.lock()
    started = true
    condition.broadcast()
    condition.unlock()
  }

  func markCompleted() {
    condition.lock()
    completed = true
    condition.broadcast()
    condition.unlock()
  }

  func waitUntilStarted(timeout: TimeInterval = 5) -> Bool {
    wait(timeout: timeout) { started }
  }

  func waitUntilCompleted(timeout: TimeInterval) -> Bool {
    wait(timeout: timeout) { completed }
  }

  private func wait(timeout: TimeInterval, predicate: () -> Bool) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() {
      guard condition.wait(until: deadline) else { break }
    }
    return predicate()
  }
}
