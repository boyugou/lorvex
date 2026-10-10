import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: path)
  return try String(contentsOf: url, encoding: .utf8)
}

@Test("The Erase confirmation sheet hangs on the Erase button, not on its Section")
func eraseConfirmationSheetIsAttachedToItsButton() throws {
  let text = try source("Sources/LorvexMobile/MobileStoreLocalDataResetSection.swift")

  // A sheet attached to the enclosing Section did not open on the Erase row's first tap, so the
  // person had to tap twice. Delete iCloud Data attaches its sheet to its button the same way.
  let button = try #require(text.range(of: ".accessibilityIdentifier(\"mobileSettings.resetDevice\")"))
  let sheet = try #require(text.range(of: ".sheet(isPresented: $showResetConfirmation)"))
  let header = try #require(text.range(of: "} header:"))
  #expect(button.upperBound <= sheet.lowerBound)
  #expect(sheet.upperBound <= header.lowerBound)
}
