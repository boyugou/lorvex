import XCTest

@testable import LorvexSync

/// Smoke test ensuring the target module remains linkable.
final class LorvexSyncTargetTests: XCTestCase {
  func testTargetCompiles() {
    XCTAssertEqual(LorvexSync.version, 1)
  }
}
