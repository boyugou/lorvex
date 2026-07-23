import Foundation
import LorvexDomain
import XCTest

@testable import LorvexCore

/// Verifies the core→app row deserializers fail loud on a schema-contract
/// violation instead of fabricating a placeholder row. A decode miss at this
/// in-process, same-schema boundary means the app's own contract is broken, so
/// minting a random id / a "Untitled" title / an `.open` status for a terminal
/// task is the worst failure mode — these tests pin that it throws instead.
final class SwiftLorvexDeserializerFailLoudTests: XCTestCase {

  // MARK: - Helpers

  /// A minimal well-formed enriched-task object (id + title + status), the
  /// three fields `task(from:)` requires. Individual tests mutate one key to
  /// exercise a single contract violation in isolation.
  private func wellFormedTaskObject() -> [String: Any] {
    [
      "id": "task-1",
      "title": "Write the deserializer tests",
      "body": "notes body",
      "status": "open",
      "priority": 1,
      "tags": ["home", "urgent"],
      "depends_on": [],
      "checklist_items": [
        ["id": "chk-1", "task_id": "task-1", "position": 0, "text": "first step"] as [String: Any]
      ],
      "reminders": [
        ["id": "rem-1", "reminder_at": "2026-01-01T09:00:00.000Z"] as [String: Any]
      ],
    ]
  }

  /// Assert `expression` throws ``LorvexCoreError/malformedCoreData`` whose
  /// `path` equals `expectedPath`.
  private func assertMalformed<T>(
    path expectedPath: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: () throws -> T
  ) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
      guard case let LorvexCoreError.malformedCoreData(path, _) = error else {
        return XCTFail("expected .malformedCoreData, got \(error)", file: file, line: line)
      }
      XCTAssertEqual(path, expectedPath, file: file, line: line)
    }
  }

  // MARK: - Task: happy path (no regression)

  func testWellFormedTaskDecodesWithoutFabrication() throws {
    let task = try SwiftLorvexTaskDeserializers.task(from: wellFormedTaskObject())
    XCTAssertEqual(task.id, "task-1")
    XCTAssertEqual(task.title, "Write the deserializer tests")
    XCTAssertEqual(task.notes, "notes body")
    XCTAssertEqual(task.priority, .p1)
    XCTAssertEqual(task.status, .open)
    XCTAssertEqual(task.tags, ["home", "urgent"])
    XCTAssertEqual(task.checklistItems.map(\.id), ["chk-1"])
    XCTAssertEqual(task.checklistItems.first?.text, "first step")
    XCTAssertEqual(task.reminders.map(\.id), ["rem-1"])
  }

  // MARK: - Task: required fields

  func testMissingIdThrowsInsteadOfMintingUUID() {
    var object = wellFormedTaskObject()
    object.removeValue(forKey: "id")
    assertMalformed(path: "task.id") {
      try SwiftLorvexTaskDeserializers.task(from: object)
    }
  }

  func testNullIdThrows() {
    var object = wellFormedTaskObject()
    object["id"] = NSNull()
    assertMalformed(path: "task.id") {
      try SwiftLorvexTaskDeserializers.task(from: object)
    }
  }

  func testMissingTitleThrowsInsteadOfUntitled() {
    var object = wellFormedTaskObject()
    object.removeValue(forKey: "title")
    assertMalformed(path: "task.title") {
      try SwiftLorvexTaskDeserializers.task(from: object)
    }
  }

  // MARK: - Task: closed enums

  func testUnknownStatusThrowsInsteadOfCoercingToOpen() {
    var object = wellFormedTaskObject()
    object["status"] = "in_limbo"
    assertMalformed(path: "task.status") {
      try SwiftLorvexTaskDeserializers.task(from: object)
    }
  }

  func testUnknownPriorityTierThrowsInsteadOfCoercingToP2() {
    var object = wellFormedTaskObject()
    object["priority"] = 7
    assertMalformed(path: "task.priority") {
      try SwiftLorvexTaskDeserializers.task(from: object)
    }
  }

  /// `tasks.priority` is a nullable column and the model enum has no "no
  /// priority" case, so an absent/null tier is the one legitimate default
  /// (`.p2`) — this is optionality, not fabrication of a required value.
  func testAbsentPriorityDefaultsToP2() throws {
    var object = wellFormedTaskObject()
    object.removeValue(forKey: "priority")
    XCTAssertEqual(try SwiftLorvexTaskDeserializers.task(from: object).priority, .p2)

    object["priority"] = NSNull()
    XCTAssertEqual(try SwiftLorvexTaskDeserializers.task(from: object).priority, .p2)
  }

  // MARK: - Task: malformed array elements

  func testChecklistElementMissingIdThrowsWithIndexedPath() {
    var object = wellFormedTaskObject()
    object["checklist_items"] = [
      ["id": "chk-0", "task_id": "task-1", "position": 0, "text": "ok"] as [String: Any],
      ["task_id": "task-1", "position": 1, "text": "missing id"] as [String: Any],
    ]
    assertMalformed(path: "task.checklist_items[1].id") {
      try SwiftLorvexTaskDeserializers.task(from: object)
    }
  }

  func testChecklistElementWrongShapeThrows() {
    var object = wellFormedTaskObject()
    object["checklist_items"] = ["not an object"]
    assertMalformed(path: "task.checklist_items[0]") {
      try SwiftLorvexTaskDeserializers.task(from: object)
    }
  }

  func testReminderElementMissingReminderAtThrows() {
    var object = wellFormedTaskObject()
    object["reminders"] = [
      ["id": "rem-9"] as [String: Any]
    ]
    assertMalformed(path: "task.reminders[0].reminder_at") {
      try SwiftLorvexTaskDeserializers.task(from: object)
    }
  }

  func testStringArrayWithNonStringElementThrowsInsteadOfDropping() {
    var object = wellFormedTaskObject()
    object["tags"] = ["ok", 42]
    assertMalformed(path: "task.tags[1]") {
      try SwiftLorvexTaskDeserializers.task(from: object)
    }
  }

  // MARK: - Calendar event

  private func wellFormedEventValue() -> JSONValue {
    .object([
      "id": .string("evt-1"),
      "title": .string("Standup"),
      "start_date": .string("2026-01-02"),
      "start_time": .string("09:00"),
      "all_day": .bool(false),
      "event_type": .string("event"),
    ])
  }

  func testWellFormedEventDecodesWithoutFabrication() throws {
    let event = try SwiftLorvexCalendarDeserializers.event(wellFormedEventValue())
    XCTAssertEqual(event.id, "evt-1")
    XCTAssertEqual(event.title, "Standup")
    XCTAssertEqual(event.startDate, "2026-01-02")
  }

  func testEventMissingIdThrowsInsteadOfMintingUUID() {
    let value = JSONValue.object([
      "title": .string("Standup"),
      "start_date": .string("2026-01-02"),
    ])
    assertMalformed(path: "calendar_event.id") {
      try SwiftLorvexCalendarDeserializers.event(value)
    }
  }

  func testEventMissingStartDateThrowsInsteadOfEmptyString() {
    let value = JSONValue.object([
      "id": .string("evt-1"),
      "title": .string("Standup"),
    ])
    assertMalformed(path: "calendar_event.start_date") {
      try SwiftLorvexCalendarDeserializers.event(value)
    }
  }

  func testEventUnknownOccurrenceStateThrowsInsteadOfDroppingSeriesSemantics() {
    let value = JSONValue.object([
      "id": .string("evt-1"),
      "title": .string("Standup"),
      "start_date": .string("2026-01-02"),
      "occurrence_state": .string("postponed"),
    ])
    assertMalformed(path: "calendar_event.occurrence_state") {
      try SwiftLorvexCalendarDeserializers.event(value)
    }
  }

  // MARK: - Habit cadence

  func testValidCadenceDecodes() throws {
    XCTAssertEqual(
      try SwiftLorvexHabitDeserializers.cadence(
        frequencyType: "daily", weekdays: [], perPeriodTarget: 1, dayOfMonth: nil),
      .daily)
  }

  func testUnknownFrequencyTypeThrowsInsteadOfCoercingToDaily() {
    XCTAssertThrowsError(
      try SwiftLorvexHabitDeserializers.cadence(
        frequencyType: "fortnightly", weekdays: [], perPeriodTarget: 1, dayOfMonth: nil))
  }

  func testOutOfRangeWeekdayThrowsInsteadOfDropping() {
    XCTAssertThrowsError(
      try SwiftLorvexHabitDeserializers.cadence(
        frequencyType: "weekly", weekdays: [9], perPeriodTarget: 1, dayOfMonth: nil))
  }
}
