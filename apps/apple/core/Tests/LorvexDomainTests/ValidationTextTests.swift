import XCTest

@testable import LorvexDomain

final class ValidationTextTests: XCTestCase {
  func assertOk(_ r: Result<Void, ValidationError>, _ msg: String = "", line: UInt = #line) {
    if case .failure(let e) = r { XCTFail("\(msg): \(e)", line: line) }
  }
  func assertErr(_ r: Result<Void, ValidationError>, line: UInt = #line) {
    if case .success = r { XCTFail("expected error", line: line) }
  }

  func testTitleValid() { assertOk(ValidationText.validateTitle("Buy groceries")) }

  func testTitleAtMaxLength() {
    let title = String(repeating: "a", count: ValidationLimits.maxTitleLength)
    assertOk(ValidationText.validateTitle(title))
  }

  func testTitleEmpty() {
    assertFailure(ValidationText.validateTitle(""), .empty("title"))
  }

  func testTitleWhitespaceOnly() {
    assertFailure(ValidationText.validateTitle("   \t\n  "), .empty("title"))
  }

  func testTitleTooLong() {
    let title = String(repeating: "a", count: ValidationLimits.maxTitleLength + 1)
    assertFailure(
      ValidationText.validateTitle(title),
      .tooLong(
        field: "title", max: ValidationLimits.maxTitleLength,
        actual: ValidationLimits.maxTitleLength + 1))
  }

  func testTitleUnicodeValid() { assertOk(ValidationText.validateTitle("工作计划 🎯")) }

  func testTitlePureInvisibleRejects() {
    let title = "\u{200B}\u{FEFF}\u{202E}\u{2060}"
    assertFailure(ValidationText.validateTitle(title), .empty("title"))
  }

  func testTitleZwsPaddedXRejects() {
    let title = String(repeating: "x\u{200B}", count: ValidationLimits.maxTitleLength)
    assertErr(ValidationText.validateTitle(title))
  }

  func testTitleAtMaxLengthOfMultiByteCodepointsPasses() {
    let title = String(repeating: "🎯", count: ValidationLimits.maxTitleLength)
    XCTAssertEqual(title.unicodeScalars.count, ValidationLimits.maxTitleLength)
    assertOk(ValidationText.validateTitle(title))
  }

  /// A body is bounded by BOTH caps: the codepoint limit (UX-facing) and the
  /// canonical-escaped byte budget (wire-size). Codepoint-max ASCII passes;
  /// multi-byte content passes exactly at the byte budget and rejects one
  /// codepoint past it.
  func testBodyDualCapContract() {
    assertOk(
      ValidationText.validateBody(String(repeating: "a", count: ValidationLimits.maxBodyLength)))

    let threeBytesEach = PayloadByteBudget.longTextEscapedBytes / 3
    assertOk(ValidationText.validateBody(String(repeating: "文", count: threeBytesEach)))
    guard
      case .failure(.tooLong(_, let max, _)) = ValidationText.validateBody(
        String(repeating: "文", count: threeBytesEach + 1))
    else {
      return XCTFail("one codepoint past the byte budget must reject")
    }
    XCTAssertEqual(max, PayloadByteBudget.longTextEscapedBytes, "the rejection is byte-denominated")
  }

  func testBodyOverMaxCodepointsRejected() {
    let body = String(repeating: "文", count: ValidationLimits.maxBodyLength + 1)
    guard case .failure(.tooLong(_, _, let actual)) = ValidationText.validateBody(body) else {
      return XCTFail("expected tooLong")
    }
    XCTAssertEqual(actual, ValidationLimits.maxBodyLength + 1)
  }

  func testBodyValid() { assertOk(ValidationText.validateBody("Some notes here.")) }
  func testBodyEmptyIsOk() { assertOk(ValidationText.validateBody("")) }

  func testBodyAtMaxLength() {
    let body = String(repeating: "x", count: ValidationLimits.maxBodyLength)
    assertOk(ValidationText.validateBody(body))
  }

  func testBodyTooLong() {
    let body = String(repeating: "x", count: ValidationLimits.maxBodyLength + 1)
    assertFailure(
      ValidationText.validateBody(body),
      .tooLong(
        field: "body", max: ValidationLimits.maxBodyLength,
        actual: ValidationLimits.maxBodyLength + 1))
  }

  func testBodyVisuallyEmptyRejects() {
    let body = "\u{200B}\u{FEFF}\u{202E}\u{2060}"
    assertFailure(ValidationText.validateBody(body), .empty("body"))
  }

  func testBodyZwsPaddedRepeatRejects() {
    let body = String(repeating: "\u{200B}", count: 1024)
    assertFailure(ValidationText.validateBody(body), .empty("body"))
  }

  func testTagNameValid() { assertOk(ValidationText.validateTagName("work")) }

  func testTagNameEmpty() {
    assertFailure(ValidationText.validateTagName(""), .empty("tag_name"))
  }

  func testTagNameWhitespaceOnly() {
    assertFailure(ValidationText.validateTagName("   "), .empty("tag_name"))
  }

  func testTagNameTooLong() {
    let name = String(repeating: "a", count: ValidationLimits.maxTagNameLength + 1)
    assertFailure(
      ValidationText.validateTagName(name),
      .tooLong(
        field: "tag_name", max: ValidationLimits.maxTagNameLength,
        actual: ValidationLimits.maxTagNameLength + 1))
  }

  func testTagNameAtMax() {
    let name = String(repeating: "a", count: ValidationLimits.maxTagNameLength)
    assertOk(ValidationText.validateTagName(name))
  }

  func testTagNameUnicode() { assertOk(ValidationText.validateTagName("工作")) }

  func testTagNameVisuallyEmptyRejects() {
    let name = "\u{200B}\u{FEFF}\u{202E}\u{2060}"
    assertFailure(ValidationText.validateTagName(name), .empty("tag_name"))
  }
}
