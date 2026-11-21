import XCTest

final class TodayTaskPickerTests: XCTestCase {
  @MainActor
  func testPlanFromEmptyTodayCancelUndoAndReopen() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    let title = "Read the field notes " + UUID().uuidString.prefix(5)
    app.buttons["Capture"].firstMatch.tap()
    let field = app.descendants(matching: .any).matching(identifier: "mobileCapture.title").firstMatch
    field.tap()
    field.typeText(title)
    app.buttons["mobileCapture.confirm"].tap()
    let choose = app.buttons["today.chooseTask"]
    XCTAssertTrue(choose.waitForExistence(timeout: 10))
    app.buttons["Tasks"].firstMatch.tap()
    let inbox = app.descendants(matching: .any).matching(identifier: "mobileTasks.list.inbox").firstMatch
    if inbox.waitForExistence(timeout: 3) { inbox.tap() }
    let fromInbox = app.descendants(matching: .any).matching(NSPredicate(
      format: "(identifier BEGINSWITH 'mobile.task.row.' OR identifier BEGINSWITH 'mobile.tasks.selectable.') AND label BEGINSWITH %@", title
    )).firstMatch
    XCTAssertTrue(fromInbox.waitForExistence(timeout: 8), app.debugDescription)
    fromInbox.tap()
    app.buttons["task.detail.add"].tap()
    app.buttons["Due"].tap()
    app.buttons["task.field.day.1"].tap()
    app.buttons["task.field.done"].tap()
    XCTAssertTrue(app.buttons["task.detail.row.due"].label.localizedCaseInsensitiveContains("tomorrow"))
    app.terminate()
    app.launch()

    XCTAssertTrue(choose.waitForExistence(timeout: 10), app.debugDescription)
    attach(app, "A free day with an unplanned task")
    choose.tap()
    let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'today.chooseTask.row.' AND label CONTAINS %@", title)).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertTrue(row.label.localizedCaseInsensitiveContains("tomorrow"), row.label)
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(choose.waitForExistence(timeout: 8))
    choose.tap()
    XCTAssertTrue(row.waitForExistence(timeout: 8))
    attach(app, "Choose a task for today")
    row.tap()
    let undo = app.buttons["mobile.undo.button"]
    XCTAssertTrue(undo.waitForExistence(timeout: 8), app.debugDescription)
    undo.tap()
    XCTAssertTrue(choose.waitForExistence(timeout: 8))
    choose.tap()
    XCTAssertTrue(row.waitForExistence(timeout: 8))
    row.tap()
    XCTAssertTrue(undo.waitForExistence(timeout: 8))

    app.terminate()
    app.launch()
    let planned = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    XCTAssertTrue(planned.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertFalse(choose.exists)
    attach(app, "The same task on Today after reopening")
    planned.tap()
    let deadline = app.buttons["task.detail.row.due"]
    XCTAssertTrue(deadline.waitForExistence(timeout: 8))
    XCTAssertTrue(deadline.label.localizedCaseInsensitiveContains("tomorrow"), deadline.label)
  }

  @MainActor
  private func attach(_ app: XCUIApplication, _ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
