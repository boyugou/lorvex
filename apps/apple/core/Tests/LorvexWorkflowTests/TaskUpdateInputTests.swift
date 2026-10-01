import LorvexDomain
import XCTest

@testable import LorvexWorkflow

/// Tests for the `TaskUpdateInput` shape and the Unicode hygiene sanitizer.
final class TaskUpdateInputTests: XCTestCase {
  // Pins the `update_task` field names and their order.
  func testFieldsListIsTheUpdateTaskWireShape() {
    XCTAssertEqual(
      TaskUpdateInput.fields,
      [
        "id",
        "title",
        "body",
        "raw_input",
        "ai_notes",
        "status",
        "list_id",
        "tags_set",
        "tags_add",
        "tags_remove",
        "priority",
        "due_date",
        "estimated_minutes",
        "recurrence",
        "depends_on",
        "depends_on_add",
        "depends_on_remove",
        "planned_date",
        "planned_start_time",
        "planned_end_time",
        "available_from",
      ])
  }

  func testDefaultInitEmitsAllUnsetPatches() {
    let input = TaskUpdateInput(id: "task-1")
    XCTAssertTrue(input.title.isUnset)
    XCTAssertTrue(input.body.isUnset)
    XCTAssertTrue(input.rawInput.isUnset)
    XCTAssertTrue(input.aiNotes.isUnset)
    XCTAssertTrue(input.status.isUnset)
    XCTAssertTrue(input.listId.isUnset)
    XCTAssertNil(input.tagsSet)
    XCTAssertNil(input.tagsAdd)
    XCTAssertNil(input.tagsRemove)
    XCTAssertTrue(input.priority.isUnset)
    XCTAssertTrue(input.dueDate.isUnset)
    XCTAssertTrue(input.estimatedMinutes.isUnset)
    XCTAssertTrue(input.recurrence.isUnset)
    XCTAssertNil(input.dependsOn)
    XCTAssertNil(input.dependsOnAdd)
    XCTAssertNil(input.dependsOnRemove)
    XCTAssertTrue(input.plannedDate.isUnset)
    XCTAssertTrue(input.availableFrom.isUnset)
  }

  func testSanitizeStripsInvisibleCodepointsFromFreeText() {
    // U+200B (ZERO WIDTH SPACE) inside title / body / raw_input /
    // ai_notes is removed by the same UnicodeHygiene gate the
    // create path runs.
    var input = TaskUpdateInput(
      id: "task-1",
      title: .set("hello\u{200B}world"),
      body: .set("body\u{200B}text"),
      rawInput: .set("raw\u{200B}input"),
      aiNotes: .set("ai\u{200B}notes"))
    TaskUpdateSanitize.sanitizeInput(&input)
    XCTAssertEqual(input.title.value, "helloworld")
    XCTAssertEqual(input.body.value, "bodytext")
    XCTAssertEqual(input.rawInput.value, "rawinput")
    XCTAssertEqual(input.aiNotes.value, "ainotes")
  }

  func testSanitizePreservesUnsetAndClear() {
    var input = TaskUpdateInput(
      id: "task-1",
      title: .clear,
      body: .unset)
    TaskUpdateSanitize.sanitizeInput(&input)
    XCTAssertTrue(input.title.isClear)
    XCTAssertTrue(input.body.isUnset)
  }

  func testSanitizeAppliesToTagVectors() {
    var input = TaskUpdateInput(
      id: "task-1",
      tagsSet: ["foo\u{200B}", "bar"],
      tagsAdd: ["baz\u{200B}qux"],
      tagsRemove: ["zap"])
    TaskUpdateSanitize.sanitizeInput(&input)
    XCTAssertEqual(input.tagsSet, ["foo", "bar"])
    XCTAssertEqual(input.tagsAdd, ["bazqux"])
    XCTAssertEqual(input.tagsRemove, ["zap"])
  }

  func testSanitizePreservesNilTagVectors() {
    var input = TaskUpdateInput(id: "task-1")
    TaskUpdateSanitize.sanitizeInput(&input)
    XCTAssertNil(input.tagsSet)
    XCTAssertNil(input.tagsAdd)
    XCTAssertNil(input.tagsRemove)
  }
}
