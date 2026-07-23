import Foundation

/// Unicode hygiene for user-supplied free-text fields.
///
/// ``sanitizeUserText(_:)`` strips invisible / formatting control codepoints
/// that enable rendering attacks (bidi spoofing, zero-width merges,
/// line-terminator injection) and then normalizes to NFC. Letter-like
/// characters from every script are preserved verbatim.
///
/// ``isDisallowedCodepoint(_:)`` is the single source of truth for the strip
/// set, shared with ``isDangerousCodepoint(_:)`` so the two surfaces can never
/// drift on which codepoints are dropped (they differ only in CR handling and
/// NFC normalization).
public enum UnicodeHygiene {
  /// Returns `true` for codepoints that should be stripped from user text.
  ///
  /// The strip set covers C0 controls except tab/LF/CR,
  /// DEL + the C1 block, the bidi override/isolate/mark family, zero-width
  /// characters + BOM, word-joiner + invisible operators, Mongolian Vowel
  /// Separator, and Unicode line/paragraph separators.
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
         0x200B...0x200D,  // ZWSP / ZWNJ / ZWJ
         0xFEFF,           // BOM / ZWNBSP
         0x2060...0x2064,  // word-joiner + invisible operators
         0x180E,           // Mongolian Vowel Separator
         0x2028, 0x2029:   // line / paragraph separators
      return true
    default:
      return false
    }
  }

  /// Sanitize user-supplied text: strip the disallowed codepoints, then
  /// normalize to NFC. Applied at every write boundary accepting free text
  /// authored by a human or model. Preserves tab/LF/CR for multi-line bodies.
  public static func sanitizeUserText(_ input: String) -> String {
    var filtered = String.UnicodeScalarView()
    for scalar in input.unicodeScalars where !isDisallowedCodepoint(scalar) {
      filtered.append(scalar)
    }
    return String(filtered).precomposedStringWithCanonicalMapping
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
}
