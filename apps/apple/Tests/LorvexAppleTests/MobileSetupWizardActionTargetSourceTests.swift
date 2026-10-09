import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Test("The setup wizard's quieter choice is a full-width 44-point tap target")
func mobileSetupWizardSecondaryButtonIsATouchTarget() throws {
  let wizard = try source("Sources/LorvexMobile/MobileSetupWizard.swift")
  let start = try #require(
    wizard.range(of: "private func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {"))
  let end = try #require(
    wizard.range(of: "private var continueButton: some View {", range: start.upperBound..<wizard.endIndex))
  let button = wizard[start.upperBound..<end.lowerBound]

  // A borderless button taps only inside its label's shape. Without the
  // minimum height and the rectangular content shape, "Not Now" answered taps
  // only on the 22-point line of its words.
  #expect(button.contains(".frame(maxWidth: .infinity, minHeight: 44)"))
  #expect(button.contains(".contentShape(Rectangle())"))
  #expect(button.contains(".buttonStyle(.borderless)"))
}
