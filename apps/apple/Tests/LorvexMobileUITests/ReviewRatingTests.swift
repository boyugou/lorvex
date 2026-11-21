import XCTest

final class ReviewRatingTests: XCTestCase {
  @MainActor
  func testSaveChangeAndClearJournalRatings() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    let base = ["-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launchArguments = base
    launchReview(app)
    let mood = app.buttons["review.daily.mood"]
    let energy = app.buttons["review.daily.energy"]
    XCTAssertTrue(mood.waitForExistence(timeout: 12))
    XCTAssertGreaterThanOrEqual(mood.frame.height, 44)
    XCTAssertGreaterThanOrEqual(energy.frame.height, 44)
    XCTAssertEqual(mood.frame.minY, energy.frame.minY, accuracy: 1)
    XCTAssertEqual(mood.frame.height, energy.frame.height, accuracy: 1)

    // The note should reach storage while the keyboard is still up.
    let note = app.textFields["review.daily.summary"]
    note.tap()
    note.typeText("Leave room for a walk. ")
    let editedNote = try XCTUnwrap(note.value as? String)
    XCTAssertTrue(editedNote.contains("Leave room for a walk."))
    let saved = app.descendants(matching: .any).matching(identifier: "review.daily.saved").firstMatch
    XCTAssertTrue(saved.waitForExistence(timeout: 8))
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    launchReview(app)
    XCTAssertTrue(note.waitForExistence(timeout: 8))
    XCTAssertEqual(note.value as? String, editedNote.trimmingCharacters(in: .whitespacesAndNewlines))

    choose("Good", in: mood, app: app)
    choose("Low", in: energy, app: app)
    capture(app, "Feeling and energy below the journal")
    launchReview(app)
    expectRating("Good", in: mood)
    expectRating("Low", in: energy)

    choose("Clear", in: energy, app: app)
    choose("Great", in: mood, app: app)
    expectRating("Add", in: energy)
    capture(app, "One rating cleared")

    app.launchArguments = base + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    launchReview(app)
    expectRating("Great", in: mood)
    expectRating("Add", in: energy)
    XCTAssertGreaterThanOrEqual(energy.frame.minY, mood.frame.maxY)
    for _ in 0..<4 where !energy.isHittable { app.swipeUp() }
    capture(app, "Two controls at accessibility text size")
    choose("Full", in: energy, app: app)

    app.launchArguments = base
    launchReview(app)
    expectRating("Full", in: energy)
    #if compiler(>=6.4) && targetEnvironment(simulator)
      if #available(iOS 27, *) { try readRatingsWithVoiceOver(mood) }
    #endif
    choose("Clear", in: energy, app: app)
    choose("Clear", in: mood, app: app)
    launchReview(app)
    expectRating("Add", in: mood)
    expectRating("Add", in: energy)
    capture(app, "Unrated journal")
  }

  #if compiler(>=6.4) && targetEnvironment(simulator)
    @available(iOS 27, *)
    @MainActor
    private func readRatingsWithVoiceOver(_ mood: XCUIElement) throws {
      let service = XCUIDevice.shared.voiceOverService
      let wasEnabled = service.isEnabled
      defer { if !wasEnabled { try? service.disable() } }
      try service.enable()
      mood.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      let reading = try service.currentSpeech().utterance
      XCTAssertTrue(reading.contains("How did it feel?") && reading.contains("Great") && reading.contains("5"), reading)
      let next = try service.moveForward().utterance
      XCTAssertTrue(next.contains("Energy") && next.contains("Full") && next.contains("5"), next)
    }
  #endif

  @MainActor
  private func launchReview(_ app: XCUIApplication) {
    app.launch()
    let tab = app.buttons["Review"].firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 12), app.debugDescription)
    tab.tap()
  }

  @MainActor
  private func choose(_ word: String, in menu: XCUIElement, app: XCUIApplication) {
    menu.tap()
    app.buttons[word].firstMatch.tap()
  }

  @MainActor
  private func expectRating(_ word: String, in menu: XCUIElement) {
    let match = NSPredicate(format: "exists == true AND value CONTAINS %@", word)
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: match, object: menu)], timeout: 8),
      .completed, menu.debugDescription)
  }

  @MainActor
  private func capture(_ app: XCUIApplication, _ name: String) {
    let snapshot = XCTAttachment(screenshot: app.screenshot())
    snapshot.name = name
    snapshot.lifetime = .keepAlways
    add(snapshot)
  }
}
