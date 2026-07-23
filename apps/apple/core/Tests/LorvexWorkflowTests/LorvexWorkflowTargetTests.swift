import XCTest

@testable import LorvexWorkflow

/// Smoke test ensuring the target module remains linkable.
final class LorvexWorkflowTargetTests: XCTestCase {
  func testTargetCompiles() {
    XCTAssertEqual(LorvexWorkflow.version, 1)
  }
}
