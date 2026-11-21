import XCTest

final class ReviewTomorrowPlanTests: XCTestCase {
  @MainActor func testPreviewCancelMoveSubsetAndUndo() throws {
    continueAfterFailure = false
    let app = openPlanner()
    let plan = app.buttons["review.day.stillOpen.tomorrow"]
    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'review.plan.task.'"))
    let forecast = app.staticTexts["review.plan.forecast"]
    XCTAssertTrue(forecast.waitForExistence(timeout: 8))
    let original = rows.allElementsBoundByIndex.map(\.identifier)
    XCTAssertGreaterThanOrEqual(original.count, 2)
    let held = try XCTUnwrap(rows.allElementsBoundByIndex.first { $0.label.contains("Review the Q3") })
    let heldID = held.identifier
    let initial = forecast.label
    held.tap()
    XCTAssertNotEqual(forecast.label, initial)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Choosing tomorrow"
    shot.lifetime = .keepAlways
    add(shot)
    let agenda = app.descendants(matching: .any).matching(identifier: "review.plan.agenda").firstMatch
    agenda.tap()
    XCTAssertTrue(app.staticTexts["Buy groceries for the week"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["review.plan.cancel"].tap()
    plan.tap()
    XCTAssertEqual(forecast.label, initial)
    for row in rows.allElementsBoundByIndex { row.tap() }
    let move = app.buttons["review.plan.move"]
    XCTAssertFalse(move.isEnabled)
    app.buttons[heldID].tap()
    move.tap()
    let undo = app.buttons["mobile.undo.button"]
    XCTAssertTrue(undo.waitForExistence(timeout: 5))
    undo.tap()
    plan.tap()
    XCTAssertTrue(forecast.waitForExistence(timeout: 8))
    XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.identifier)), Set(original))
    XCTAssertEqual(forecast.label, initial)
  }

  @MainActor func testLargeTextKeepsSelectionAndConfirmationReachable() throws {
    continueAfterFailure = false
    let app = openPlanner(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    let forecast = app.staticTexts["review.plan.forecast"]
    XCTAssertTrue(forecast.waitForExistence(timeout: 8))
    let move = app.buttons["review.plan.move"]
    XCTAssertTrue(move.isHittable)
    let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'review.plan.task.' AND label CONTAINS 'Q3'")).firstMatch
    let list = app.collectionViews.firstMatch
    for _ in 0..<6 where !row.isHittable { list.swipeUp() }
    XCTAssertTrue(row.isHittable)
    row.tap()
    XCTAssertFalse(row.isSelected)
    XCTAssertTrue(move.isHittable)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Selection at largest text size"
    shot.lifetime = .keepAlways
    add(shot)
    app.buttons["review.plan.cancel"].tap()
  }

  @MainActor private func openPlanner(arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-setupCompleted", "YES", "-lorvexSeedSampleData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launchArguments += arguments
    app.launch()
    let tab = app.buttons["Review"].firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 15))
    tab.tap()
    let plan = app.buttons["review.day.stillOpen.tomorrow"]
    for _ in 0..<6 where !plan.isHittable { app.swipeUp() }
    XCTAssertTrue(plan.isHittable)
    plan.tap()
    return app
  }
}
