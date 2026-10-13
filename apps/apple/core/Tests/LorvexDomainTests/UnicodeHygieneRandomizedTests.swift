import Foundation
import XCTest

@testable import LorvexDomain

/// Random strings built from the codepoints the sanitizer treats specially (joiners, tag
/// characters, controls, bidi marks, combining marks, scripts that join) keep the properties the
/// write boundary relies on. A text stored by one device is sanitized again when a backup
/// restores it or a peer's edit arrives, so a second pass must change nothing; otherwise the
/// two copies drift apart.
///
/// `UNICODEFUZZ_ROUNDS` and `UNICODEFUZZ_SEED` widen a run: for example
/// `UNICODEFUZZ_ROUNDS=2000000 UNICODEFUZZ_SEED=5 swift test --filter UnicodeHygieneRandomized`.
final class UnicodeHygieneRandomizedTests: XCTestCase {
  private var rounds: Int {
    Int(ProcessInfo.processInfo.environment["UNICODEFUZZ_ROUNDS"] ?? "") ?? 30_000
  }

  private func seed(_ fallback: UInt64) -> UInt64 {
    UInt64(ProcessInfo.processInfo.environment["UNICODEFUZZ_SEED"] ?? "") ?? fallback
  }

  private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  private static let pieces: [String] = [
    "a", "Z", "é", "e\u{301}", "ñ", "n\u{303}", " ", "  ", "\t", "\n", "\r\n", "\u{85}", "\u{2028}",
    "\u{2029}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{2060}", "\u{200E}", "\u{200F}",
    "\u{202E}", "\u{202C}", "\u{2066}", "\u{2069}", "\u{061C}", "\u{180E}", "\u{FE0F}", "\u{FE0E}",
    "\u{0}", "\u{7}", "\u{9F}", "\u{E0020}", "\u{E0067}", "\u{E007F}", "🏴", "👨", "👩", "👧",
    "👨\u{200D}👩\u{200D}👧", "🇺🇸", "🇯🇵", "❤️", "❤\u{200D}🔥", "👍🏽", "\u{1F3FD}", "क", "्", "ष",
    "\u{094D}\u{200D}", "\u{094D}\u{200C}", "ب", "ـ", "ا", "ک", "\u{064B}", "\u{0651}", "한", "ᄒ",
    "\u{1161}", "\u{11A8}", "中", "文", "\u{3099}", "\u{0F40}", "\u{0F74}", "\u{1100}", "1", "-",
    "\u{0301}", "\u{0323}", "\u{0307}", "\u{0344}", "\u{0958}", "\u{1E9B}\u{0323}", "ﬁ", "Å", "Å",
  ]

  /// Pieces that fold, decompose, or change case in unusual ways, for the tag lookup key.
  private static let foldingPieces: [String] = [
    "ß", "ẞ", "İ", "ı", "I", "i", "Σ", "σ", "ς", "ǅ", "ǆ", "Ǆ", "ﬃ", "ﬁ", "K", "K", "Å", "Å", "Ω",
    "Ω", "µ", "μ", "ſ", "s", "ŉ", "ǰ", "ΐ", "\u{0345}", "\u{03B9}", "ᾳ", "ᾼ", "ᾀ", "Ⅷ", "ⅷ", "①",
    "㎏", "ﾊ", "ハ", "\u{3099}", "\u{FF9E}", "²", "½", "™", "…", "Ａ", "ａ", "\u{00A0}", "\u{2003}",
    "\u{3000}", " ", "  ", "a", "B", "é", "e\u{301}", "ǈ", "ᾈ", "ᲀ", "ᲈ", "Ꙋ", "ꙋ", "ẛ", "ẛ\u{323}",
  ]

  func testTheTagLookupKeyIsStableWhenNormalizedAgain() {
    var rng = SplitMix64(state: seed(13))
    var failures: [String] = []
    let pool = Self.foldingPieces + Self.pieces
    for _ in 0..<rounds {
      let input = (0..<Int.random(in: 1...8, using: &rng))
        .map { _ in pool[Int.random(in: 0..<pool.count, using: &rng)] }
        .joined()
      let key = normalizeLookupKey(input)
      let again = normalizeLookupKey(key)
      if key != again {
        failures.append("\(scalars(input)) → \(scalars(key)) → \(scalars(again))")
        if failures.count >= 12 { break }
      }
    }
    XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
  }

  private func randomText(_ rng: inout SplitMix64) -> String {
    (0..<Int.random(in: 0...14, using: &rng))
      .map { _ in Self.pieces[Int.random(in: 0..<Self.pieces.count, using: &rng)] }
      .joined()
  }

  private func scalars(_ text: String) -> String {
    text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
  }

  func testSanitizingTwiceChangesNothing() {
    var rng = SplitMix64(state: seed(7))
    var failures: [String] = []
    for _ in 0..<rounds {
      let input = randomText(&rng)
      let once = UnicodeHygiene.sanitizeUserText(input)
      let twice = UnicodeHygiene.sanitizeUserText(once)
      if once != twice {
        failures.append("multi-line \(scalars(input)) → \(scalars(once)) → \(scalars(twice))")
      }
      let line = UnicodeHygiene.sanitizeSingleLineText(input)
      let lineAgain = UnicodeHygiene.sanitizeSingleLineText(line)
      if line != lineAgain {
        failures.append("single-line \(scalars(input)) → \(scalars(line)) → \(scalars(lineAgain))")
      }
      if failures.count >= 12 { break }
    }
    XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
  }

  func testTheOutputHoldsNothingTheSanitizerWouldStrip() {
    var rng = SplitMix64(state: seed(11))
    var failures: [String] = []
    for _ in 0..<rounds {
      let input = randomText(&rng)
      let once = UnicodeHygiene.sanitizeUserText(input)
      if UnicodeHygiene.containsStrippedCodepoint(once) {
        failures.append("\(scalars(input)) → \(scalars(once))")
      }
      if once != once.precomposedStringWithCanonicalMapping {
        failures.append("not NFC: \(scalars(input)) → \(scalars(once))")
      }
      let line = UnicodeHygiene.sanitizeSingleLineText(input)
      if line.unicodeScalars.contains(where: { "\n\r\t\u{85}\u{2028}\u{2029}".unicodeScalars.contains($0) }) {
        failures.append("single-line kept a break: \(scalars(input)) → \(scalars(line))")
      }
      if failures.count >= 12 { break }
    }
    XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
  }
}
