import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// N4: a `timezone` preference change re-materializes each active task
/// reminder's `reminder_at` from its stored wall-clock anchor
/// (`original_local_time` + `original_tz`), so "9 AM local" survives the switch
/// instead of the old UTC instant staying pinned. Exercised against the on-disk
/// `SwiftLorvexCoreService` over an in-memory GRDB store.
final class ReminderTimezoneAnchorTests: XCTestCase {
  private func makeServiceAndStore() throws -> (SwiftLorvexCoreService, LorvexStore) {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return (SwiftLorvexCoreService(store: store), store)
  }

  private func instant(_ raw: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw) ?? Date(timeIntervalSince1970: 0)
  }

  private func reminderRow(_ store: LorvexStore, taskID: String) throws -> Row {
    try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT reminder_at, original_local_time, original_tz
          FROM task_reminders WHERE task_id = ?
          """,
        arguments: [taskID])!
    }
  }

  /// The wall-clock intent survives a timezone change: a reminder anchored to
  /// "09:00 America/New_York" becomes 09:00 America/Los_Angeles on the same
  /// calendar day (a 3-hour eastward shift in UTC), and the anchor's stored zone
  /// advances to the new preference.
  func testTimezoneChangeReanchorsActiveReminderWallClock() async throws {
    let (service, store) = try makeServiceAndStore()
    _ = try await service.setPreference(key: "timezone", value: "\"America/New_York\"")
    let task = try await service.createTask(title: "Standup", notes: "")
    // 13:00Z on 2026-06-22 is 09:00 EDT (UTC-4) in New York.
    _ = try await service.addTaskReminder(taskID: task.id, reminderAt: "2026-06-22T13:00:00Z")

    let before = try reminderRow(store, taskID: task.id)
    XCTAssertEqual(before["original_local_time"], "09:00")
    XCTAssertEqual(before["original_tz"], "America/New_York")

    _ = try await service.setPreference(key: "timezone", value: "\"America/Los_Angeles\"")

    let after = try reminderRow(store, taskID: task.id)
    let reanchored: String = after["reminder_at"]
    // 09:00 PDT (UTC-7) on the same day == 16:00Z.
    XCTAssertEqual(SyncTimestamp.parse(reanchored)?.date, instant("2026-06-22T16:00:00Z"))
    XCTAssertEqual(after["original_tz"], "America/Los_Angeles")
  }

  /// Setting the preference to the same zone (or one a reminder is already
  /// anchored to) is a no-op for the instant, so an idempotent apply doesn't
  /// drift the reminder.
  func testSameTimezoneIsNoOp() async throws {
    let (service, store) = try makeServiceAndStore()
    _ = try await service.setPreference(key: "timezone", value: "\"America/New_York\"")
    let task = try await service.createTask(title: "Standup", notes: "")
    _ = try await service.addTaskReminder(taskID: task.id, reminderAt: "2026-06-22T13:00:00Z")
    let before: String = try reminderRow(store, taskID: task.id)["reminder_at"]

    _ = try await service.setPreference(key: "timezone", value: "\"America/New_York\"")

    let after: String = try reminderRow(store, taskID: task.id)["reminder_at"]
    XCTAssertEqual(before, after)
  }

  /// A reminder with no wall-clock anchor (written while no timezone preference
  /// was set) is a fixed absolute instant and is left untouched by a later
  /// timezone change — the anchor columns are the opt-in signal for re-anchoring.
  func testUnanchoredReminderIsLeftAbsolute() async throws {
    let (service, store) = try makeServiceAndStore()
    // No timezone preference set → the writer resolves a nil anchor.
    let task = try await service.createTask(title: "Standup", notes: "")
    _ = try await service.addTaskReminder(taskID: task.id, reminderAt: "2026-06-22T13:00:00Z")
    let before = try reminderRow(store, taskID: task.id)
    XCTAssertNil(before["original_tz"] as String?)
    let originalInstant: String = before["reminder_at"]

    _ = try await service.setPreference(key: "timezone", value: "\"America/Los_Angeles\"")

    let after: String = try reminderRow(store, taskID: task.id)["reminder_at"]
    XCTAssertEqual(after, originalInstant)
  }

  /// L2: a reminder whose anchored wall time lands in the new zone's
  /// spring-forward gap is re-anchored to that day's first valid instant (not
  /// left pinned to the stale old-zone instant), and its `original_tz` still
  /// advances — preserving the anchor invariant later defers rely on.
  func testTimezoneChangeReanchorsReminderLandingInSpringForwardGap() async throws {
    let (service, store) = try makeServiceAndStore()
    // Arizona has no DST, so 09:30Z on 2026-03-08 is a stable 02:30 MST (UTC-7).
    _ = try await service.setPreference(key: "timezone", value: "\"America/Phoenix\"")
    let task = try await service.createTask(title: "Early alarm", notes: "")
    _ = try await service.addTaskReminder(taskID: task.id, reminderAt: "2026-03-08T09:30:00Z")

    let before = try reminderRow(store, taskID: task.id)
    XCTAssertEqual(before["original_local_time"], "02:30")
    XCTAssertEqual(before["original_tz"], "America/Phoenix")

    // New York springs forward at 02:00 on 2026-03-08, so the 02:30 wall time
    // does not exist that day. The re-anchor resolves it to the day's first
    // valid instant (00:00 EST == 05:00Z) and advances the anchor zone rather
    // than leaving the old 09:30Z instant with a stale "America/Phoenix" anchor.
    _ = try await service.setPreference(key: "timezone", value: "\"America/New_York\"")

    let after = try reminderRow(store, taskID: task.id)
    let reanchored: String = after["reminder_at"]
    XCTAssertEqual(SyncTimestamp.parse(reanchored)?.date, instant("2026-03-08T05:00:00Z"))
    XCTAssertEqual(after["original_tz"], "America/New_York")
  }
}
