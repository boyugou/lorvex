import Testing

@testable import LorvexApple

/// A text field clips a placeholder wider than itself mid-word, so the prompts
/// that name a list cut a very long name with an ellipsis.
@Suite("List prompt names")
struct ListPromptNameTests {
  private let longName =
    "Cross-functional launch readiness with legal, security, support and regional marketing"

  @Test("a list name within the limit appears whole")
  func shortNameIsUnchanged() {
    let limit = AppStore.searchPromptListNameLimit
    #expect(AppStore.promptListName("Errands", limit: limit) == "Errands")
    let atLimit = String(repeating: "a", count: limit)
    #expect(AppStore.promptListName(atLimit, limit: limit) == atLimit)
  }

  @Test("a longer name is cut at the limit and ends with an ellipsis")
  func longNameIsCut() {
    let prompt = AppStore.promptListName(longName, limit: AppStore.searchPromptListNameLimit)
    #expect(prompt == "Cross-functional launch…")
    #expect(prompt.count <= AppStore.searchPromptListNameLimit + 1)
  }

  @Test("a single long word is cut inside the word")
  func longWordIsCutInside() {
    let word = "a-remarkably-long-name-that-has-no-spaces-at-all"
    #expect(
      AppStore.promptListName(word, limit: AppStore.searchPromptListNameLimit)
        == "a-remarkably-long-name-t…")
  }

  @Test("the cut never leaves a space before the ellipsis")
  func cutDropsTrailingSpace() {
    let limit = AppStore.searchPromptListNameLimit
    let name = String(repeating: "a", count: limit - 1) + " tail of the name"
    #expect(AppStore.promptListName(name, limit: limit).hasSuffix("a…"))
  }

  @Test("the quick-add placeholder keeps more of the name than the search prompt")
  func quickAddKeepsMore() {
    #expect(AppStore.quickAddPromptListNameLimit > AppStore.searchPromptListNameLimit)
    let cut = AppStore.promptListName(longName, limit: AppStore.quickAddPromptListNameLimit)
    #expect(cut == "Cross-functional launch readiness with…")
  }
}
