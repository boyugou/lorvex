import Foundation
import LorvexCore
import Testing

/// Typed numbers read in the digits of any script, and number fields start in
/// the user's digits (``LorvexNumberInput``).
@Suite("Number input")
struct LorvexNumberInputTests {
  @Test("A whole number reads in the digits of any script, mixed freely")
  func wholeNumbersReadInAnyScript() {
    #expect(LorvexNumberInput.integer(from: "45") == 45)
    #expect(LorvexNumberInput.integer(from: "٤٥") == 45)  // Arabic-Indic
    #expect(LorvexNumberInput.integer(from: "۴۵") == 45)  // Persian and Urdu
    #expect(LorvexNumberInput.integer(from: "४५") == 45)  // Devanagari
    #expect(LorvexNumberInput.integer(from: "４５") == 45)  // full width
    #expect(LorvexNumberInput.integer(from: "٤5") == 45)
  }

  @Test("Whitespace, a sign, and invisible marks around the digits are read through")
  func surroundingsAreReadThrough() {
    #expect(LorvexNumberInput.integer(from: " 45\n") == 45)
    // A right-to-left paste can carry a right-to-left mark or isolates.
    #expect(LorvexNumberInput.integer(from: "\u{200F}٤٥") == 45)
    #expect(LorvexNumberInput.integer(from: "\u{2067}٤٥\u{2069}") == 45)
    #expect(LorvexNumberInput.integer(from: "-٣") == -3)
    #expect(LorvexNumberInput.integer(from: "+7") == 7)
  }

  @Test("Text that is not a whole number in decimal digits reads as nothing")
  func nonNumbersReadAsNothing() {
    #expect(LorvexNumberInput.integer(from: "") == nil)
    #expect(LorvexNumberInput.integer(from: "soon") == nil)
    #expect(LorvexNumberInput.integer(from: "١٬٢٣٤") == nil)
    #expect(LorvexNumberInput.integer(from: "4.5") == nil)
    #expect(LorvexNumberInput.integer(from: "½") == nil)
    #expect(LorvexNumberInput.integer(from: "Ⅻ") == nil)
    #expect(LorvexNumberInput.integer(from: "五") == nil)
    #expect(LorvexNumberInput.integer(from: "99999999999999999999") == nil)
  }

  @Test("A decimal reads with a point in any script's digits, and nothing but digits")
  func decimals() {
    #expect(LorvexNumberInput.decimal(from: "1.5") == 1.5)
    #expect(LorvexNumberInput.decimal(from: "１.５") == 1.5)
    #expect(LorvexNumberInput.decimal(from: "٢") == 2)
    #expect(LorvexNumberInput.decimal(from: "nan") == nil)
    #expect(LorvexNumberInput.decimal(from: "inf") == nil)
    #expect(LorvexNumberInput.decimal(from: "0x1p3") == nil)
    #expect(LorvexNumberInput.decimal(from: "1e3") == nil)
  }

  @Test("A field starts in the locale's digits without grouping, and reads back")
  func fieldTextUsesTheLocalesDigits() {
    let saudi = Locale(identifier: "ar_SA")
    #expect(LorvexNumberInput.text(for: 1440, locale: Locale(identifier: "en_US")) == "1440")
    #expect(LorvexNumberInput.text(for: 1440, locale: saudi) == "١٤٤٠")
    #expect(LorvexNumberInput.text(for: 45, locale: Locale(identifier: "fa_IR")) == "۴۵")
    // A user who picked Latin digits for Arabic keeps them.
    #expect(LorvexNumberInput.text(for: 45, locale: Locale(identifier: "ar_SA@numbers=latn")) == "45")
    for value in [1, 45, 1440] {
      #expect(LorvexNumberInput.integer(from: LorvexNumberInput.text(for: value, locale: saudi)) == value)
    }
  }
}
