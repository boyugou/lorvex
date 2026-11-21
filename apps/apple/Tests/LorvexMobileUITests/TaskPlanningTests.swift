import XCTest

final class TaskPlanningTests: XCTestCase {
  @MainActor
  func testPlanAnInboxTaskAndKeepItsDeadline() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    let title = "Reserve a reading room " + UUID().uuidString.prefix(6)
    XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
    app.buttons["Capture"].firstMatch.tap()
    let field = app.descendants(matching: .any).matching(identifier: "mobileCapture.title").firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText(title)
    app.buttons["mobileCapture.confirm"].tap()
    let open = app.buttons["capture.receipt.button"]
    XCTAssertTrue(open.waitForExistence(timeout: 10))
    open.tap()

    let when = app.buttons["task.detail.row.doOn"]
    let due = app.buttons["task.detail.row.due"]
    XCTAssertTrue(when.waitForExistence(timeout: 10))
    app.buttons["task.detail.add"].tap()
    app.buttons["Due"].tap()
    app.buttons["task.field.day.1"].tap()
    app.buttons["task.field.done"].tap()
    XCTAssertTrue(due.waitForExistence(timeout: 10))
    let deadline = due.label
    XCTAssertTrue(deadline.localizedCaseInsensitiveContains("tomorrow"), deadline)

    // Reopen the saved task from its own list, as when triaging an Inbox.
    app.terminate()
    app.launchArguments += ["-lorvexOpenURL", "lorvex://list/inbox"]
    app.launch()
    let inbox = app.navigationBars["Inbox"]
    XCTAssertTrue(inbox.waitForExistence(timeout: 15))
    let row = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "(identifier BEGINSWITH 'mobile.task.row.' OR identifier BEGINSWITH 'mobile.tasks.selectable.') AND label BEGINSWITH %@",
        title)
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    XCTAssertTrue(when.waitForExistence(timeout: 10))
    XCTAssertTrue(when.label.localizedCaseInsensitiveContains("set date"), when.label)
    XCTAssertFalse(app.buttons["task.detail.delete"].exists)
    attach(app, "Inbox task before planning")
    when.tap()
    app.buttons["task.field.day.0"].tap()
    app.buttons["task.field.done"].tap()
    XCTAssertTrue(when.waitForExistence(timeout: 10))
    XCTAssertTrue(when.label.localizedCaseInsensitiveContains("today"), when.label)
    XCTAssertEqual(due.label, deadline)
    attach(app, "Planned task with its deadline")

    app.buttons["task.detail.more"].tap()
    XCTAssertTrue(app.buttons["task.detail.cancel"].exists)
    app.buttons["task.detail.delete"].tap()
    XCTAssertTrue(app.buttons["Delete Permanently"].waitForExistence(timeout: 5))
    let dismiss = app.otherElements["PopoverDismissRegion"]
    if dismiss.exists {
      // A native popover closes with a tap outside its bounds.
      dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0.68)).tap()
    } else {
      app.buttons["Cancel"].tap()
    }
    XCTAssertTrue(app.buttons["Delete Permanently"].waitForNonExistence(timeout: 5))
    if app.navigationBars["Task"].exists {
      app.navigationBars["Task"].buttons["BackButton"].tap()
    }
    XCTAssertTrue(inbox.waitForExistence(timeout: 10))
    XCTAssertTrue(row.isHittable)
    app.terminate()
    app.launch()
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    XCTAssertTrue(when.waitForExistence(timeout: 10))
    XCTAssertTrue(when.label.localizedCaseInsensitiveContains("today"), when.label)
    XCTAssertEqual(due.label, deadline)
  }

  @MainActor
  private func attach(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
