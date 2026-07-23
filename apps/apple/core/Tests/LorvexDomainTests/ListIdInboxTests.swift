import XCTest

@testable import LorvexDomain

final class ListIdInboxTests: XCTestCase {
  func testInboxSentinelValue() {
    XCTAssertEqual(ListId.inbox().rawValue, "inbox")
    XCTAssertEqual(ListId.inbox().rawValue, inboxSentinel)
    XCTAssertEqual(ListId.inboxSentinel, "inbox")
  }
}
