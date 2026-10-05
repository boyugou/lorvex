import XCTest

@testable import LorvexDomain

final class SearchFoldTests: XCTestCase {

  func testAsciiIsLowercasedAndOtherwiseUnchanged() {
    XCTAssertEqual(SearchFold.fold("Buy MILK, 42 eggs!"), "buy milk, 42 eggs!")
    XCTAssertEqual(SearchFold.fold(""), "")
    XCTAssertEqual(SearchFold.fold("   "), "   ")
  }

  func testLatinAccentsAreRemoved() {
    XCTAssertEqual(SearchFold.fold("Café Crème Brûlée"), "cafe creme brulee")
    XCTAssertEqual(SearchFold.fold("Zażółć gęślą jaźń"), "zazolc gesla jazn")
    XCTAssertEqual(SearchFold.fold("Việt Nam"), "viet nam")
    XCTAssertEqual(SearchFold.fold("Ñandú"), "nandu")
  }

  func testLettersWithoutADecompositionAreReplaced() {
    XCTAssertEqual(SearchFold.fold("Łódź"), "lodz")
    XCTAssertEqual(SearchFold.fold("Đi chợ"), "di cho")
    XCTAssertEqual(SearchFold.fold("ĐỪNG QUÊN"), "dung quen")
    XCTAssertEqual(SearchFold.fold("Straße"), "strasse")
    XCTAssertEqual(SearchFold.fold("GROẞ"), "gross")
    XCTAssertEqual(SearchFold.fold("Ærlig Øl"), "aerlig ol")
    XCTAssertEqual(SearchFold.fold("Œuvre"), "oeuvre")
    XCTAssertEqual(SearchFold.fold("Þórr Ðe"), "thorr de")
  }

  func testTurkishDottedAndDotlessIAreOneLetter() {
    XCTAssertEqual(SearchFold.fold("Işık ve ısı İstanbul"), "isik ve isi istanbul")
    XCTAssertEqual(SearchFold.fold("ISIK"), SearchFold.fold("ışık"))
    XCTAssertEqual(SearchFold.fold("İSTANBUL"), SearchFold.fold("istanbul"))
  }

  func testCyrillicYoAndShortIAreOneLetterWithTheirBase() {
    XCTAssertEqual(SearchFold.fold("Всё ещё, Ёлка и йод"), "все еще, елка и иод")
    XCTAssertEqual(SearchFold.fold("ЁЖ"), "еж")
    XCTAssertEqual(SearchFold.fold("Їжак"), "іжак")
  }

  func testGreekAccentsCaseAndFinalSigmaAreDropped() {
    XCTAssertEqual(SearchFold.fold("Καλημέρα κόσμε"), "καλημερα κοσμε")
    XCTAssertEqual(SearchFold.fold("ΚΑΛΗΜΕΡΑ"), "καλημερα")
    XCTAssertEqual(SearchFold.fold("λόγος"), "λογοσ")
    XCTAssertEqual(SearchFold.fold("ΛΟΓΟΣ"), "λογοσ")
    XCTAssertEqual(SearchFold.fold("ΐ ΰ"), "ι υ")
  }

  func testArabicScriptVariantsAndMarksAreUnified() {
    XCTAssertEqual(SearchFold.fold("أسماء إلى آمن"), "اسماء الي امن")
    XCTAssertEqual(SearchFold.fold("مدرسة"), "مدرسه")
    XCTAssertEqual(SearchFold.fold("مُحَمَّد"), "محمد")
    XCTAssertEqual(SearchFold.fold("كـــتاب"), "كتاب")
    // Arabic and Persian keyboards produce different codepoints for the same word.
    XCTAssertEqual(SearchFold.fold("کتاب"), SearchFold.fold("كتاب"))
    XCTAssertEqual(SearchFold.fold("ایران"), SearchFold.fold("ايران"))
  }

  func testDecimalDigitsOfEveryScriptBecomeAscii() {
    XCTAssertEqual(SearchFold.fold("۱۲۳ ١٢٣ १२३ ১২৩ ０９"), "123 123 123 123 09")
  }

  func testHebrewPointsAreRemoved() {
    XCTAssertEqual(SearchFold.fold("שָׁלוֹם"), "שלום")
  }

  func testWidthLigaturesAndCompatibilityFormsFold() {
    XCTAssertEqual(SearchFold.fold("ＡＢＣ１２３"), "abc123")
    XCTAssertEqual(SearchFold.fold("ﬁne ﬂow"), "fine flow")
    XCTAssertEqual(SearchFold.fold("x²"), "x2")
  }

  func testMarksThatCarryMeaningAreKept() {
    // Devanagari vowel signs and Thai tone marks distinguish words.
    XCTAssertNotEqual(SearchFold.fold("दूध"), SearchFold.fold("दध"))
    XCTAssertNotEqual(SearchFold.fold("ที่"), SearchFold.fold("ท"))
    XCTAssertNotEqual(SearchFold.fold("ที่"), SearchFold.fold("ที"))
    XCTAssertEqual(SearchFold.fold("दूध खरीदें"), "दूध खरीदें")
  }

  func testKanaAndHangulStayComposed() {
    XCTAssertEqual(SearchFold.fold("がぎぐ パピプ"), "がぎぐ パピプ")
    XCTAssertEqual(SearchFold.fold("한국어"), "한국어")
    XCTAssertEqual(SearchFold.fold("牛奶 买"), "牛奶 买")
  }

  func testFoldIsIdempotent() {
    let samples = [
      "Łódź", "Всё ещё", "Işık İstanbul", "Καλημέρα ΛΟΓΟΣ", "أسماء الطلاب", "کتاب ۱۲۳",
      "שָׁלוֹם", "Straße ĐỪNG", "दूध खरीदें", "ทำวันนี้", "한국어 がぎぐ", "ＡＢＣ ﬁne", "plain ascii",
    ]
    for sample in samples {
      let once = SearchFold.fold(sample)
      XCTAssertEqual(SearchFold.fold(once), once, sample)
    }
  }

  func testRemovedMarkRanges() {
    for value: UInt32 in [0x0300, 0x0301, 0x036F, 0x0654, 0x064B, 0x065F, 0x0670, 0x05B8, 0x05C1] {
      XCTAssertTrue(SearchFold.isRemovedMark(Unicode.Scalar(value)!), String(value, radix: 16))
    }
    // The first scalar past a range, and signs of scripts that keep theirs.
    for value: UInt32 in [0x02FF, 0x0370, 0x05BE, 0x0660, 0x093C, 0x0942, 0x0E34, 0x0E48, 0x3099] {
      XCTAssertFalse(SearchFold.isRemovedMark(Unicode.Scalar(value)!), String(value, radix: 16))
    }
  }

  func testTokensAreFoldedWordsWithoutRepeats() {
    XCTAssertEqual(SearchFold.tokens("Всё, ещё ВСЁ!"), ["все", "еще"])
    XCTAssertEqual(SearchFold.tokens("  Łódź—kupić  mleko "), ["lodz", "kupic", "mleko"])
    XCTAssertEqual(SearchFold.tokens("e-mail a_b"), ["e", "mail", "a", "b"])
    XCTAssertEqual(SearchFold.tokens(""), [])
    XCTAssertEqual(SearchFold.tokens(" - % _ "), [])
  }

  func testTokensStopAtTheLimit() {
    let words = (1...20).map { "w\($0)" }.joined(separator: " ")
    XCTAssertEqual(SearchFold.tokens(words), (1...SearchFold.maxTokens).map { "w\($0)" })
  }
}
