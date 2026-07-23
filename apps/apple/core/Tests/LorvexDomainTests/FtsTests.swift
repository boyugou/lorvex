import XCTest

@testable import LorvexDomain

final class FtsTests: XCTestCase {
  func testSingleTokenGetsPrefixWildcard() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("gro"), "\"gro\"*")
  }

  func testLastTokenGetsPrefixWildcard() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("hello world"), "\"hello\" \"world\"*")
  }

  func testSpecialCharsSplitIntoSubtokens() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("foo*bar"), "\"foo\" \"bar\"*")
    XCTAssertEqual(Fts.sanitizeFtsQuery("\"quoted\""), "\"quoted\"*")
  }

  func testEmptyInputReturnsEmpty() {
    XCTAssertEqual(Fts.sanitizeFtsQuery(""), "")
    XCTAssertEqual(Fts.sanitizeFtsQuery("   "), "")
  }

  func testAllSpecialCharsYieldsEmpty() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("\"*()"), "")
  }

  func testControlCharactersAreStripped() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("hello\0world"), "\"hello\" \"world\"*")
    XCTAssertEqual(Fts.sanitizeFtsQuery("test\u{01}\u{02}\u{03}"), "\"test\"*")
    XCTAssertEqual(Fts.sanitizeFtsQuery("a\tb"), "\"a\" \"b\"*")
  }

  func testVeryLongInputTruncatedTo64Tokens() {
    let longInput = (0..<200).map { "word\($0)" }.joined(separator: " ")
    let result = Fts.sanitizeFtsQuery(longInput)
    let quoteCount = result.filter { $0 == "\"" }.count
    XCTAssertEqual(quoteCount / 2, 64)
  }

  func testCjkTokensPassThrough() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("买牛奶"), "\"买牛奶\"*")
  }

  func testEmojiOnlySubtokensDrop() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("🎯 goals"), "\"goals\"*")
  }

  func testPunctuationSplits() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("2024-Q1"), "\"2024\" \"Q1\"*")
    XCTAssertEqual(Fts.sanitizeFtsQuery("foo-bar"), "\"foo\" \"bar\"*")
    XCTAssertEqual(Fts.sanitizeFtsQuery("2026-04-17"), "\"2026\" \"04\" \"17\"*")
  }

  func testEmailLikeBecomesPhrase() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("alice@example.com"), "\"alice example com\"*")
  }

  func testDottedVersionBecomesPhrase() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("v1.2.3"), "\"v1 2 3\"*")
  }

  func testEmailAlongsideOtherWords() {
    XCTAssertEqual(
      Fts.sanitizeFtsQuery("email alice@example.com"),
      "\"email\" \"alice example com\"*")
  }

  func testHyphenatedNonDottedStillSplits() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("project-alpha"), "\"project\" \"alpha\"*")
  }

  func testQuotedPhrasePreserved() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("\"exact phrase\""), "\"exact phrase\"*")
  }

  func testQuotedPhraseWithFollowingBare() {
    XCTAssertEqual(
      Fts.sanitizeFtsQuery("\"exact phrase\" more"), "\"exact phrase\" \"more\"*")
  }

  func testQuotedPhraseLastCarriesWildcard() {
    XCTAssertEqual(
      Fts.sanitizeFtsQuery("bare \"exact phrase\""), "\"bare\" \"exact phrase\"*")
  }

  func testUnterminatedQuoteTolerated() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("foo \"bar baz"), "\"foo\" \"bar baz\"*")
  }

  func testEmptyQuotesDropped() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("foo \"\" bar"), "\"foo\" \"bar\"*")
  }

  func testFtsKeywordsRemainLiteralWhenQuoted() {
    XCTAssertEqual(Fts.sanitizeFtsQuery("AND"), "\"AND\"*")
    XCTAssertEqual(Fts.sanitizeFtsQuery("NOT hello"), "\"NOT\" \"hello\"*")
    XCTAssertEqual(Fts.sanitizeFtsQuery("a OR b"), "\"a\" \"OR\" \"b\"*")
  }

  // containsCjk
  func testContainsCjkChinese() {
    XCTAssertTrue(Fts.containsCjk("中文"))
    XCTAssertTrue(Fts.containsCjk("写一个中文任务"))
    XCTAssertTrue(Fts.containsCjk("buy 牛奶"))
  }

  func testContainsCjkJapanese() {
    XCTAssertTrue(Fts.containsCjk("こんにちは"))
    XCTAssertTrue(Fts.containsCjk("カタカナ"))
    XCTAssertTrue(Fts.containsCjk("漢字"))
  }

  func testContainsCjkKorean() {
    XCTAssertTrue(Fts.containsCjk("한국어"))
  }

  func testContainsCjkRejectsLatin() {
    XCTAssertFalse(Fts.containsCjk("hello world"))
    XCTAssertFalse(Fts.containsCjk("groceries"))
    XCTAssertFalse(Fts.containsCjk(""))
    XCTAssertFalse(Fts.containsCjk("🎯 goals"))
  }

  func testContainsCjkMixed() {
    XCTAssertTrue(Fts.containsCjk("buy 牛奶 tomorrow"))
    XCTAssertTrue(Fts.containsCjk("task: 完成报告"))
  }

  // length caps
  func testCapFtsQueryLengthTruncates() {
    let long = String(repeating: "a", count: 10_000)
    let capped = Fts.capFtsQueryLength(long)
    XCTAssertEqual(capped.count, 512)
  }

  func testCapFtsQueryLengthUnicodeBoundary() {
    let input = String(repeating: "a", count: 511) + "中"
    let capped = Fts.capFtsQueryLength(input)
    XCTAssertTrue(capped.hasSuffix("中"))
    XCTAssertEqual(capped.unicodeScalars.count, 512)
  }

  func testSanitizeTruncatesPerToken() {
    let giant = String(repeating: "a", count: 10_000)
    let sanitized = Fts.sanitizeFtsQuery(giant)
    var inner = sanitized
    if inner.hasPrefix("\"") { inner.removeFirst() }
    if inner.hasSuffix("*") { inner.removeLast() }
    if inner.hasSuffix("\"") { inner.removeLast() }
    XCTAssertEqual(inner.count, 64)
  }

  func testSanitize10kBlobDoesNotExplode() {
    let huge = String(repeating: "x", count: 20_000)
    let result = Fts.sanitizeFtsQuery(huge)
    XCTAssertTrue(result.hasPrefix("\""))
    XCTAssertTrue(result.hasSuffix("\"*"))
    XCTAssertLessThan(result.count, 80)
  }

  // shouldUseLikeFallback
  func testShouldUseLikeFallbackTrueCjk() {
    XCTAssertTrue(Fts.shouldUseLikeFallback("中文"))
    XCTAssertTrue(Fts.shouldUseLikeFallback("买 牛奶"))
  }

  func testShouldUseLikeFallbackTrueEmoji() {
    XCTAssertTrue(Fts.shouldUseLikeFallback("🚀"))
    XCTAssertTrue(Fts.shouldUseLikeFallback("🎯 🚀"))
  }

  func testShouldUseLikeFallbackTruePunct() {
    XCTAssertTrue(Fts.shouldUseLikeFallback("---"))
    XCTAssertTrue(Fts.shouldUseLikeFallback("..."))
    XCTAssertTrue(Fts.shouldUseLikeFallback("!?&*"))
  }

  func testShouldUseLikeFallbackFalseAlnum() {
    XCTAssertFalse(Fts.shouldUseLikeFallback("hello"))
    XCTAssertFalse(Fts.shouldUseLikeFallback("buy groceries"))
    XCTAssertFalse(Fts.shouldUseLikeFallback("task-123"))
  }

  func testShouldUseLikeFallbackFalseMixed() {
    XCTAssertFalse(Fts.shouldUseLikeFallback("🚀 ship"))
    XCTAssertFalse(Fts.shouldUseLikeFallback("goals 🎯"))
  }

  // shortTrailingToken
  func testShortTrailingTokenFlags2And3CharTrailers() {
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("oject"))
    XCTAssertEqual(Fts.shortTrailingTokenForLikeRetry("ab"), "ab")
    XCTAssertEqual(Fts.shortTrailingTokenForLikeRetry("foo ab"), "ab")
    XCTAssertEqual(Fts.shortTrailingTokenForLikeRetry("foo abc"), "abc")
  }

  func testShortTrailingTokenRejectsSingleChar() {
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("a"))
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("foo a"))
  }

  func testShortTrailingTokenRejectsLong() {
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("foobar"))
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("foo barbaz"))
  }

  func testShortTrailingTokenRejectsEmpty() {
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry(""))
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("   "))
  }

  func testShortTrailingTokenRejectsQuoted() {
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("\"abc\""))
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("foo \"bar\""))
  }

  func testShortTrailingTokenRejectsEmailLike() {
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("alice@example.com"))
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("v1.2.3"))
    XCTAssertNil(Fts.shortTrailingTokenForLikeRetry("foo.ab"))
  }

  func testShortTrailingTokenAcceptsAfterHyphen() {
    XCTAssertEqual(Fts.shortTrailingTokenForLikeRetry("foo-ab"), "ab")
  }
}
