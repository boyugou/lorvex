import Foundation

/// Unicode hygiene for user-supplied free-text fields.
///
/// ``sanitizeUserText(_:)`` strips the invisible codepoints that enable
/// rendering and prompt attacks — bidi spoofing, hidden zero-width splits and
/// merges, line-terminator injection, text smuggled in tag characters — and
/// then normalizes to NFC. Visible characters from every script are preserved
/// verbatim, and so are the invisible codepoints a script or an emoji needs
/// where it needs them:
///
/// - The zero-width joiner and non-joiner (U+200D, U+200C) beside a virama,
///   where they choose an Indic conjunct's form ("क्‍ष", Sinhala "ශ්‍රී",
///   Bengali "র‍্য"); between letters of a cursive-joining script (Arabic,
///   Syriac, N'Ko, Mongolian, and others), where they decide whether the
///   letters join (Persian "می‌خواهم"); and the joiner between the emoji of
///   an emoji sequence ("👩‍💻", "🏳️‍🌈").
/// - Tag characters (U+E0020…U+E007F) only as the three subdivision flags
///   Unicode recommends for interchange: England, Scotland, and Wales.
///
/// Anywhere else those codepoints carry nothing visible, and they are
/// stripped.
public enum UnicodeHygiene {
  /// Returns `true` for codepoints stripped wherever they occur.
  ///
  /// The set covers C0 controls except tab/LF/CR, DEL and the C1 block, the
  /// bidi override/isolate/mark family, the zero-width space and BOM, the word
  /// joiner and invisible operators, the Mongolian Vowel Separator, and the
  /// line/paragraph separators. The joiners and tag characters, which some
  /// text needs, are judged in context by ``sanitizeUserText(_:)``.
  public static func isDisallowedCodepoint(_ c: Unicode.Scalar) -> Bool {
    let v = c.value
    // C0 (0x00..=0x1F) except tab (0x09), LF (0x0A), CR (0x0D).
    if v <= 0x1F && v != 0x09 && v != 0x0A && v != 0x0D {
      return true
    }
    // DEL (0x7F) + C1 block (0x80..=0x9F).
    if v == 0x7F || (0x80...0x9F).contains(v) {
      return true
    }
    switch v {
    case 0x202A...0x202E,  // bidi overrides / isolates
         0x2066...0x2069,
         0x200E, 0x200F,   // LRM / RLM
         0x061C,           // Arabic Letter Mark
         0x200B,           // ZWSP
         0xFEFF,           // BOM / ZWNBSP
         0x2060...0x2064,  // word-joiner + invisible operators
         0x180E,           // Mongolian Vowel Separator
         0x2028, 0x2029:   // line / paragraph separators
      return true
    default:
      return false
    }
  }

  /// Whether `c` draws nothing on its own: a codepoint
  /// ``isDisallowedCodepoint(_:)`` strips, a zero-width joiner or non-joiner,
  /// or a tag character. Text made of these and whitespace reads as empty.
  public static func isInvisibleCodepoint(_ c: Unicode.Scalar) -> Bool {
    isDisallowedCodepoint(c) || isJoiner(c) || isTagCharacter(c)
  }

  /// Sanitize user-supplied text: strip the disallowed codepoints, and the
  /// joiners and tag characters outside the places described on
  /// ``UnicodeHygiene``, then normalize to NFC. Applied at every write
  /// boundary accepting free text authored by a human or model. Preserves
  /// tab/LF/CR for multi-line bodies. Idempotent.
  public static func sanitizeUserText(_ input: String) -> String {
    String(keptScalars(input)).precomposedStringWithCanonicalMapping
  }

  /// Whether ``sanitizeUserText(_:)`` would remove any codepoint of `input`
  /// (normalization aside).
  public static func containsStrippedCodepoint(_ input: String) -> Bool {
    keptScalars(input).count != input.unicodeScalars.count
  }

  /// `input` without zero-width joiners and non-joiners. A joiner chooses the
  /// shape of the glyphs around it, not the word, so a key that identifies a
  /// name ignores it.
  public static func removingJoiners(_ input: String) -> String {
    var filtered = String.UnicodeScalarView()
    filtered.append(contentsOf: input.unicodeScalars.lazy.filter { !isJoiner($0) })
    return String(filtered)
  }

  /// Recursively scrub every JSON string leaf via ``sanitizeUserText(_:)``.
  ///
  /// Object keys are left intact (schema-defined identifiers); numbers,
  /// booleans, and null pass through.
  public static func sanitizeUserTextInJSON(_ value: JSONValue) -> JSONValue {
    switch value {
    case .string(let s):
      return .string(sanitizeUserText(s))
    case .array(let items):
      return .array(items.map(sanitizeUserTextInJSON))
    case .object(let map):
      return .object(map.mapValues(sanitizeUserTextInJSON))
    default:
      return value
    }
  }

  // MARK: - Context

  /// The scalars of `input` that ``sanitizeUserText(_:)`` keeps. A joiner is
  /// judged by its neighbors as written, so removing a stripped neighbor never
  /// licenses it on a second pass.
  private static func keptScalars(_ input: String) -> String.UnicodeScalarView {
    let scalars = Array(input.unicodeScalars)
    var kept = String.UnicodeScalarView()
    var index = 0
    while index < scalars.count {
      if let end = subdivisionFlagEnd(scalars, at: index) {
        kept.append(contentsOf: scalars[index..<end])
        index = end
        continue
      }
      let scalar = scalars[index]
      let strips =
        isDisallowedCodepoint(scalar) || isTagCharacter(scalar)
        || (isJoiner(scalar) && !joinerBelongs(scalars, at: index))
      if !strips {
        kept.append(scalar)
      }
      index += 1
    }
    return kept
  }

  private static func isJoiner(_ c: Unicode.Scalar) -> Bool {
    c.value == 0x200C || c.value == 0x200D
  }

  private static func isTagCharacter(_ c: Unicode.Scalar) -> Bool {
    c.value == 0xE0001 || (0xE0020...0xE007F).contains(c.value)
  }

  /// Whether the joiner at `index` does work: beside a virama, between letters
  /// of a cursive-joining script (the joiner needs such a letter on one side,
  /// the non-joiner on both), or, for the joiner, between two emoji.
  private static func joinerBelongs(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
    let before = index > 0 ? scalars[index - 1] : nil
    let after = index + 1 < scalars.count ? scalars[index + 1] : nil
    if before.map(isVirama) == true || after.map(isVirama) == true {
      return true
    }
    let letterBefore = base(of: scalars, from: index - 1, step: -1).map(isCursiveJoiningLetter) == true
    let letterAfter = base(of: scalars, from: index + 1, step: 1).map(isCursiveJoiningLetter) == true
    if scalars[index].value == 0x200C {
      return letterBefore && letterAfter
    }
    if letterBefore || letterAfter {
      return true
    }
    guard let before, let after else { return false }
    return endsEmoji(before) && isEmojiElement(after)
  }

  /// The nearest scalar from `start` in the direction of `step` that is not a
  /// combining mark, so a vowel sign between a letter and a joiner is skipped.
  private static func base(of scalars: [Unicode.Scalar], from start: Int, step: Int) -> Unicode.Scalar? {
    var index = start
    while scalars.indices.contains(index) {
      switch scalars[index].properties.generalCategory {
      case .nonspacingMark, .enclosingMark: index += step
      default: return scalars[index]
      }
    }
    return nil
  }

  private static func isVirama(_ c: Unicode.Scalar) -> Bool {
    c.properties.canonicalCombiningClass == .virama
  }

  /// A letter of a script whose letters join cursively, where the joiners
  /// choose between joined and separate forms.
  private static func isCursiveJoiningLetter(_ c: Unicode.Scalar) -> Bool {
    switch c.properties.generalCategory {
    case .otherLetter, .modifierLetter, .uppercaseLetter, .lowercaseLetter: break
    default: return false
    }
    switch c.value {
    case 0x0600...0x077F,  // Arabic, Syriac, Arabic Supplement
         0x07C0...0x07FF,  // N'Ko
         0x0840...0x08FF,  // Mandaic, Syriac Supplement, Arabic Extended-B and -A
         0x1800...0x18AF,  // Mongolian
         0xA840...0xA87F,  // Phags-pa
         0xFB50...0xFDFF, 0xFE70...0xFEFF,  // Arabic presentation forms
         0x10AC0...0x10AFF,  // Manichaean
         0x10B80...0x10BAF,  // Psalter Pahlavi
         0x10D00...0x10D3F,  // Hanifi Rohingya
         0x10EC0...0x10EFF,  // Arabic Extended-C
         0x10F30...0x10FDF,  // Sogdian, Old Uyghur, Chorasmian
         0x1E900...0x1E95F:  // Adlam
      return true
    default:
      return false
    }
  }

  /// A scalar an emoji ends with before a joiner: an emoji (not one of the
  /// ASCII keycap bases), a skin-tone modifier, or the emoji presentation
  /// selector.
  private static func endsEmoji(_ c: Unicode.Scalar) -> Bool {
    c.value == 0xFE0F || isEmojiElement(c)
  }

  private static func isEmojiElement(_ c: Unicode.Scalar) -> Bool {
    c.value > 0x7F && c.properties.isEmoji
  }

  /// The tag spellings of the subdivision flags Unicode recommends for
  /// interchange.
  private static let subdivisionFlags: Set<String> = ["gbeng", "gbsct", "gbwls"]

  /// The end of the subdivision flag that starts at `start`: a waving black
  /// flag, tag characters spelling a recommended subdivision, and the cancel
  /// tag. `nil` when no such flag starts there.
  private static func subdivisionFlagEnd(_ scalars: [Unicode.Scalar], at start: Int) -> Int? {
    guard scalars[start].value == 0x1F3F4 else { return nil }
    var spelling = String.UnicodeScalarView()
    var index = start + 1
    while index < scalars.count, spelling.count < 7, (0xE0020...0xE007E).contains(scalars[index].value),
      let letter = Unicode.Scalar(scalars[index].value - 0xE0000)
    {
      spelling.append(letter)
      index += 1
    }
    guard index < scalars.count, scalars[index].value == 0xE007F,
      subdivisionFlags.contains(String(spelling))
    else { return nil }
    return index + 1
  }
}
