import Foundation

/// FTS5 query sanitization shared across SQLite consumers.
///
/// Caps raw input length, splits user input into FTS5 `Word` / `Phrase`
/// units, strips characters with special meaning in FTS5 query syntax,
/// and emits a stable canonical form: each non-last unit unwildcarded,
/// the last carrying a `*` prefix wildcard so live-typed queries match.
public enum Fts {
  static let maxFtsTokens = 64
  /// Hard cap on per-token character count.
  static let maxFtsTokenChars = 64
  /// Hard cap on raw query character count before tokenization.
  static let maxFtsQueryChars = 512
  /// Threshold under which a bare trailing token should be retried via
  /// `LIKE %tok%` because FTS5 prefix matching only matches the start of
  /// indexed words.
  static let shortTokenMaxLen = 3

  // MARK: - Alphanumeric predicate

  /// Unicode `Alphabetic` (which includes ideographic CJK + hiragana + katakana
  /// + hangul) OR any numeric category. Operates on a single `Unicode.Scalar`.
  static func isUnicodeAlphanumeric(_ s: Unicode.Scalar) -> Bool {
    if s.properties.isAlphabetic { return true }
    switch s.properties.generalCategory {
    case .decimalNumber, .letterNumber, .otherNumber:
      return true
    default:
      return false
    }
  }

  static func anyAlphanumeric(_ s: String) -> Bool {
    s.unicodeScalars.contains(where: isUnicodeAlphanumeric)
  }

  static func anyWhitespace(_ s: String) -> Bool {
    s.unicodeScalars.contains { $0.properties.isWhitespace }
  }

  // MARK: - Length caps

  /// Truncate `query` to at most `maxFtsQueryChars` characters, respecting
  /// Unicode-scalar boundaries.
  public static func capFtsQueryLength(_ query: String) -> String {
    var idx = query.unicodeScalars.startIndex
    let end = query.unicodeScalars.endIndex
    var count = 0
    while idx < end, count < maxFtsQueryChars {
      idx = query.unicodeScalars.index(after: idx)
      count += 1
    }
    if idx == end { return query }
    return String(String.UnicodeScalarView(query.unicodeScalars[..<idx]))
  }

  // MARK: - CJK detection

  /// Returns `true` if the query contains any CJK character. FTS5 unicode61
  /// treats CJK runs as opaque tokens because it splits only on whitespace
  /// and punctuation, so callers must route CJK queries through a LIKE
  /// fallback path.
  public static func containsCjk(_ query: String) -> Bool {
    for s in query.unicodeScalars {
      let v = s.value
      if (0x4E00...0x9FFF).contains(v)  // CJK Unified Ideographs
        || (0x3400...0x4DBF).contains(v)  // Extension A
        || (0x20000...0x2A6DF).contains(v)  // Extension B
        || (0x3040...0x309F).contains(v)  // Hiragana
        || (0x30A0...0x30FF).contains(v)  // Katakana
        || (0x31F0...0x31FF).contains(v)  // Katakana Phonetic Extensions
        || (0xAC00...0xD7AF).contains(v)  // Hangul Syllables
        || (0x1100...0x11FF).contains(v)  // Hangul Jamo
        || (0xFF65...0xFF9F).contains(v)  // Halfwidth Katakana
        || (0xF900...0xFAFF).contains(v)  // CJK Compatibility Ideographs
      {
        return true
      }
    }
    return false
  }

  /// Returns `true` when a query should skip FTS5 entirely and go straight
  /// to the LIKE fallback path: any CJK content, or no alphanumeric scalar
  /// anywhere in the input.
  public static func shouldUseLikeFallback(_ query: String) -> Bool {
    if containsCjk(query) { return true }
    return !anyAlphanumeric(query)
  }

  /// Returns the trailing alphanumeric run when it is 2–3 chars long and
  /// the caller should plan a `LIKE %tok%` retry (FTS5 prefix-only would
  /// miss substring intent). Returns `nil` for longer trailers, for
  /// quoted-phrase trailers, for email-/dotted-identifier trailers (which
  /// already become phrases), or when there is no alphanumeric tail.
  public static func shortTrailingTokenForLikeRetry(_ query: String) -> String? {
    // Trim trailing whitespace via scalar view.
    let trimmed = trimEnd(query)
    if trimmed.isEmpty { return nil }
    if trimmed.hasSuffix("\"") { return nil }
    // Walk back to the first non-alphanumeric scalar.
    let scalars = trimmed.unicodeScalars
    var idx = scalars.endIndex
    while idx > scalars.startIndex {
      let prev = scalars.index(before: idx)
      if !isUnicodeAlphanumeric(scalars[prev]) {
        break
      }
      idx = prev
    }
    // `idx` points at the first scalar of the trailing alnum run (or the
    // end-of-string if there were none).
    if idx == scalars.endIndex { return nil }
    let trailing = String(String.UnicodeScalarView(scalars[idx..<scalars.endIndex]))
    if trailing.isEmpty { return nil }
    // Char-before-trailing-run: disqualify retry on email/dotted identifiers.
    if idx > scalars.startIndex {
      let prev = scalars[scalars.index(before: idx)]
      if prev == "@" || prev == "." { return nil }
    }
    let count = trailing.unicodeScalars.count
    if count >= 2 && count <= shortTokenMaxLen {
      return trailing
    }
    return nil
  }

  static func trimEnd(_ s: String) -> String {
    let scalars = s.unicodeScalars
    var idx = scalars.endIndex
    while idx > scalars.startIndex {
      let prev = scalars.index(before: idx)
      if !scalars[prev].properties.isWhitespace { break }
      idx = prev
    }
    return String(String.UnicodeScalarView(scalars[scalars.startIndex..<idx]))
  }

  // MARK: - Sanitize

  enum FtsUnit: Equatable {
    case word(String)
    case phrase([String])

    var isEmpty: Bool {
      switch self {
      case .word(let w): return w.isEmpty
      case .phrase(let ws): return ws.isEmpty || ws.allSatisfy(\.isEmpty)
      }
    }

    func write(into out: inout String, isLast: Bool) {
      switch self {
      case .word(let w):
        out.append("\"")
        out.append(w)
        out.append("\"")
      case .phrase(let words):
        out.append("\"")
        var first = true
        for w in words {
          if !first { out.append(" ") }
          out.append(w)
          first = false
        }
        out.append("\"")
      }
      if isLast { out.append("*") }
    }
  }

  /// Clean a raw token fragment by stripping FTS5-syntactic and control
  /// characters and truncating to ``maxFtsTokenChars``.
  static func cleanToken(_ token: String) -> String {
    let bad: Set<Character> = ["\"", "*", "(", ")", ":", "^", "{", "}"]
    var out = ""
    var taken = 0
    for ch in token {
      if bad.contains(ch) { continue }
      if ch.unicodeScalars.first.map({ CharacterSet.controlCharacters.contains($0) }) ?? false {
        continue
      }
      out.append(ch)
      taken += 1
      if taken >= maxFtsTokenChars { break }
    }
    return out
  }

  /// Split a bare (unquoted) whitespace-delimited token into FTS units.
  static func splitBareToken(_ token: String) -> [FtsUnit] {
    let runs = splitAlnumRuns(token)
    if runs.count < 2 {
      return runs.map { FtsUnit.word(cleanToken($0)) }.filter { !$0.isEmpty }
    }
    let isIdentifierLike =
      token.unicodeScalars.contains(where: { $0 == "@" || $0 == "." })
      && !anyWhitespace(token)
    if isIdentifierLike {
      let cleaned = runs.map(cleanToken).filter { !$0.isEmpty }
      if cleaned.count >= 2 {
        return [.phrase(cleaned)]
      } else if cleaned.count == 1 {
        return [.word(cleaned[0])]
      }
      return []
    }
    return runs.map { FtsUnit.word(cleanToken($0)) }.filter { !$0.isEmpty }
  }

  /// Split a string on every non-alphanumeric scalar, dropping empty runs.
  static func splitAlnumRuns(_ s: String) -> [String] {
    var runs: [String] = []
    var current = String.UnicodeScalarView()
    for scalar in s.unicodeScalars {
      if isUnicodeAlphanumeric(scalar) {
        current.append(scalar)
      } else {
        if !current.isEmpty {
          runs.append(String(current))
          current.removeAll(keepingCapacity: true)
        }
      }
    }
    if !current.isEmpty { runs.append(String(current)) }
    return runs
  }

  enum Segment {
    case bare(String)
    case quoted(String)
  }

  static func splitSegments(_ input: String) -> [Segment] {
    var segments: [Segment] = []
    var rest = Substring(input)
    while true {
      // Skip leading whitespace.
      while let f = rest.first, f.isWhitespace {
        rest = rest.dropFirst()
      }
      if rest.isEmpty { break }
      if rest.first == "\"" {
        rest = rest.dropFirst()
        if let qIdx = rest.firstIndex(of: "\"") {
          let inside = rest[..<qIdx]
          segments.append(.quoted(String(inside)))
          rest = rest[rest.index(after: qIdx)...]
        } else {
          segments.append(.quoted(String(rest)))
          rest = Substring()
        }
      } else {
        // Bare: take up to whitespace or `"`.
        var endIdx = rest.startIndex
        while endIdx < rest.endIndex {
          let c = rest[endIdx]
          if c.isWhitespace || c == "\"" { break }
          endIdx = rest.index(after: endIdx)
        }
        let bare = rest[..<endIdx]
        if !bare.isEmpty {
          segments.append(.bare(String(bare)))
        }
        rest = rest[endIdx...]
      }
    }
    return segments
  }

  /// Sanitize a user query for FTS5 MATCH syntax.
  ///
  /// Splits the input into whitespace-separated tokens and wraps each as a
  /// literal phrase. Tokens are implicitly ANDed by FTS5 when separated by
  /// spaces. `"..."` quoted spans become a single phrase (preserving
  /// ordered intent). Identifier-like tokens (`@` or `.` joining alnum
  /// runs) become ordered phrases. The final unit gets a `*` prefix
  /// wildcard so live-typed search hits as-you-type.
  public static func sanitizeFtsQuery(_ input: String) -> String {
    let capped = capFtsQueryLength(input)

    var units: [FtsUnit] = []
    for segment in splitSegments(capped) {
      if units.count >= maxFtsTokens { break }
      switch segment {
      case .quoted(let raw):
        let words = splitAlnumRuns(raw).map(cleanToken).filter { !$0.isEmpty }
        switch words.count {
        case 0: break
        case 1: units.append(.word(words[0]))
        default: units.append(.phrase(words))
        }
      case .bare(let raw):
        for unit in splitBareToken(raw) {
          if unit.isEmpty { continue }
          units.append(unit)
          if units.count >= maxFtsTokens { break }
        }
      }
    }

    if units.isEmpty { return "" }
    if units.count > maxFtsTokens {
      units = Array(units.prefix(maxFtsTokens))
    }

    var out = ""
    out.reserveCapacity(capped.utf8.count + 8)
    let last = units.count - 1
    for (i, unit) in units.enumerated() {
      if i > 0 { out.append(" ") }
      unit.write(into: &out, isLast: i == last)
    }
    return out
  }
}
