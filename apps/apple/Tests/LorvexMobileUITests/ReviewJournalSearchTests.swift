import XCTest

final class ReviewJournalSearchTests: XCTestCase {
  @MainActor func testFindAndEditYesterdaysEntryFromToday() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = ["-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    let review = app.buttons["Review"].firstMatch
    XCTAssertTrue(review.waitForExistence(timeout: 12))
    review.tap()

    let header = app.buttons["review.day.date"]
    XCTAssertTrue(header.waitForExistence(timeout: 8))
    header.tap()
    let yesterday = app.buttons["Yesterday"]
    XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
    yesterday.tap()
    let note = app.textFields["review.daily.summary"]
    XCTAssertTrue(note.waitForExistence(timeout: 5))
    let phrase = "Tile " + String(UUID().uuidString.prefix(6))
    note.tap()
    note.typeText(phrase)
    app.buttons["review.day.returnToday"].tap()

    let openSearch = app.buttons["review.search.open"]
    XCTAssertTrue(openSearch.waitForExistence(timeout: 8), app.debugDescription)
    openSearch.tap()
    let field = app.descendants(matching: .any)["review.search.field"].firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
    field.tap()
    let missingPhrase = String(UUID().uuidString.prefix(8))
    field.typeText(missingPhrase)
    let emptyMessage = app.staticTexts.matching(NSPredicate(
      format: "label CONTAINS %@", missingPhrase)).firstMatch
    XCTAssertTrue(emptyMessage.waitForExistence(timeout: 8))
    app.buttons["review.search.clear"].tap()
    field.typeText(phrase)
    let match = app.buttons.matching(NSPredicate(
      format: "identifier BEGINSWITH 'review.search.day.' AND label CONTAINS %@", phrase)).firstMatch
    XCTAssertTrue(match.waitForExistence(timeout: 8))
    match.tap()
    let edit = app.buttons["review.search.edit"]
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    edit.tap()

    XCTAssertTrue(app.buttons["review.day.returnToday"].waitForExistence(timeout: 8))
    XCTAssertTrue((note.value as? String)?.contains(phrase) == true)
    note.tap()
    let amendment = "Kiln " + String(UUID().uuidString.prefix(6))
    note.typeText(amendment)
    let returnToday = app.buttons["review.day.returnToday"]
    returnToday.tap()
    XCTAssertTrue(returnToday.waitForNonExistence(timeout: 8))
    header.tap()
    XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
    yesterday.tap()
    let saved = NSPredicate(format: "value CONTAINS %@", amendment)
    let expectation = XCTNSPredicateExpectation(predicate: saved, object: note)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
  }
}
