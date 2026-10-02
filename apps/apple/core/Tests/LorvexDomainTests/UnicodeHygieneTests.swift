import XCTest
@testable import LorvexDomain

/// Ported from `lorvex_domain::unicode_hygiene::tests`.
final class UnicodeHygieneTests: XCTestCase {
  private func sanitize(_ s: String) -> String { UnicodeHygiene.sanitizeUserText(s) }

  func testStripsRTLOverride() {
    XCTAssertEqual(sanitize("pay\u{202E}dlrow_olleh.exe"), "paydlrow_olleh.exe")
  }

  func testStripsAllBidiControls() {
    var input = "a"
    for v in (0x202A...0x202E) { input.unicodeScalars.append(Unicode.Scalar(v)!) }
    for v in (0x2066...0x2069) { input.unicodeScalars.append(Unicode.Scalar(v)!) }
    input += "b"
    XCTAssertEqual(sanitize(input), "ab")
  }

  func testStripsZeroWidthSpace() {
    XCTAssertEqual(sanitize("ad\u{200B}min"), "admin")
  }

  func testStripsLRMRLM() {
    XCTAssertEqual(sanitize("ad\u{200E}min"), "admin")
    XCTAssertEqual(sanitize("ad\u{200F}min"), "admin")
  }

  func testStripsMongolianVowelSeparator() {
    XCTAssertEqual(sanitize("ad\u{180E}min"), "admin")
  }

  func testStripsArabicLetterMark() {
    XCTAssertEqual(sanitize("ad\u{061C}min"), "admin")
  }

  func testStripsWordJoinerAndInvisibleOperators() {
    for v in 0x2060...0x2064 {
      XCTAssertEqual(sanitize("ad\(Unicode.Scalar(v)!)min"), "admin")
    }
  }

  func testStripsZWNJ_ZWJ_BOM() {
    XCTAssertEqual(sanitize("a\u{200C}b\u{200D}c\u{FEFF}d"), "abcd")
  }

  // MARK: - Joiners and tag characters in context

  func testKeepsJoinersInEmojiSequences() {
    for emoji in ["👩‍💻", "👨‍👩‍👧", "🏳️‍🌈", "🧑🏽‍🚀", "❤️‍🔥", "🏃‍♂️"] {
      XCTAssertEqual(sanitize("\(emoji) Code review"), "\(emoji) Code review", emoji)
    }
  }

  func testKeepsJoinersThatShapeAScript() {
    XCTAssertEqual(sanitize("می\u{200C}خواهم کتاب\u{200C}ها"), "می\u{200C}خواهم کتاب\u{200C}ها")  // Persian
    XCTAssertEqual(sanitize("ශ්\u{200D}රී ලංකා"), "ශ්\u{200D}රී ලංකා")  // Sinhala: virama, joiner
    XCTAssertEqual(sanitize("क्\u{200D}ष"), "क्\u{200D}ष")  // Hindi half form: virama, joiner
    XCTAssertEqual(sanitize("র\u{200D}্যাব"), "র\u{200D}্যাব")  // Bengali: joiner, virama
  }

  func testStripsJoinersWithNothingToShape() {
    XCTAssertEqual(sanitize("ad\u{200D}min"), "admin")
    XCTAssertEqual(sanitize("ad\u{200C}min"), "admin")
    XCTAssertEqual(sanitize("\u{200D}👩"), "👩")
    XCTAssertEqual(sanitize("👩\u{200D}"), "👩")
    XCTAssertEqual(sanitize("1\u{200D}2"), "12", "ASCII keycap bases are not emoji here")
    XCTAssertEqual(sanitize("ب\u{200C} ه"), "ب ه", "a non-joiner needs letters on both sides")
    XCTAssertEqual(sanitize("👩\u{200B}\u{200D}💻"), "👩💻", "a stripped neighbor licenses nothing")
  }

  func testKeepsOnlyRecommendedSubdivisionFlags() {
    let scotland = "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
    XCTAssertEqual(sanitize("Trip \(scotland)"), "Trip \(scotland)")
    // Tag characters spelling anything else are an invisible message.
    let smuggled = "🏴\u{E0069}\u{E0067}\u{E006E}\u{E006F}\u{E0072}\u{E0065}\u{E007F}"
    XCTAssertEqual(sanitize("Trip \(smuggled)"), "Trip 🏴")
    XCTAssertEqual(sanitize("ok\u{E0001}\u{E0068}\u{E0069}\u{E007F}"), "ok")
    XCTAssertEqual(sanitize("ok\u{E0068}\u{E0069}"), "ok")
  }

  func testJoinerAndTagRulesAreIdempotent() {
    let wales = "🏴\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"
    let input = "👩\u{200D}💻 می\u{200C}خواهم a\u{200D}b \(wales) x\u{E0041} 👩\u{200B}\u{200D}💻"
    let once = sanitize(input)
    XCTAssertEqual(once, sanitize(once))
    XCTAssertFalse(UnicodeHygiene.containsStrippedCodepoint(once))
  }

  func testLookupKeyIgnoresJoiners() {
    XCTAssertEqual(normalizeLookupKey("کتاب\u{200C}ها"), normalizeLookupKey("کتابها"))
    XCTAssertEqual(normalizeLookupKey("👩\u{200D}💻"), normalizeLookupKey("👩💻"))
  }

  func testInvisibleCodepointsIncludeJoinersAndTags() {
    XCTAssertTrue(ValidationText.isVisuallyEmpty("\u{200D}\u{200C} \u{E0041}"))
    XCTAssertFalse(ValidationText.isVisuallyEmpty("👩\u{200D}💻"))
  }

  func testStripsLineParagraphSeparators() {
    XCTAssertEqual(sanitize("hello\u{2028}world\u{2029}!"), "helloworld!")
  }

  func testPreservesCJK() { XCTAssertEqual(sanitize("工作清单 — 今天"), "工作清单 — 今天") }
  func testPreservesEmoji() { XCTAssertEqual(sanitize("🎯 Daily focus 🚀"), "🎯 Daily focus 🚀") }
  func testPreservesRTLLetters() { XCTAssertEqual(sanitize("مرحبا"), "مرحبا") }

  func testPreservesWhitespaceAndNewlines() {
    XCTAssertEqual(sanitize("line one\nline\ttwo"), "line one\nline\ttwo")
  }

  func testNormalizesToNFC() {
    XCTAssertEqual(sanitize("cafe\u{0301}"), "caf\u{00E9}")
  }

  func testEmptyStringOK() { XCTAssertEqual(sanitize(""), "") }

  func testOnlyDisallowedCharsYieldsEmpty() {
    XCTAssertEqual(sanitize("\u{202E}\u{200B}\u{FEFF}\u{2028}"), "")
  }

  func testIdempotent() {
    let once = sanitize("Hello\u{202E} 世界\u{200B}! café")
    XCTAssertEqual(once, sanitize(once))
  }

  func testPreservesAccentedLatin() {
    XCTAssertEqual(sanitize("café naïve jalapeño"), "café naïve jalapeño")
  }

  func testStripsNullByte() {
    XCTAssertEqual(sanitize("foo\u{0000}bar"), "foobar")
  }

  func testStripsAllC0ControlsExceptTabLFCR() {
    for cp in 0x00...0x1F {
      let c = Unicode.Scalar(cp)!
      var input = "a"; input.unicodeScalars.append(c); input += "b"
      if cp == 0x09 || cp == 0x0A || cp == 0x0D {
        XCTAssertEqual(sanitize(input), input, "whitespace U+\(cp) preserved")
      } else {
        XCTAssertEqual(sanitize(input), "ab", "control U+\(cp) stripped")
      }
    }
  }

  func testStripsAllC1Controls() {
    for cp in 0x80...0x9F {
      let c = Unicode.Scalar(cp)!
      var input = "a"; input.unicodeScalars.append(c); input += "b"
      let out = sanitize(input)
      XCTAssertFalse(out.unicodeScalars.contains(c), "C1 U+\(cp) leaked")
    }
  }

  func testPreservesTabNewlineCR() {
    XCTAssertEqual(sanitize("line1\nline2\tcol\rcol2"), "line1\nline2\tcol\rcol2")
  }

  // MARK: - JSON scrubber

  func testJSONObjectStringLeavesAreScrubbed() {
    let value: JSONValue = ["display_name": "Bob\u{202E}resu_", "tagline": "ad\u{200B}min"]
    let out = UnicodeHygiene.sanitizeUserTextInJSON(value)
    XCTAssertEqual(out, ["display_name": "Bobresu_", "tagline": "admin"])
  }

  func testJSONArrayStringLeavesAreScrubbed() {
    let value: JSONValue = ["clean", "ad\u{200B}min", ["nested", "pay\u{202E}exe"]]
    let out = UnicodeHygiene.sanitizeUserTextInJSON(value)
    XCTAssertEqual(out, ["clean", "admin", ["nested", "payexe"]])
  }

  func testJSONObjectKeysAreNotScrubbed() {
    let key = "display\u{200B}name"
    let value: JSONValue = .object([key: "clean"])
    let out = UnicodeHygiene.sanitizeUserTextInJSON(value)
    guard case .object(let map) = out else { return XCTFail() }
    XCTAssertNotNil(map[key], "object keys must be left intact")
  }

  func testJSONNonStringLeavesPassThrough() {
    let value: JSONValue = ["n": 42, "b": true, "null": nil, "arr": [1, 2, false]]
    XCTAssertEqual(UnicodeHygiene.sanitizeUserTextInJSON(value), value)
  }

  func testJSONDeepNestingScrubsEveryLevel() {
    let value: JSONValue = ["level1": ["level2": [["level3": "ad\u{200B}min"]]]]
    let out = UnicodeHygiene.sanitizeUserTextInJSON(value)
    XCTAssertEqual(out, ["level1": ["level2": [["level3": "admin"]]]])
  }
}
