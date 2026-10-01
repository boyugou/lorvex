import Foundation
import XCTest

@testable import LorvexCore

final class WeeklyReviewWindowLabelTests: XCTestCase {
  private func snapshot(windowTitle: String) -> WeeklyReviewSnapshot {
    WeeklyReviewSnapshot(
      windowTitle: windowTitle, completedThisWeek: 0, createdThisWeek: 0, overdueOpen: 0,
      deferredOpen: 0, someday: 0, estimateCoverageRatio: nil, topCompleted: [],
      frequentlyDeferred: [], topSomeday: [])
  }

  private let english = Locale(identifier: "en_US")

  func testWindowInsideOneMonthReadsAsOneRange() {
    let label = snapshot(windowTitle: "2026-09-22 - 2026-09-28").windowRangeLabel(locale: english)
    XCTAssertTrue(label.hasPrefix("September 22"), label)
    XCTAssertTrue(label.hasSuffix("28"), label)
    XCTAssertFalse(label.contains("2026"), label)
  }

  func testWindowAcrossMonthsNamesBoth() {
    let label = snapshot(windowTitle: "2026-09-29 - 2026-10-05").windowRangeLabel(locale: english)
    XCTAssertTrue(label.hasPrefix("September 29"), label)
    XCTAssertTrue(label.hasSuffix("October 5"), label)
  }

  func testOtherTitlesPassThrough() {
    XCTAssertEqual(snapshot(windowTitle: "This week").windowRangeLabel(locale: english), "This week")
    XCTAssertEqual(
      snapshot(windowTitle: "2026-09-28 - 2026-09-22").windowRangeLabel(locale: english),
      "2026-09-28 - 2026-09-22")
  }
}
