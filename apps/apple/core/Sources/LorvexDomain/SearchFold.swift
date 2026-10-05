import Foundation

/// The comparison form of text for search: lowercase, without combining
/// marks, with the letter variants a person typing a query does not tell apart
/// written as one letter.
///
/// The FTS5 `unicode61` index folds case and the accents that decompose in
/// Latin, so "cafe" finds "Café", but it leaves several everyday differences
/// between stored text and typed queries: Russian "ё" against "е", Polish "ł"
/// against "l", Vietnamese "đ" against "d", German "ß" against "ss", Greek
/// accented against bare vowels, Turkish dotless "ı" and dotted "İ" against
/// "i", and Arabic-script hamza, yeh, and kaf variants. Text written by an
/// assistant tends to carry the complete spelling while a query is typed
/// without it, so the search falls back to comparing both sides through
/// ``fold(_:)`` when the index finds nothing.
///
/// The fold is a one-way projection used only for comparison. Scripts whose
/// combining marks carry meaning (Devanagari, Thai, and the other Indic and
/// Southeast Asian scripts) keep them, and kana and Hangul are left composed.
public enum SearchFold {
  /// The most query tokens ``tokens(_:)`` returns; later words are ignored.
  public static let maxTokens = 8

  /// `text` in comparison form.
  ///
  /// The steps, in order: compatibility decomposition (so full-width letters,
  /// ligatures, and compatibility digits become their plain forms), removal of
  /// the combining marks listed in ``isRemovedMark(_:)``, lowercasing, the
  /// letter replacements (ß as "ss", ł as "l", Farsi yeh as Arabic yeh, and so
  /// on), decimal digits of every script written as ASCII digits, and
  /// canonical recomposition. A string of ASCII characters only skips these
  /// steps and is just lowercased.
  public static func fold(_ text: String) -> String {
    if text.utf8.allSatisfy({ $0 < 0x80 }) { return text.lowercased() }
    var folded = String.UnicodeScalarView()
    for scalar in text.decomposedStringWithCompatibilityMapping.unicodeScalars {
      if isRemovedMark(scalar) { continue }
      if scalar.properties.changesWhenLowercased {
        for lowered in scalar.properties.lowercaseMapping.unicodeScalars {
          appendFolded(lowered, to: &folded)
        }
      } else {
        appendFolded(scalar, to: &folded)
      }
    }
    return String(folded).precomposedStringWithCanonicalMapping
  }

  /// The folded words of `query`, in order and without repeats, at most
  /// ``maxTokens``. A word is a run of letters and digits; punctuation and
  /// whitespace only separate words.
  public static func tokens(_ query: String) -> [String] {
    var seen = Set<String>()
    var words: [String] = []
    for run in Fts.splitAlnumRuns(fold(query)) where seen.insert(run).inserted {
      words.append(run)
      if words.count == maxTokens { break }
    }
    return words
  }

  /// Combining marks that only decorate a base letter: the general combining
  /// diacritics (Latin, Greek, Cyrillic, and Vietnamese tones), the Hebrew
  /// points and cantillation, and the Arabic vowel and Quranic marks. The
  /// vowel signs of Indic and Southeast Asian scripts are not in this set.
  static func isRemovedMark(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x0300...0x036F, 0x0483...0x0489, 0x0591...0x05BD, 0x05BF, 0x05C1...0x05C2,
      0x05C4...0x05C5, 0x05C7, 0x0610...0x061A, 0x064B...0x065F, 0x0670, 0x06D6...0x06DC,
      0x06DF...0x06E4, 0x06E7...0x06E8, 0x06EA...0x06ED, 0x1AB0...0x1AFF, 0x1DC0...0x1DFF,
      0x20D0...0x20FF, 0xFE20...0xFE2F:
      return true
    default:
      return false
    }
  }

  /// Appends a lowercase scalar, written as its replacement letters, as an
  /// ASCII digit when it is a decimal digit of another script, or unchanged.
  private static func appendFolded(
    _ scalar: Unicode.Scalar, to folded: inout String.UnicodeScalarView
  ) {
    if scalar.value < 0x80 {
      folded.append(scalar)
    } else if let replacement = replacement(for: scalar) {
      folded.append(contentsOf: replacement.unicodeScalars)
    } else if scalar.properties.numericType == .decimal,
      let value = scalar.properties.numericValue, (0...9).contains(value)
    {
      folded.append(Unicode.Scalar(UInt8(48 + Int(value))))
    } else {
      folded.append(scalar)
    }
  }

  /// The letters a lowercase scalar without a canonical decomposition is
  /// written as, or `nil` when it stays: Latin letters (ß, æ, œ, ø, ł, đ, ð,
  /// þ, ħ, ı, ĸ, ŀ, ŧ), the Greek final sigma, and the Arabic-script variants
  /// a keyboard layout produces interchangeably (alef wasla, teh marbuta, alef
  /// maksura, Farsi yeh, Farsi kaf, the heh forms of Urdu and Uyghur, yeh
  /// barree, and the tatweel filler, which is dropped).
  private static func replacement(for scalar: Unicode.Scalar) -> String? {
    switch scalar.value {
    case 0x00DF: return "ss"
    case 0x00E6: return "ae"
    case 0x0153: return "oe"
    case 0x00F8: return "o"
    case 0x0142, 0x0140: return "l"
    case 0x0111, 0x00F0: return "d"
    case 0x00FE: return "th"
    case 0x0127: return "h"
    case 0x0131: return "i"
    case 0x0138: return "k"
    case 0x0167: return "t"
    case 0x03C2: return "σ"
    case 0x0671: return "\u{0627}"
    case 0x0629, 0x06C1, 0x06BE, 0x06D5: return "\u{0647}"
    case 0x0649, 0x06CC, 0x06D2: return "\u{064A}"
    case 0x06A9: return "\u{0643}"
    case 0x0640: return ""
    default: return nil
    }
  }
}
