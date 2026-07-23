import XCTest

@testable import LorvexDomain

final class PreferenceValueContractTests: XCTestCase {
  func testTimezoneRequiresAndNormalizesValidIanaString() throws {
    XCTAssertEqual(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefTimezone,
        value: .string("  America/Los_Angeles  ")
      ).get(),
      .string("America/Los_Angeles"))
    XCTAssertEqual(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefTimezone,
        value: .string("GMT")
      ).get(),
      .string("UTC"))
    for alias in ["PST", "GMT+5", "Etc/UTC", "US/Pacific"] {
      XCTAssertThrowsError(
        try PreferenceValueContract.normalize(
          key: PreferenceKeys.prefTimezone,
          value: .string(alias)
        ).get())
    }
    XCTAssertThrowsError(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefTimezone,
        value: .string("Mars/Olympus_Mons")
      ).get())
    XCTAssertThrowsError(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefTimezone,
        value: .bool(true)
      ).get())
  }

  func testWorkingHoursNormalizesBothAcceptedShapes() throws {
    let expected = JSONValue.object([
      "start": .string("09:00"),
      "end": .string("18:00"),
    ])
    XCTAssertEqual(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefWorkingHours,
        value: .string("9:00-18:00")
      ).get(), expected)
    XCTAssertEqual(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefWorkingHours,
        value: .object(["end": .string("18:00"), "start": .string("09:00")])
      ).get(), expected)
  }

  func testWorkingHoursRejectsInvalidOrNonIncreasingWindow() {
    for value: JSONValue in [
      .string("18:00-09:00"),
      .string("09:00-09:00"),
      .object(["start": .string("09:00"), "end": .string("25:00")]),
      .object([
        "start": .string("09:00"), "end": .string("18:00"), "extra": .bool(true),
      ]),
    ] {
      XCTAssertThrowsError(
        try PreferenceValueContract.normalize(
          key: PreferenceKeys.prefWorkingHours, value: value
        ).get())
    }
  }

  func testBooleanAndIdentifierPreferencesAreTyped() throws {
    XCTAssertEqual(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefRecordRawInput, value: .bool(false)
      ).get(), .bool(false))
    XCTAssertThrowsError(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefRecordRawInput, value: .string("false")
      ).get())
    XCTAssertEqual(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefDefaultListId, value: .string(" inbox ")
      ).get(), .string("inbox"))
    XCTAssertThrowsError(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefDefaultListId, value: .string("not-an-id")
      ).get())
  }

  func testUnknownAndControlPlaneKeysCannotBecomeOrdinaryRows() {
    XCTAssertThrowsError(
      try PreferenceValueContract.normalize(key: "future_key", value: .string("x")).get())
    XCTAssertThrowsError(
      try PreferenceValueContract.normalize(
        key: PreferenceKeys.prefAiChangelogRetentionPolicy,
        value: .string("maximum")
      ).get())
  }
}
