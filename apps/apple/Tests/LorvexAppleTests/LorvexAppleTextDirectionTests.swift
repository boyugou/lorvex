import LorvexCore
import Testing

@testable import LorvexApple

/// The Mac app lays itself out in the direction of the language it shows,
/// whatever the system's own direction (``LorvexAppleTextDirection``). AppKit
/// reads the default once per process, so these tests check the launch
/// arguments the app hands it.
struct LorvexAppleTextDirectionTests {
  @Test("A right-to-left language turns the text direction on and keeps every other argument")
  func rightToLeftLanguageTurnsTheDirectionOn() throws {
    let arguments: [String: Any] = ["AppleLanguages": ["ar"], "lorvexPreviewNow": "11:20"]
    let aligned = try #require(LorvexAppleTextDirection.alignedArguments(arguments, showing: .ar))
    #expect(aligned["AppleTextDirection"] as? Bool == true)
    #expect(aligned["AppleLanguages"] as? [String] == ["ar"])
    #expect(aligned["lorvexPreviewNow"] as? String == "11:20")
    #expect(aligned.count == 3)
  }

  @Test("A left-to-right language leaves the arguments alone")
  func leftToRightLanguagesNeedNothing() {
    for language in AppLanguage.selectable where language != .ar {
      #expect(LorvexAppleTextDirection.alignedArguments([:], showing: language) == nil)
    }
  }

  @Test("An explicit text-direction argument decides by itself")
  func explicitArgumentWins() {
    let arguments: [String: Any] = ["AppleTextDirection": false]
    #expect(LorvexAppleTextDirection.alignedArguments(arguments, showing: .ar) == nil)
  }
}
