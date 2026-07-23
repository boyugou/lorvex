import Foundation
import Testing

@Test
func carPlaySceneChromeUsesLocalizationCatalog() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexCarPlay/LorvexCarPlaySceneDelegate.swift"),
    encoding: .utf8
  )

  for key in [
    "carplay.action.retry",
    "carplay.section.error",
    "carplay.section.focus",
    "carplay.section.today",
  ] {
    #expect(source.contains(#"localized: "\#(key)""#))
  }
  #expect(!source.contains("CarPlayL10n.string("))
  #expect(source.components(separatedBy: "bundle: CarPlayL10n.bundle").count > 4)
  #expect(!source.contains(#"CPListItem(text: "Retry""#))
  #expect(!source.contains(#"header: "Error""#))
  #expect(!source.contains(#"header: "Now Focusing""#))
}

private func packageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
