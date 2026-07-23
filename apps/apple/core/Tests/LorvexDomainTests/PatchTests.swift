import XCTest

@testable import LorvexDomain

final class PatchTests: XCTestCase {
  func testMapTransformsSetOnly() {
    XCTAssertEqual(Patch<UInt32>.unset.map { $0 + 1 }, .unset)
    XCTAssertEqual(Patch<UInt32>.clear.map { $0 + 1 }, .clear)
    XCTAssertEqual(Patch<UInt32>.set(5).map { $0 + 1 }, .set(6))
  }

  func testAccessors() {
    XCTAssertTrue(Patch<String>.unset.isUnset)
    XCTAssertFalse(Patch<String>.unset.isSetOrClear)
    XCTAssertTrue(Patch<String>.clear.isClear)
    XCTAssertTrue(Patch<String>.clear.isSetOrClear)
    XCTAssertEqual(Patch<String>.set("hi").value, "hi")
    XCTAssertNil(Patch<String>.unset.value)
    XCTAssertEqual(Patch<String>.set("hi").asBindValue, "hi")
    XCTAssertNil(Patch<String>.clear.asBindValue)
  }
}
