import XCTest

@testable import LorvexDomain

final class ParseIDWithSentinelTests: XCTestCase {
  private let validV7 = "01966a3f-7c8b-7d4e-8f3a-000000000001"

  func testRejectsEmptyAfterTrim() {
    let result = EntityID.parseIDWithSentinel("   ", field: "task_id")
    XCTAssertEqual(result, .failure(.empty("task_id")))
  }

  func testAcceptsUUIDV4AndV7() {
    let v4 = "f47ac10b-58cc-4372-a567-0e02b2c3d479"
    XCTAssertEqual(try EntityID.parseIDWithSentinel(v4, field: "task_id").get(), v4)
    XCTAssertEqual(try EntityID.parseIDWithSentinel(validV7, field: "task_id").get(), validV7)
  }

  func testTrimsSurroundingWhitespace() {
    let padded = "  \(validV7)  "
    XCTAssertEqual(try EntityID.parseIDWithSentinel(padded, field: "task_id").get(), validV7)
  }

  func testRejectsGarbageWithFieldLabel() {
    let result = EntityID.parseIDWithSentinel("not-a-uuid", field: "list_id")
    guard case let .failure(.invalidFormat(field, expected, actual)) = result else {
      return XCTFail("expected invalidFormat, got \(result)")
    }
    XCTAssertEqual(field, "list_id")
    XCTAssertEqual(expected, "UUID")
    XCTAssertEqual(actual, "not-a-uuid")
  }

  func testSentinelIsAcceptedWithoutUUIDShapeCheck() {
    let result = EntityID.parseIDWithSentinel("inbox", field: "list_id", sentinel: "inbox")
    XCTAssertEqual(try result.get(), "inbox")
  }

  func testSentinelDoesNotDisableUUIDValidationForOtherInputs() {
    let result = EntityID.parseIDWithSentinel("not-a-uuid", field: "list_id", sentinel: "inbox")
    guard case .failure(.invalidFormat) = result else {
      return XCTFail("expected invalidFormat, got \(result)")
    }
  }

  func testSentinelMatchRespectsTrim() {
    let result = EntityID.parseIDWithSentinel("  inbox  ", field: "list_id", sentinel: "inbox")
    XCTAssertEqual(try result.get(), "inbox")
  }
}

final class NewEntityIDStringTests: XCTestCase {
  func testProducesUUIDV7Shape() {
    let s = EntityID.newEntityIDString()
    XCTAssertEqual(s.count, 36, "UUID string should be 36 chars (8-4-4-4-12)")
    XCTAssertEqual(s.filter { $0 == "-" }.count, 4)
    // Canonical hyphenated lowercase shape parses.
    XCTAssertTrue(EntityID.isCanonicalUUID(s))
    // Version nibble at string index 14 must be '7'.
    let chars = Array(s)
    XCTAssertEqual(chars[14], "7", "must produce UUIDv7")
    // RFC 4122 variant nibble at string index 19 is in {8,9,a,b}.
    XCTAssertTrue("89ab".contains(chars[19]), "must carry RFC 4122 variant")
  }

  func testDeterministicFormatFromInjectedSeam() {
    // Fixed timestamp + fixed random tail → exact byte-for-byte format.
    let ms: UInt64 = 0x0196_6A3F_7C8B
    let tail: [UInt8] = [0xFF, 0xFF, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0]
    let s = EntityID.newEntityIDString(nowMilliseconds: ms, randomBytes: { tail })
    // bytes: 01 96 6a 3f 7c 8b | 7f ff | 92 34 | 56 78 9a bc de f0
    //  - byte6 = 0xFF -> (0xF & 0x0F)|0x70 = 0x7F  -> version nibble 7
    //  - byte8 = 0x12 -> (0x12 & 0x3F)|0x80 = 0x92 -> variant 0b10
    XCTAssertEqual(s, "01966a3f-7c8b-7fff-9234-56789abcdef0")
  }

  func testLexicographicOrderingMatchesChronological() {
    let earlier = EntityID.newEntityIDString(
      nowMilliseconds: 1000, randomBytes: { Array(repeating: 0xFF, count: 10) })
    let later = EntityID.newEntityIDString(
      nowMilliseconds: 2000, randomBytes: { Array(repeating: 0x00, count: 10) })
    XCTAssertLessThan(earlier, later, "later timestamp must sort after earlier despite random tail")
  }
}
