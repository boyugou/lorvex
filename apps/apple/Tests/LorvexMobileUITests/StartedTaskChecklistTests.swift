import XCTest

final class StartedTaskChecklistTests: XCTestCase {
  @MainActor
  func testAddCompleteAndReopenTheFirstStepOfAStartedTask() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
    app.buttons["Capture"].firstMatch.tap()
    let field = app.descendants(matching: .any).matching(identifier: "mobileCapture.title").firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 8))
    field.tap()
    field.typeText("Check the transcript " + UUID().uuidString.prefix(6))
    app.buttons["mobileCapture.confirm"].tap()
    let receipt = app.buttons["capture.receipt.button"]
    XCTAssertTrue(receipt.waitForExistence(timeout: 10))
    receipt.tap()

    let start = app.buttons["task.detail.start"]
    XCTAssertTrue(start.waitForExistence(timeout: 8))
    start.tap()
    let add = app.buttons["task.detail.add"]
    XCTAssertTrue(add.waitForExistence(timeout: 5))
    add.tap()
    app.buttons["Checklist"].tap()
    let composer = app.textFields["task.detail.checklist.composer"]
    XCTAssertTrue(composer.waitForExistence(timeout: 5))
    composer.tap()
    let instruction = "Verify the quoted sentence"
    composer.typeText(instruction + "\n")

    let step = app.buttons.matching(NSPredicate(format: "label == %@", instruction)).firstMatch
    XCTAssertTrue(step.waitForExistence(timeout: 8))
    XCTAssertEqual(step.value as? String, "Not Completed")
    step.tap()
    XCTAssertTrue(step.waitForNonExistence(timeout: 8))
    let completed = app.buttons.containing(.staticText, identifier: "task.detail.checklist.completed").firstMatch
    XCTAssertTrue(completed.isHittable)
    completed.tap()
    XCTAssertTrue(step.waitForExistence(timeout: 5))
    XCTAssertEqual(step.value as? String, "Completed")
    step.tap()
    let pendingAgain = NSPredicate(format: "value == %@", "Not Completed")
    expectation(for: pendingAgain, evaluatedWith: step)
    waitForExpectations(timeout: 8)
    XCTAssertFalse(completed.exists)
  }
}
