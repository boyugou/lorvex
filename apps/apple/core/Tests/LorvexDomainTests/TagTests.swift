import XCTest

@testable import LorvexDomain

final class TagTests: XCTestCase {
  func testAsciiBasic() {
    XCTAssertEqual(normalizeLookupKey("Hello World"), "hello world")
  }

  func testCjkPreserved() {
    XCTAssertEqual(normalizeLookupKey("工作"), "工作")
  }

  func testEmojiPreserved() {
    XCTAssertEqual(normalizeLookupKey("🏠 Home"), "🏠 home")
  }

  func testWhitespaceCollapse() {
    XCTAssertEqual(normalizeLookupKey("  hello   world  "), "hello world")
  }

  func testMixedCase() {
    XCTAssertEqual(normalizeLookupKey("WorkOut"), "workout")
  }

  func testEmptyString() {
    XCTAssertEqual(normalizeLookupKey(""), "")
  }

  func testOnlyWhitespace() {
    XCTAssertEqual(normalizeLookupKey("   "), "")
  }

  func testTabsAndNewlinesCollapsed() {
    XCTAssertEqual(normalizeLookupKey("hello\t\nworld"), "hello world")
  }

  func testNfkcFullwidthCharacters() {
    let fullwidth = "\u{FF21}\u{FF22}\u{FF23}"
    XCTAssertEqual(normalizeLookupKey(fullwidth), "abc")
  }

  func testNfkcHalfwidthKatakana() {
    let halfwidth = "\u{FF76}"
    let fullwidth = "\u{30AB}"
    XCTAssertEqual(
      normalizeLookupKey(halfwidth), normalizeLookupKey(fullwidth),
      "halfwidth and fullwidth katakana should normalize to the same key")
  }

  func testUnicodeNormalizationSameCharacter() {
    let composed = "\u{00E9}"
    let decomposed = "\u{0065}\u{0301}"
    XCTAssertEqual(
      normalizeLookupKey(composed), normalizeLookupKey(decomposed),
      "composed and decomposed forms should produce the same lookup key")
  }

  func testMixedScriptWithEmoji() {
    XCTAssertEqual(normalizeLookupKey("  🎯 Daily 工作  "), "🎯 daily 工作")
  }

  func testGermanSharpSFoldsToSs() {
    XCTAssertEqual(normalizeLookupKey("Straße"), "strasse")
    XCTAssertEqual(normalizeLookupKey("STRASSE"), "strasse")
    XCTAssertEqual(normalizeLookupKey("Straße"), normalizeLookupKey("STRASSE"))
  }

  func testTurkishDottedCapitalIFoldsToCombiningDot() {
    let folded = normalizeLookupKey("İstanbul")
    XCTAssertEqual(
      folded, "i\u{307}stanbul",
      "İ should casefold to 'i' + COMBINING DOT ABOVE")
    XCTAssertEqual(
      normalizeLookupKey("İstanbul"), normalizeLookupKey("İstanbul"),
      "idempotent on already-folded form")
  }

  func testGreekFinalSigmaUnifiesWithMedial() {
    XCTAssertEqual(
      normalizeLookupKey("ΚΟΣΜΟΣ"),
      "\u{03BA}\u{03BF}\u{03C3}\u{03BC}\u{03BF}\u{03C3}",
      "all-caps GREEK CAPITAL SIGMA must fold to medial σ")
    XCTAssertEqual(
      normalizeLookupKey("\u{03C3}\u{03BF}\u{03C2}"),
      "\u{03C3}\u{03BF}\u{03C3}",
      "final sigma σ-σ-ς should fold to medial σ-σ-σ")
  }

  func testUppercaseCjkLatinMix() {
    XCTAssertEqual(normalizeLookupKey("ABC工作DEF"), "abc工作def")
  }

  func testSingleCharacter() {
    XCTAssertEqual(normalizeLookupKey("A"), "a")
  }

  func testLeadingTrailingEmoji() {
    XCTAssertEqual(normalizeLookupKey("🔥🔥🔥"), "🔥🔥🔥")
  }

  func testMultipleWhitespaceTypes() {
    let input = "hello\u{00A0}\u{2003}world"
    XCTAssertEqual(normalizeLookupKey(input), "hello world")
  }

  func testNfkcSuperscriptDigits() {
    XCTAssertEqual(normalizeLookupKey("x\u{00B2}"), "x2")
  }

  func testStripsZeroWidthBeforeNfkc() {
    XCTAssertEqual(
      normalizeLookupKey("Work\u{200B}"), normalizeLookupKey("Work"),
      "zero-width space must be stripped so the lookup key matches the visible string")
    XCTAssertEqual(
      normalizeLookupKey("Wo\u{200B}rk"), normalizeLookupKey("Work"),
      "interior zero-width space must be stripped")
    XCTAssertEqual(
      normalizeLookupKey("Work\u{202E}"), normalizeLookupKey("Work"),
      "bidi override must be stripped")
  }

  func testIdempotent() {
    let input = "Hello World"
    let key1 = normalizeLookupKey(input)
    let key2 = normalizeLookupKey(key1)
    XCTAssertEqual(key1, key2, "normalizing an already-normalized key should be idempotent")
  }
}
