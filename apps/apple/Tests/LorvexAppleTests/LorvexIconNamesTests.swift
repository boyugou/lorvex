import LorvexCore
import Testing

@testable import LorvexApple

/// The names and search keywords of the icons the list and habit picker offers.
@Suite("Icon picker names")
@MainActor
struct LorvexIconNamesTests {
  @Test("every curated icon has a name and keywords")
  func everyCuratedIconIsNamed() {
    for symbol in LorvexAppearancePicker.iconChoices {
      #expect(LorvexIconNames.name(for: symbol)?.isEmpty == false, "no name for \(symbol)")
      #expect(LorvexIconNames.keywords(for: symbol)?.isEmpty == false, "no keywords for \(symbol)")
    }
  }

  @Test("names differ between icons, so VoiceOver can tell them apart")
  func namesAreUnique() {
    let names = LorvexAppearancePicker.iconChoices.compactMap(LorvexIconNames.name(for:))
    #expect(Set(names).count == names.count)
  }

  @Test("a filled variant has the name of its outline symbol")
  func filledVariantsResolve() {
    #expect(LorvexIconNames.name(for: "star.fill") == LorvexIconNames.name(for: "star"))
    #expect(
      LorvexIconNames.name(for: "dollarsign.circle.fill")
        == LorvexIconNames.name(for: "dollarsign.circle"))
    #expect(LorvexIconNames.name(for: "repeat") != nil)
    #expect(LorvexIconNames.name(for: "figure.mind.and.body") != nil)
    #expect(LorvexIconNames.name(for: "not.a.symbol") == nil)
  }

  @Test("search matches the name, a keyword, and the SF Symbol name")
  func searchReadsEveryField() throws {
    let name = try #require(LorvexIconNames.name(for: "dumbbell"))
    let keyword = try #require(LorvexIconNames.keywords(for: "dumbbell")?.split(separator: " ").first)
    #expect(LorvexIconNames.matches("dumbbell", query: name))
    #expect(LorvexIconNames.matches("dumbbell", query: String(keyword)))
    #expect(LorvexIconNames.matches("figure.run", query: "figure.run"))
    #expect(LorvexIconNames.matches("figure.run", query: "FIGURE"))
  }

  @Test("every word typed must match, and an unrelated word matches nothing")
  func searchNeedsEveryWord() {
    #expect(!LorvexIconNames.matches("dumbbell", query: "dumbbell zzzz"))
    #expect(!LorvexIconNames.matches("dumbbell", query: "zzzz"))
    #expect(LorvexIconNames.matches("dumbbell", query: "  "))
  }
}
