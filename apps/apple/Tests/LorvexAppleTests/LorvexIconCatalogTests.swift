import LorvexCore
import Testing

@testable import LorvexMobile

/// The icon set every list and habit picker offers, with the names and search
/// keywords of its icons.
@Suite("Icon catalog")
@MainActor
struct LorvexIconCatalogTests {
  @Test("every curated icon has a name and keywords, and none is listed twice")
  func everyCuratedIconIsNamed() {
    #expect(Set(LorvexIconCatalog.choices).count == LorvexIconCatalog.choices.count)
    for symbol in LorvexIconCatalog.choices {
      #expect(LorvexIconCatalog.name(for: symbol)?.isEmpty == false, "no name for \(symbol)")
      #expect(LorvexIconCatalog.keywords(for: symbol)?.isEmpty == false, "no keywords for \(symbol)")
    }
  }

  @Test("names differ between icons, so VoiceOver can tell them apart")
  func namesAreUnique() {
    let names = LorvexIconCatalog.choices.compactMap(LorvexIconCatalog.name(for:))
    #expect(Set(names).count == names.count)
  }

  @Test("a search lists the matching icons in the curated order, and an empty one lists them all")
  func searchListsMatchesInTheCuratedOrder() {
    #expect(LorvexIconCatalog.choices(matching: "  ") == LorvexIconCatalog.choices)
    let found = LorvexIconCatalog.choices(matching: "figure.run")
    #expect(found.first == "figure.run")
    #expect(found == LorvexIconCatalog.choices.filter(found.contains))
    #expect(LorvexIconCatalog.choices(matching: "zzzzqx").isEmpty)
  }

  @Test("the leading icons come first, once each, and the search still applies to them")
  func leadingIconsComeFirst() {
    let ordered = LorvexIconCatalog.choices(matching: "", leading: MobileIconChoices.habit)
    #expect(Array(ordered.prefix(MobileIconChoices.habit.count)) == MobileIconChoices.habit)
    #expect(Set(ordered) == Set(LorvexIconCatalog.choices))
    #expect(ordered.count == LorvexIconCatalog.choices.count)
    let found = LorvexIconCatalog.choices(matching: "dumbbell", leading: MobileIconChoices.habit)
    #expect(found == ["dumbbell"])
  }

  @Test("the icons a sheet puts first are curated icons, so every one has a name")
  func sheetLeadingIconsAreCurated() {
    for symbol in MobileIconChoices.habit + MobileIconChoices.list {
      #expect(LorvexIconCatalog.choices.contains(symbol), "\(symbol) is not curated")
    }
    #expect(Set(MobileIconChoices.habit).count == MobileIconChoices.habit.count)
    #expect(Set(MobileIconChoices.list).count == MobileIconChoices.list.count)
  }

  @Test("the iPhone grid draws and stores a filled variant where one exists")
  func iPhoneGridUsesFilledVariants() {
    #expect(MobileIconChoices.symbol(for: "star") == "star.fill")
    #expect(MobileIconChoices.symbol(for: "figure.run") == "figure.run")
    #expect(MobileIconChoices.symbol(for: "custom.not.curated") == "custom.not.curated")
    for symbol in LorvexIconCatalog.choices {
      #expect(
        LorvexIconCatalog.outlineName(of: MobileIconChoices.symbol(for: symbol)) == symbol,
        "\(symbol) draws as another icon")
    }
  }

  @Test("a filled variant has the name of its outline symbol")
  func filledVariantsResolve() {
    #expect(LorvexIconCatalog.name(for: "star.fill") == LorvexIconCatalog.name(for: "star"))
    #expect(
      LorvexIconCatalog.name(for: "dollarsign.circle.fill")
        == LorvexIconCatalog.name(for: "dollarsign.circle"))
    #expect(LorvexIconCatalog.name(for: "not.a.symbol") == nil)
  }

  @Test("search matches the name, a keyword, and the SF Symbol name")
  func searchReadsEveryField() throws {
    let name = try #require(LorvexIconCatalog.name(for: "dumbbell"))
    let keyword = try #require(LorvexIconCatalog.keywords(for: "dumbbell")?.split(separator: " ").first)
    #expect(LorvexIconCatalog.matches("dumbbell", query: name))
    #expect(LorvexIconCatalog.matches("dumbbell", query: String(keyword)))
    #expect(LorvexIconCatalog.matches("figure.run", query: "figure.run"))
    #expect(LorvexIconCatalog.matches("figure.run", query: "FIGURE"))
  }

  @Test("every word typed must match, and an unrelated word matches nothing")
  func searchNeedsEveryWord() {
    #expect(!LorvexIconCatalog.matches("dumbbell", query: "dumbbell zzzz"))
    #expect(!LorvexIconCatalog.matches("dumbbell", query: "zzzz"))
    #expect(LorvexIconCatalog.matches("dumbbell", query: "  "))
  }
}
