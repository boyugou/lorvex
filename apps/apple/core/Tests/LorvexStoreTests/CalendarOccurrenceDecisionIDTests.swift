import XCTest

@testable import LorvexStore

final class CalendarOccurrenceDecisionIDTests: XCTestCase {
  func testGoldenVectors() {
    XCTAssertEqual(
      CalendarOccurrenceDecisionID.make(
        seriesId: "01943a6d-b5c8-7e1f-9a12-3456789abcde",
        recurrenceGeneration: "1800000000000_0001_1111111111111111",
        recurrenceInstanceDate: "2026-08-10"),
      "87e42d64-adb1-89b6-8cd4-d9fe3a86b98b")
    XCTAssertEqual(
      CalendarOccurrenceDecisionID.make(
        seriesId: "550e8400-e29b-41d4-a716-446655440000",
        recurrenceGeneration: "1800000000000_9999_abcdefabcdefabcd",
        recurrenceInstanceDate: "9999-12-31"),
      "6d5ce6c1-ce46-8ce5-921d-b3ca3f827338")
  }

  func testIdentityIncludesGenerationAndOccurrenceDate() {
    let base = CalendarOccurrenceDecisionID.make(
      seriesId: "01943a6d-b5c8-7e1f-9a12-3456789abcde",
      recurrenceGeneration: "1800000000000_0001_1111111111111111",
      recurrenceInstanceDate: "2026-08-10")
    XCTAssertEqual(
      base,
      CalendarOccurrenceDecisionID.make(
        seriesId: "01943a6d-b5c8-7e1f-9a12-3456789abcde",
        recurrenceGeneration: "1800000000000_0001_1111111111111111",
        recurrenceInstanceDate: "2026-08-10"))
    XCTAssertNotEqual(
      base,
      CalendarOccurrenceDecisionID.make(
        seriesId: "01943a6d-b5c8-7e1f-9a12-3456789abcde",
        recurrenceGeneration: "1800000000001_0000_1111111111111111",
        recurrenceInstanceDate: "2026-08-10"))
    XCTAssertNotEqual(
      base,
      CalendarOccurrenceDecisionID.make(
        seriesId: "01943a6d-b5c8-7e1f-9a12-3456789abcde",
        recurrenceGeneration: "1800000000000_0001_1111111111111111",
        recurrenceInstanceDate: "2026-08-11"))
  }

  func testOutputIsCanonicalUuidV8WithRfcVariant() throws {
    let value = CalendarOccurrenceDecisionID.make(
      seriesId: "01943a6d-b5c8-7e1f-9a12-3456789abcde",
      recurrenceGeneration: "1800000000000_0001_1111111111111111",
      recurrenceInstanceDate: "2026-08-10")
    XCTAssertNotNil(UUID(uuidString: value))
    XCTAssertEqual(value.count, 36)
    XCTAssertEqual(value[value.index(value.startIndex, offsetBy: 14)], "8")
    XCTAssertTrue("89ab".contains(value[value.index(value.startIndex, offsetBy: 19)]))
    XCTAssertEqual(value, value.lowercased())
  }
}
