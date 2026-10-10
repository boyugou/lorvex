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

@Test("The Mac Data Import picker and contents sheet are presented from the Settings root")
func macImportPresentationsAreAppliedAtTheSettingsRoot() throws {
  let section = try source("Sources/LorvexApple/Views/SettingsDataImportSection.swift")
  let root = try source("Sources/LorvexApple/Views/SettingsView.swift")

  // A presentation attached to the grouped Form's Section does not reliably present, so the
  // import section carries none and the root applies them like every other Settings sheet.
  let sectionStart = try #require(section.range(of: "var dataImportSection: some View {"))
  let presentations = try #require(
    section.range(of: "func dataImportPresentations(_ content: some View) -> some View {"))
  #expect(sectionStart.upperBound <= presentations.lowerBound)
  let sectionBody = section[sectionStart.upperBound..<presentations.lowerBound]
  #expect(!sectionBody.contains(".fileImporter("))
  #expect(!sectionBody.contains(".sheet("))
  #expect(section[presentations.upperBound...].contains(".fileImporter("))
  #expect(section[presentations.upperBound...].contains(".sheet(isPresented: importPreviewBinding)"))
  #expect(root.contains("dataImportPresentations(settingsRoot)"))
}
