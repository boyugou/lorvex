import XCTest

@testable import LorvexRuntime

/// Smoke test ensuring the target module remains linkable.
final class LorvexRuntimeTargetTests: XCTestCase {
  func testTargetCompiles() {
    XCTAssertEqual(LorvexRuntime.version, 1)
  }
}
