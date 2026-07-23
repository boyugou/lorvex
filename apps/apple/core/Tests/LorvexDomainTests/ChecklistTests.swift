import XCTest

@testable import LorvexDomain

final class ChecklistTests: XCTestCase {
  func testValidateChineseTextAtMaxCodepointsPasses() {
    let text = String(repeating: "工", count: maxTaskChecklistItemTextLength)
    XCTAssertEqual(text.unicodeScalars.count, maxTaskChecklistItemTextLength)
    XCTAssertGreaterThan(
      text.utf8.count, maxTaskChecklistItemTextLength,
      "byte length should exceed codepoint cap so this test exercises the codepoint path")
    XCTAssertNoThrow(try validateTaskChecklistItemText(text))
  }

  func testValidateChineseTextOnePastMaxCodepointsRejects() {
    let text = String(repeating: "工", count: maxTaskChecklistItemTextLength + 1)
    do {
      try validateTaskChecklistItemText(text)
      XCTFail("expected TooLong")
    } catch let ValidationError.tooLong(field, max, actual) {
      XCTAssertEqual(field, "task_checklist_item.text")
      XCTAssertEqual(max, maxTaskChecklistItemTextLength)
      XCTAssertEqual(
        actual, maxTaskChecklistItemTextLength + 1,
        "actual must be reported in codepoints, not bytes")
    } catch {
      XCTFail("expected TooLong, got \(error)")
    }
  }
}
