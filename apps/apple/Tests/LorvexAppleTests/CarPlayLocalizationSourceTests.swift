import Foundation
import Testing

/// The CarPlay scene delegate only compiles inside an iOS xcodebuild, so its
/// copy is checked at the source level: every piece of chrome reads the CarPlay
/// catalog through `CarPlayL10n.bundle`, and no English string is hardcoded.
@Test
func carPlaySceneChromeUsesLocalizationCatalog() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexCarPlay/LorvexCarPlaySceneDelegate.swift"),
    encoding: .utf8
  )

  for key in [
    "carplay.title",
    "carplay.action.retry",
    "carplay.action.complete",
    "carplay.action.defer_tomorrow",
    "carplay.action.open_iphone",
    "carplay.action.cancel",
    "carplay.section.error",
    "carplay.empty.title",
    "carplay.empty.detail",
  ] {
    #expect(source.contains(#"localized: "\#(key)""#), "missing catalog key \(key)")
  }
  #expect(!source.contains("CarPlayL10n.string("))
  #expect(source.components(separatedBy: "bundle: CarPlayL10n.bundle").count > 4)
  #expect(!source.contains(#"CPListItem(text: "Retry""#))
  #expect(!source.contains(#"CPListTemplate(title: "Lorvex""#))
  #expect(!source.contains(#"header: "Error""#))
  #expect(!source.contains(#"header: "Now Focusing""#))
}

/// Every catalog key the CarPlay module reads exists in its catalog in both
/// shipped languages, and no key in the catalog is dead.
@Test
func carPlayCatalogMatchesTheKeysTheModuleReads() throws {
  let root = packageRoot()
  let moduleDirectory = root.appending(path: "Sources/LorvexCarPlay")
  let files = try FileManager.default.contentsOfDirectory(
    at: moduleDirectory, includingPropertiesForKeys: nil
  ).filter { $0.pathExtension == "swift" }
  #expect(files.count >= 3)

  let keyPattern = try NSRegularExpression(pattern: #"localized: "(carplay\.[a-z_.]+)""#)
  var usedKeys = Set<String>()
  for file in files {
    let source = try String(contentsOf: file, encoding: .utf8)
    let range = NSRange(source.startIndex..., in: source)
    for match in keyPattern.matches(in: source, range: range) {
      if let keyRange = Range(match.range(at: 1), in: source) {
        usedKeys.insert(String(source[keyRange]))
      }
    }
  }

  let catalogURL = moduleDirectory.appending(path: "Resources/Localizable.xcstrings")
  let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
  let strings = try #require(catalog?["strings"] as? [String: Any])
  let catalogKeys = Set(strings.keys)

  #expect(usedKeys.subtracting(catalogKeys).isEmpty, "keys read but not in the catalog")
  #expect(catalogKeys.subtracting(usedKeys).isEmpty, "catalog keys nothing reads")
  for (key, value) in strings {
    let localizations = (value as? [String: Any])?["localizations"] as? [String: Any]
    for language in ["en", "zh-Hans"] {
      let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
      let text = unit?["value"] as? String
      #expect(!(text ?? "").isEmpty, "\(key) has no \(language) value")
    }
  }
}

private func packageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
