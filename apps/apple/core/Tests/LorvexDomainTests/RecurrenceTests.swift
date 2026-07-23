import XCTest

@testable import LorvexDomain

/// Ports `recurrence/tests.rs` — `generateInstanceKey` byte-for-byte parity.
final class RecurrenceTests: XCTestCase {
  func testFormatIsCorrect() {
    let key = Recurrence.generateInstanceKey(
      recurrenceGroupID: "grp-abc", canonicalOccurrenceDate: "2026-04-01")
    XCTAssertEqual(key, "grp-abc:2026-04-01")
  }

  func testReturnsNoneForEmptyGroupID() {
    XCTAssertNil(
      Recurrence.generateInstanceKey(recurrenceGroupID: "", canonicalOccurrenceDate: "2026-03-25"))
  }

  func testDeterministicAcrossDevices() {
    let groupID = "01966a3f-7c8b-7d4e-8f3a-000000000001"
    let date = "2026-03-25"
    let a = Recurrence.generateInstanceKey(recurrenceGroupID: groupID, canonicalOccurrenceDate: date)
    let b = Recurrence.generateInstanceKey(recurrenceGroupID: groupID, canonicalOccurrenceDate: date)
    XCTAssertEqual(a, b)
    XCTAssertNotNil(a)
  }

  func testInstanceKeyFormat() {
    let key = Recurrence.generateInstanceKey(
      recurrenceGroupID: "group-1", canonicalOccurrenceDate: "2026-04-05")
    XCTAssertEqual(key, "group-1:2026-04-05")
  }

  func testRejectsNonCanonicalDate() {
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group-1", canonicalOccurrenceDate: "not-a-date"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group-1", canonicalOccurrenceDate: "2026-4-5"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group-1", canonicalOccurrenceDate: "2026-04-05T00:00"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(recurrenceGroupID: "group-1", canonicalOccurrenceDate: ""))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group-1", canonicalOccurrenceDate: "2026/04/05"))
  }

  func testRejectsOutOfRangeCalendarDates() {
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group", canonicalOccurrenceDate: "2026-13-99"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group", canonicalOccurrenceDate: "2026-00-01"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group", canonicalOccurrenceDate: "2026-02-30"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group", canonicalOccurrenceDate: "2025-02-29"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group", canonicalOccurrenceDate: "2026-12-32"))
    XCTAssertNotNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "group", canonicalOccurrenceDate: "2024-02-29"))
  }

  func testRejectsDangerousCharactersInGroupID() {
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "grp:colon", canonicalOccurrenceDate: "2026-04-05"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "grp space", canonicalOccurrenceDate: "2026-04-05"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "grp%pct", canonicalOccurrenceDate: "2026-04-05"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "grp_under", canonicalOccurrenceDate: "2026-04-05"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "grp\nlf", canonicalOccurrenceDate: "2026-04-05"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "grp\tab", canonicalOccurrenceDate: "2026-04-05"))
    XCTAssertNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "grp\u{0}nul", canonicalOccurrenceDate: "2026-04-05"))
    XCTAssertNotNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "01966a3f-7c8b-7d4e-8f3a-000000000001",
        canonicalOccurrenceDate: "2026-04-05"))
    XCTAssertNotNil(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: "grp-abc", canonicalOccurrenceDate: "2026-04-05"))
  }
}
