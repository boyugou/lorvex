import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class PayloadLoadersTests: XCTestCase {

  private let V = "0000000000000_0000_a0a0a0a0a0a0a0a0"
  private let T0 = "2026-04-01T00:00:00.000Z"
  private let T1 = "2026-04-02T00:00:00.000Z"
  private let HASH_A = String(repeating: "a", count: 64)
  private let HASH_B = String(repeating: "b", count: 64)

  private func seedList(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES ('list-default', 'L', ?1, ?2, ?2)
        """,
      arguments: [V, T0])
  }

  private func seedTask(_ db: Database, _ id: String) throws {
    try seedList(db)
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, list_id, version, created_at, updated_at) \
        VALUES (?1, 'T', 'list-default', ?2, ?3, ?3)
        """,
      arguments: [id, V, T0])
  }

  // MARK: - habit

  func testHabitPayloadRoundTripsThroughSelectColumns() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO habits
            (id, name, icon, color, cue, frequency_type, per_period_target, day_of_month,
             target_count, archived, created_at, updated_at, lookup_key, version)
          VALUES
            ('habit-1', 'Read', 'book', '#4477aa', 'after coffee', 'weekly', 1, NULL,
             2, 0, ?1, ?2, 'read', ?3)
          """,
        arguments: [T0, T1, V])
      // Weekday set materialized in the child (Monday-first 0=Mon, 2=Wed).
      try db.execute(
        sql: "INSERT INTO habit_weekdays (habit_id, weekday) VALUES ('habit-1', 0), ('habit-1', 2)")

      let payload = try XCTUnwrap(PayloadLoaders.loadHabitSyncPayload(db, habitId: "habit-1"))
      XCTAssertEqual(payload["id"].asString, "habit-1")
      XCTAssertEqual(payload["name"].asString, "Read")
      XCTAssertEqual(payload["icon"].asString, "book")
      XCTAssertEqual(payload["color"].asString, "#4477aa")
      XCTAssertEqual(payload["cue"].asString, "after coffee")
      XCTAssertEqual(payload["frequency_type"].asString, "weekly")
      // The weekday set rides inside the habit payload; frequency_value is gone.
      XCTAssertEqual(payload["weekdays"], .array([.int(0), .int(2)]))
      XCTAssertTrue(payload["frequency_value"].isNull)
      XCTAssertEqual(payload["per_period_target"].asInt, 1)
      XCTAssertTrue(payload["day_of_month"].isNull)
      XCTAssertEqual(payload["target_count"].asInt, 2)
      XCTAssertEqual(payload["archived"].asBool, false)
      XCTAssertEqual(payload["created_at"].asString, T0)
      XCTAssertEqual(payload["updated_at"].asString, T1)
      XCTAssertEqual(payload["position"].asInt, 0)
      XCTAssertEqual(payload["version"].asString, V)

      let row = try XCTUnwrap(
        Row.fetchOne(
          db, sql: "SELECT \(PayloadLoaders.habitSelectColumns) FROM habits WHERE id = ?1",
          arguments: ["habit-1"]))
      let streamed = PayloadLoaders.habitPayloadFromRow(row, weekdays: [.mon, .wed])
      XCTAssertEqual(payload, streamed)
    }
  }

  func testHabitPayloadEmitsJsonBoolForArchived() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, icon, color, cue, frequency_type, per_period_target,
            day_of_month, target_count, archived, version, created_at, updated_at)
          VALUES ('h-1', 'Read', NULL, NULL, NULL, 'daily', 1, NULL, 1, 1, ?1, ?2, ?2)
          """,
        arguments: [V, T0])
      let payload = try XCTUnwrap(PayloadLoaders.loadHabitSyncPayload(db, habitId: "h-1"))
      XCTAssertEqual(payload["id"].asString, "h-1")
      XCTAssertTrue(payload["icon"].isNull)
      XCTAssertEqual(payload["weekdays"], .array([]))
      XCTAssertTrue(payload["frequency_value"].isNull)
      XCTAssertEqual(payload["target_count"].asInt, 1)
      XCTAssertEqual(payload["archived"].asBool, true)
      XCTAssertEqual(payload["position"].asInt, 0)
      XCTAssertEqual(payload["version"].asString, V)
    }
  }

  // MARK: - task_checklist_item

  func testTaskChecklistItemPayloadIncludesVersion() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, "task-1")
      try db.execute(
        sql: """
          INSERT INTO task_checklist_items
            (id, task_id, position, text, completed_at, version, created_at, updated_at)
          VALUES
            ('check-1', 'task-1', 0, 'Step one', NULL, ?1, ?2, ?3)
          """,
        arguments: [V, T0, T1])

      let payload = try XCTUnwrap(
        PayloadLoaders.loadTaskChecklistItemSyncPayload(db, itemId: "check-1"))
      XCTAssertEqual(payload["id"].asString, "check-1")
      XCTAssertEqual(payload["task_id"].asString, "task-1")
      XCTAssertEqual(payload["position"].asInt, 0)
      XCTAssertEqual(payload["text"].asString, "Step one")
      XCTAssertTrue(payload["completed_at"].isNull)
      XCTAssertEqual(payload["version"].asString, V)
      XCTAssertEqual(payload["created_at"].asString, T0)
      XCTAssertEqual(payload["updated_at"].asString, T1)

      let streamed = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql:
            "SELECT \(PayloadLoaders.taskChecklistItemSelectColumns) FROM task_checklist_items WHERE id = ?1",
          arguments: ["check-1"]).map(PayloadLoaders.taskChecklistItemPayloadFromRow))
      XCTAssertEqual(payload, streamed)
    }
  }

  // MARK: - memory

  func testMemoryPayloadRoundTripsThroughSelectColumns() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: "INSERT INTO memories (id, key, content, version, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        arguments: ["mem-1", "k1", "hello", V, T0])
      let payload = try XCTUnwrap(PayloadLoaders.loadMemorySyncPayload(db, key: "k1"))
      XCTAssertEqual(payload["id"].asString, "mem-1")
      XCTAssertEqual(payload["key"].asString, "k1")
      XCTAssertEqual(payload["content"].asString, "hello")
      XCTAssertEqual(payload["version"].asString, V)
      XCTAssertEqual(payload["updated_at"].asString, T0)
      let streamed = try XCTUnwrap(
        Row.fetchOne(
          db, sql: "SELECT \(PayloadLoaders.memorySelectColumns) FROM memories WHERE key = ?1",
          arguments: ["k1"]).map(PayloadLoaders.memoryPayloadFromRow))
      XCTAssertEqual(payload, streamed)
    }
  }

  func testLoadMemorySyncPayloadReturnsNoneForMissingKey() throws {
    let store = try TestSupport.freshStore()
    try store.writer.read { db in
      XCTAssertNil(try PayloadLoaders.loadMemorySyncPayload(db, key: "nope"))
    }
  }

  // MARK: - tag / task_tag

  func testTaskTagPayloadCarriesVersion() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, "task-1")
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES ('tag-1', 'Work', 'work', ?1, ?2, ?2)
          """,
        arguments: [V, T0])
      try db.execute(
        sql: """
          INSERT INTO task_tags (task_id, tag_id, version, created_at)
          VALUES ('task-1', 'tag-1', ?1, ?2)
          """,
        arguments: [V, T0])
      let payload = try XCTUnwrap(
        PayloadLoaders.loadTaskTagSyncPayload(db, taskId: "task-1", tagId: "tag-1"))
      XCTAssertEqual(payload["task_id"].asString, "task-1")
      XCTAssertEqual(payload["tag_id"].asString, "tag-1")
      XCTAssertEqual(payload["version"].asString, V)
      XCTAssertEqual(payload["created_at"].asString, T0)
    }
  }

  // MARK: - task_calendar_event_link

  func testTaskCalendarEventLinkPayloadCarriesVersionAndUpdatedAt() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, "task-1")
      try db.execute(
        sql: """
          INSERT INTO calendar_events
            (id, title, start_date, start_time, all_day, event_type,
             recurrence_topology_version, content_version, version, created_at, updated_at)
          VALUES ('ev-1', 'Meet', '2026-04-05', '09:00', 0, 'event', ?1, ?1, ?1, ?2, ?2)
          """,
        arguments: [V, T0])
      try db.execute(
        sql: """
          INSERT INTO task_calendar_event_links
            (task_id, calendar_event_id, version, created_at, updated_at)
          VALUES ('task-1', 'ev-1', ?1, ?2, ?3)
          """,
        arguments: [V, T0, T1])
      let payload = try XCTUnwrap(
        PayloadLoaders.loadTaskCalendarEventLinkSyncPayload(
          db, taskId: "task-1", calendarEventId: "ev-1"))
      XCTAssertEqual(payload["task_id"].asString, "task-1")
      XCTAssertEqual(payload["calendar_event_id"].asString, "ev-1")
      XCTAssertEqual(payload["version"].asString, V)
      XCTAssertEqual(payload["created_at"].asString, T0)
      XCTAssertEqual(payload["updated_at"].asString, T1)
    }
  }

  // MARK: - habit_completion

  func testHabitCompletionPayloadCarriesVersion() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
          VALUES ('h-1', 'Read', 'daily', 1, 0, ?1, ?2, ?2)
          """,
        arguments: [V, T0])
      try db.execute(
        sql: """
          INSERT INTO habit_completions
            (habit_id, completed_date, value, note, version, created_at, updated_at)
          VALUES ('h-1', '2026-04-05', 1, 'good', ?1, ?2, ?2)
          """,
        arguments: [V, T0])
      let payload = try XCTUnwrap(
        PayloadLoaders.loadHabitCompletionSyncPayload(
          db, habitId: "h-1", completedDate: "2026-04-05"))
      XCTAssertEqual(payload["habit_id"].asString, "h-1")
      XCTAssertEqual(payload["completed_date"].asString, "2026-04-05")
      XCTAssertEqual(payload["value"].asInt, 1)
      XCTAssertEqual(payload["note"].asString, "good")
      XCTAssertEqual(payload["version"].asString, V)
    }
  }

  // MARK: - habit_reminder_policy

  func testHabitReminderPolicyPayloadEmitsJsonBoolForEnabled() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
          VALUES ('h-1', 'Read', 'daily', 1, 0, ?1, ?2, ?2)
          """,
        arguments: [V, T0])
      try db.execute(
        sql: """
          INSERT INTO habit_reminder_policies
            (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
          VALUES ('p-1', 'h-1', '07:00', 0, ?1, ?2, ?2)
          """,
        arguments: [V, T0])
      let payload = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql:
            "SELECT \(PayloadLoaders.habitReminderPolicySelectColumns) FROM habit_reminder_policies WHERE id = ?1",
          arguments: ["p-1"]).map(PayloadLoaders.habitReminderPolicyPayloadFromRow))
      XCTAssertEqual(payload["id"].asString, "p-1")
      XCTAssertEqual(payload["habit_id"].asString, "h-1")
      XCTAssertEqual(payload["reminder_time"].asString, "07:00")
      XCTAssertEqual(payload["enabled"].asBool, false)
      XCTAssertEqual(payload["version"].asString, V)
    }
  }

  // MARK: - preference

  func testPreferenceUpsertPayloadParsesCanonicalJson() throws {
    let payload = try PayloadLoaders.preferenceUpsertPayload(
      key: "theme", valueRaw: "\"dark\"", updatedAt: T0)
    XCTAssertEqual(payload["key"].asString, "theme")
    XCTAssertEqual(payload["value"].asString, "dark")
    XCTAssertEqual(payload["updated_at"].asString, T0)
  }

  func testPreferenceUpsertPayloadRejectsMalformedJson() {
    XCTAssertThrowsError(
      try PayloadLoaders.preferenceUpsertPayload(key: "theme", valueRaw: "{not json", updatedAt: T0)
    ) { error in
      XCTAssertTrue("\(error)".contains("theme"), "unexpected error: \(error)")
    }
  }

  func testPreferenceDeleteSnapshotCarriesVersion() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO preferences (key, value, updated_at, version)
          VALUES ('theme', '"dark"', ?1, ?2)
          """,
        arguments: [T0, V])
      let snap = try XCTUnwrap(PayloadLoaders.loadPreferenceDeleteSnapshot(db, key: "theme"))
      XCTAssertEqual(snap["key"].asString, "theme")
      XCTAssertEqual(snap["value"].asString, "\"dark\"")
      XCTAssertEqual(snap["version"].asString, V)
      XCTAssertEqual(snap["updated_at"].asString, T0)
    }
  }

  // MARK: - task_checklist_item round-trip

  func testTaskChecklistItemPayloadRoundTrip() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, "task-1")
      try db.execute(
        sql: """
          INSERT INTO task_checklist_items
            (id, task_id, position, text, completed_at, version, created_at, updated_at)
          VALUES ('cli-1', 'task-1', 0, 'do it', NULL, ?1, ?2, ?2)
          """,
        arguments: [V, T0])
      let payload = try XCTUnwrap(
        PayloadLoaders.loadTaskChecklistItemSyncPayload(db, itemId: "cli-1"))
      XCTAssertEqual(payload["id"].asString, "cli-1")
      XCTAssertEqual(payload["task_id"].asString, "task-1")
      XCTAssertEqual(payload["position"].asInt, 0)
      XCTAssertEqual(payload["text"].asString, "do it")
      XCTAssertTrue(payload["completed_at"].isNull)
      XCTAssertEqual(payload["created_at"].asString, T0)
      XCTAssertEqual(payload["updated_at"].asString, T0)
    }
  }

}
