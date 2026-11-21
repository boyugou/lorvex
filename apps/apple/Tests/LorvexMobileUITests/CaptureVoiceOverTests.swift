import XCTest

final class CaptureVoiceOverTests: XCTestCase {
  @MainActor
  func testOpenUndatedTaskAfterCapture() throws {
    continueAfterFailure = false
    #if compiler(>=6.4) && targetEnvironment(simulator)
      guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver automation requires iOS 27.") }
      let voiceOver = XCUIDevice.shared.voiceOverService
      let wasEnabled = voiceOver.isEnabled
      addTeardownBlock { @MainActor in
        let service = XCUIDevice.shared.voiceOverService
        if wasEnabled { try service.enable() } else if service.isEnabled { try service.disable() }
      }
      if wasEnabled { try voiceOver.disable() }

      let app = XCUIApplication()
      app.launchArguments = ["-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
      app.launch()
      let capture = app.buttons["Capture"].firstMatch
      XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
      XCTAssertTrue(capture.waitForExistence(timeout: 10))
      capture.tap()

      let field = app.descendants(matching: .any).matching(identifier: "mobileCapture.title").firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 10))
      let title = "Find the paperback"
      field.tap()
      field.typeText(title)
      try voiceOver.enable()
      XCTAssertTrue(voiceOver.isEnabled)
      let save = app.buttons["mobileCapture.confirm"]
      save.tap()
      if !save.waitForNonExistence(timeout: 2) { save.doubleTap() }

      let open = app.buttons["capture.receipt.button"]
      XCTAssertTrue(open.waitForExistence(timeout: 10))
      // Without VoiceOver the receipt expires after eight seconds.
      XCTAssertFalse(open.waitForNonExistence(timeout: 9))
      let receipt = try voiceOver.currentSpeech().utterance
      XCTAssertTrue(receipt.contains(title) && receipt.contains("Inbox"), receipt)
      let next = try voiceOver.moveForward().utterance
      XCTAssertTrue(next.hasPrefix("Open"), next)
      open.doubleTap()
      XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
    #else
      throw XCTSkip("Run the VoiceOver UI test on an iOS 27 simulator with Xcode 27.")
    #endif
  }
}
