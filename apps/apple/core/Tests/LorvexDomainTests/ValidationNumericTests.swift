import XCTest

@testable import LorvexDomain

final class ValidationNumericTests: XCTestCase {
  func assertOk(_ r: Result<Void, ValidationError>, _ msg: String = "", line: UInt = #line) {
    if case .failure(let e) = r { XCTFail("\(msg): \(e)", line: line) }
  }
  func assertErr(_ r: Result<Void, ValidationError>, line: UInt = #line) {
    if case .success = r { XCTFail("expected error", line: line) }
  }

  func testPriorityValidRange() {
    for p in ValidationLimits.priorityMin...ValidationLimits.priorityMax {
      assertOk(ValidationNumeric.validatePriority(p), "priority \(p)")
    }
  }

  func testPriorityTooLow() {
    assertFailure(
      ValidationNumeric.validatePriority(0),
      .outOfRange(
        field: "priority", min: ValidationLimits.priorityMin, max: ValidationLimits.priorityMax,
        actual: 0))
  }

  func testPriorityTooHigh() {
    assertFailure(
      ValidationNumeric.validatePriority(5),
      .outOfRange(
        field: "priority", min: ValidationLimits.priorityMin, max: ValidationLimits.priorityMax,
        actual: 5))
  }

  func testPriorityNegative() { assertErr(ValidationNumeric.validatePriority(-1)) }

  func testEstimatedMinutesValid() { assertOk(ValidationNumeric.validateEstimatedMinutes(60)) }
  func testEstimatedMinutesZeroIsRejected() { assertErr(ValidationNumeric.validateEstimatedMinutes(0)) }
  func testEstimatedMinutesOneIsMinimum() { assertOk(ValidationNumeric.validateEstimatedMinutes(1)) }
  func testEstimatedMinutesMax() {
    assertOk(ValidationNumeric.validateEstimatedMinutes(ValidationLimits.maxEstimatedMinutes))
  }
  func testEstimatedMinutesNegative() { assertErr(ValidationNumeric.validateEstimatedMinutes(-1)) }
  func testEstimatedMinutesOverMax() {
    assertErr(ValidationNumeric.validateEstimatedMinutes(ValidationLimits.maxEstimatedMinutes + 1))
  }

  func testMoodValidRange() {
    for v in ValidationLimits.moodMin...ValidationLimits.moodMax {
      assertOk(ValidationNumeric.validateMood(v), "mood \(v)")
    }
  }
  func testMoodTooLow() { assertErr(ValidationNumeric.validateMood(0)) }
  func testMoodTooHigh() { assertErr(ValidationNumeric.validateMood(6)) }

  func testReminderWindowValid() { assertOk(ValidationNumeric.validateReminderWindow(3600)) }
  func testReminderWindowZero() { assertOk(ValidationNumeric.validateReminderWindow(0)) }
  func testReminderWindowMax() {
    assertOk(ValidationNumeric.validateReminderWindow(ValidationLimits.maxReminderWindowSeconds))
  }
  func testReminderWindowNegative() { assertErr(ValidationNumeric.validateReminderWindow(-1)) }
  func testReminderWindowOverMax() {
    assertErr(ValidationNumeric.validateReminderWindow(ValidationLimits.maxReminderWindowSeconds + 1))
  }
}
