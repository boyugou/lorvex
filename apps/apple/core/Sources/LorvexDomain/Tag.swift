import Foundation
#if canImport(CoreFoundation)
  import CoreFoundation
#endif

/// Tag domain types and lookup key normalization.
///
/// ``normalizeLookupKey(_:)`` is the single canonical way to convert a
/// human-supplied display name into a machine-comparable lookup key. All
/// code paths that need to match tags by name call this function. No ad-hoc
/// lowercasing elsewhere in the codebase.
///
/// Rules (in order):
/// 1. Strip bidi / zero-width / invisible controls via ``UnicodeHygiene/sanitizeUserText(_:)``
/// 2. Unicode NFKC normalization
/// 3. Trim leading / trailing whitespace
/// 4. Unicode default casefold (UTS #18 R3 — `ß`→`ss`, Greek capital sigma
///    always to medial `σ`, Turkish dotted `İ` → `i` + combining dot, etc.)
/// 5. Collapse internal whitespace runs (any Unicode whitespace) to a single
///    ASCII space
///
/// Step 4 uses CoreFoundation's `CFStringFold` with
/// `kCFCompareCaseInsensitive`, which implements Unicode default casefold.
/// Swift's `String.lowercased()` is not equivalent: it preserves Greek final
/// sigma at word end and leaves `ß` untouched, so two devices producing the
/// same display string would otherwise reach different lookup keys.

/// Normalize a display name into a machine-comparable lookup key suitable
/// for UNIQUE constraint enforcement and case-insensitive tag deduplication
/// across sync boundaries.
public func normalizeLookupKey(_ displayName: String) -> String {
  let scrubbed = UnicodeHygiene.sanitizeUserText(displayName)
  // NFKC normalization.
  let nfkc = scrubbed.precomposedStringWithCompatibilityMapping
  let trimmed = nfkc.trimmingCharacters(in: .whitespacesAndNewlines)

  // Casefold via CFStringFold (Unicode default casefold).
  let folded = defaultCaseFold(trimmed)

  var result = ""
  result.reserveCapacity(folded.unicodeScalars.count)
  var prevSpace = false
  for scalar in folded.unicodeScalars {
    if isUnicodeWhitespace(scalar) {
      if !prevSpace {
        result.append(" ")
        prevSpace = true
      }
    } else {
      result.unicodeScalars.append(scalar)
      prevSpace = false
    }
  }
  return result
}

/// Unicode default casefold via CoreFoundation: `ß`→`ss`, Greek
/// capital sigma always folds to medial `σ` (not the positional final
/// `ς`), Turkish capital `İ` → `i` + COMBINING DOT ABOVE, etc.
private func defaultCaseFold(_ s: String) -> String {
  let mutable = NSMutableString(string: s)
  CFStringFold(mutable as CFMutableString, [.compareCaseInsensitive], nil)
  return mutable as String
}

/// The Unicode `White_Space` property covers ASCII whitespace, NBSP (U+00A0),
/// all Zs-category spaces (em space, en space, …), and U+0085 / U+200E / U+200F
/// etc. that have the property. Foundation's
/// `CharacterSet.whitespacesAndNewlines` is close but does not include every
/// White_Space scalar, so we check the Unicode property directly.
private func isUnicodeWhitespace(_ scalar: Unicode.Scalar) -> Bool {
  scalar.properties.isWhitespace
}
