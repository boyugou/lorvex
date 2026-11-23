import XCTest

/// The weekly journal's filter menu draws one line of text, under half the
/// height a finger needs. Its touch region reaches above and below the label,
/// so the menu opens from a tap just inside either edge of that region, where
/// the label draws nothing.
final class ReviewWeekFilterTests: XCTestCase {
  @MainActor
  func testFilterOpensFromTheEdgesOfItsTouchRegion() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      "-lorvexSeedSampleData", "-lorvexOpenURL", "lorvex://tab/review/week",
    ]
    app.launch()
    let filter = app.buttons["review.week.filter"]
    XCTAssertTrue(filter.waitForExistence(timeout: 20), app.debugDescription)
    XCTAssertGreaterThanOrEqual(filter.frame.height, 44)

    // Each choice names the option the next tap must find the menu showing.
    for (edge, choice) in [(0.05, "Wins"), (0.95, "All")] {
      filter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: edge)).tap()
      let option = app.buttons[choice].firstMatch
      XCTAssertTrue(
        option.waitForExistence(timeout: 5),
        "no menu from a tap at \(edge) of the region's height: \(filter.frame)")
      option.tap()
      let chosen = NSPredicate(format: "label == %@", choice)
      XCTAssertEqual(
        XCTWaiter.wait(
          for: [XCTNSPredicateExpectation(predicate: chosen, object: filter)], timeout: 5),
        .completed, filter.debugDescription)
    }
  }
}
