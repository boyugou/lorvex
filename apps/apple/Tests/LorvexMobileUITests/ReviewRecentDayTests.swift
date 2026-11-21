import XCTest

final class ReviewRecentDayTests: XCTestCase {
  @MainActor func testWriteYesterdayAndReturnToToday() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    XCUIDevice.shared.orientation = .portrait
    openReview(app)
    let note = app.textFields["review.daily.summary"]
    let header = app.buttons["review.day.date"]
    let marker = String(UUID().uuidString.prefix(5))
    let todaysNote = "Bring the sketchbook \(marker)."
    let yesterdaysNote = "The second sketch worked \(marker)."
    XCTAssertTrue(note.waitForExistence(timeout: 10))
    note.tap()
    note.typeText(todaysNote)
    header.tap()
    let yesterday = app.buttons["Yesterday"]
    XCTAssertTrue(yesterday.waitForExistence(timeout: 5), app.debugDescription)
    yesterday.tap()
    let back = app.buttons["review.day.returnToday"]
    XCTAssertTrue(back.waitForExistence(timeout: 8))
    note.tap()
    note.typeText(yesterdaysNote)
    app.buttons["review.daily.energy"].tap()
    app.buttons["Steady"].firstMatch.tap()
    capture(app, "Yesterday in the journal")
    back.tap()
    expectText(note, contains: todaysNote)
    XCTAssertFalse((note.value as? String)?.contains(yesterdaysNote) == true)

    app.buttons["Week"].firstMatch.tap()
    // SwiftUI renders the journal content as a text element under its date.
    let pastWords = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", yesterdaysNote)).firstMatch
    XCTAssertTrue(pastWords.waitForExistence(timeout: 10))
    capture(app, "Both entries in the weekly journal")
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let prior = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
    app.buttons["review.week.day.\(formatter.string(from: prior))"].tap()
    let edit = app.buttons["review.day.edit"]
    XCTAssertTrue(edit.waitForExistence(timeout: 8))
    edit.tap()
    expectText(note, contains: yesterdaysNote)
    XCTAssertTrue(app.buttons["review.daily.energy"].value.debugDescription.contains("Steady"))
    openReview(app)
    expectText(note, contains: todaysNote)
    header.tap()
    yesterday.tap()
    expectText(note, contains: yesterdaysNote)
  }

  @MainActor private func openReview(_ app: XCUIApplication) {
    app.launch()
    let tab = app.buttons["Review"].firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 12))
    tab.tap()
  }

  @MainActor private func expectText(_ field: XCUIElement, contains text: String) {
    let match = NSPredicate(format: "exists == true AND value CONTAINS %@", text)
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: match, object: field)], timeout: 8), .completed)
  }

  @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
