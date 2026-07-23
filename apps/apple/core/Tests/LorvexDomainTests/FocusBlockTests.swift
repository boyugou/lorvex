import XCTest

@testable import LorvexDomain

final class FocusBlockTests: XCTestCase {
  func testParseRoundTripsEveryVariant() {
    for variant in [FocusBlockType.task, .buffer, .event] {
      XCTAssertEqual(FocusBlockType.parse(variant.asString), variant)
    }
  }

  func testParseRejectsUnknownBlockType() {
    XCTAssertNil(FocusBlockType.parse("holiday"))
    XCTAssertNil(FocusBlockType.parse("Task"), "case-sensitive")
    XCTAssertNil(FocusBlockType.parse(""))
  }

  func testRequiresTaskIdOnlyForTaskVariant() {
    XCTAssertTrue(FocusBlockType.task.requiresTaskId)
    XCTAssertFalse(FocusBlockType.buffer.requiresTaskId)
    XCTAssertFalse(FocusBlockType.event.requiresTaskId)
  }

  func testEventSourceRoundTripsEveryVariant() {
    for source in FocusScheduleEventSource.allCases {
      XCTAssertEqual(FocusScheduleEventSource.parse(source.rawValue), source)
    }
    XCTAssertNil(FocusScheduleEventSource.parse("calendar"))
    XCTAssertNil(FocusScheduleEventSource.parse("Provider"))
  }
}
