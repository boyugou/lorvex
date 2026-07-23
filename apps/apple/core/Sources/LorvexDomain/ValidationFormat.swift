/// Format-shape validators: calendar date range, user/calendar URL
/// allowlists, and CSS hex colors.
///
/// `validateDateFormat` and `validateTimeFormat` are thin wrappers over the
/// ISO-date / `HH:MM` parsers (``IsoDate/parseIsoDate(_:)`` and
/// ``Parsing/parseHhmmToMinutes(_:)``), so the validators and the parsers share
/// one definition of well-formed.
public enum ValidationFormat {
  /// Validate a date string: must be `YYYY-MM-DD` and a real calendar date.
  /// Thin wrapper over ``IsoDate/parseIsoDate(_:)`` for callers that only care
  /// about validity, not the parsed value.
  public static func validateDateFormat(_ s: String) -> Result<Void, ValidationError> {
    IsoDate.parseIsoDate(s).map { _ in () }
  }

  /// Validate a time string: must be `HH:MM` with hours 00-23 and minutes
  /// 00-59. Any input ``Parsing/parseHhmmToMinutes(_:)`` accepts is valid.
  public static func validateTimeFormat(_ s: String) -> Result<Void, ValidationError> {
    if Parsing.parseHhmmToMinutes(s) != nil {
      return .success(())
    }
    return .failure(.invalidFormat(field: "time", expected: "HH:MM (00:00-23:59)", actual: s))
  }

  /// Validate that an optional calendar `endDate` does not precede
  /// `startDate`. Both inputs are expected to be `YYYY-MM-DD` strings; lexical
  /// order on that canonical shape coincides with calendar order.
  ///
  /// Returns `nil` if `endDate` is absent, otherwise the `endDate` string.
  public static func validateCalendarDateRange(
    startDate: String, endDate: String?
  ) -> Result<String?, ValidationError> {
    guard let end = endDate else {
      return .success(nil)
    }
    if end < startDate {
      return .failure(
        .invalidFormat(
          field: "end_date",
          expected: "end_date must be on or after start_date",
          actual: "end_date=\(end), start_date=\(startDate)"))
    }
    return .success(end)
  }

  /// Per-validator message bundle for ``validateURLWithSchemeAllowlist``.
  struct URLMessages {
    let emptyExpected: String
    let schemeExpected: String
    let controlExpected: String
    let whitespaceExpected: String
  }

  /// Lowercase only ASCII bytes of `s`, leaving non-ASCII scalars untouched.
  /// The scheme allowlist matches on this form, so a Unicode-aware lowercasing
  /// would change codepoints.
  static func asciiLowercased(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.map { scalar in
      if scalar.value >= 0x41 && scalar.value <= 0x5A {
        return Unicode.Scalar(scalar.value + 0x20)!
      }
      return scalar
    }))
  }

  /// Lowercase only the scheme portion of a URL (everything before the first
  /// `:`), ASCII-only. Authority/path/query stay untouched (case-sensitive
  /// under RFC 3986). No colon → value returned verbatim.
  static func lowercaseURLScheme(_ s: String) -> String {
    let scalars = Array(s.unicodeScalars)
    guard let colonIdx = scalars.firstIndex(where: { $0 == ":" }) else {
      return s
    }
    let scheme = scalars[..<colonIdx]
    if scheme.allSatisfy({ !($0.value >= 0x41 && $0.value <= 0x5A) }) {
      return s
    }
    var out = String.UnicodeScalarView()
    for scalar in scheme {
      if scalar.value >= 0x41 && scalar.value <= 0x5A {
        out.append(Unicode.Scalar(scalar.value + 0x20)!)
      } else {
        out.append(scalar)
      }
    }
    out.append(contentsOf: scalars[colonIdx...])
    return String(out)
  }

  /// Shared body for ``validateUserURL(_:)`` and ``validateCalendarURL(_:)``.
  /// Walks: sanitize → trim → empty-check → scheme-allowlist → control chars →
  /// whitespace → lowercase-scheme. Returns the sanitized + trimmed canonical
  /// form so callers persist that, not the raw input.
  static func validateURLWithSchemeAllowlist(
    _ s: String, allowedPrefixes: [String], msgs: URLMessages
  ) -> Result<String, ValidationError> {
    let cleaned = UnicodeHygiene.sanitizeUserText(s)
    let trimmed = trimWhitespace(cleaned)
    if trimmed.isEmpty {
      return .failure(.invalidFormat(field: "url", expected: msgs.emptyExpected, actual: s))
    }
    let lowered = asciiLowercased(trimmed)
    if !allowedPrefixes.contains(where: { lowered.hasPrefix($0) }) {
      return .failure(.invalidFormat(field: "url", expected: msgs.schemeExpected, actual: s))
    }
    if trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
      return .failure(.invalidFormat(field: "url", expected: msgs.controlExpected, actual: s))
    }
    if trimmed.unicodeScalars.contains(where: { $0.properties.isWhitespace }) {
      return .failure(.invalidFormat(field: "url", expected: msgs.whitespaceExpected, actual: s))
    }
    return .success(lowercaseURLScheme(trimmed))
  }

  /// Trim leading/trailing Unicode whitespace scalars, using the Unicode
  /// `White_Space` property.
  static func trimWhitespace(_ s: String) -> String {
    let scalars = Array(s.unicodeScalars)
    var lo = 0
    var hi = scalars.count
    while lo < hi && scalars[lo].properties.isWhitespace { lo += 1 }
    while hi > lo && scalars[hi - 1].properties.isWhitespace { hi -= 1 }
    return String(String.UnicodeScalarView(scalars[lo..<hi]))
  }

  /// Validate a general-purpose user-pasted link. Accepts `http`, `https`,
  /// `mailto`, and `tel` schemes. Returns the sanitized + trimmed canonical
  /// form. Plain `http://` is intentionally accepted here; the stricter
  /// https-preferring calendar policy lives in ``validateCalendarURL(_:)``.
  public static func validateUserURL(_ s: String) -> Result<String, ValidationError> {
    let allowed = ["http://", "https://", "mailto:", "tel:"]
    let msgs = URLMessages(
      emptyExpected: "non-empty URL with http://, https://, mailto:, or tel: scheme",
      schemeExpected: "scheme must be http, https, mailto, or tel",
      controlExpected: "URL must not contain control characters",
      whitespaceExpected: "URL must not contain whitespace; encode spaces as %20")
    return validateURLWithSchemeAllowlist(s, allowedPrefixes: allowed, msgs: msgs)
  }

  /// Validate a calendar-subscription / calendar-event URL. Accepts only
  /// `http`, `https`, and `webcal` schemes; rejects `javascript:`, `data:`,
  /// `file:`, and every other scheme. Returns the sanitized + trimmed
  /// canonical form.
  public static func validateCalendarURL(_ s: String) -> Result<String, ValidationError> {
    let allowed = ["http://", "https://", "webcal://"]
    let msgs = URLMessages(
      emptyExpected: "non-empty calendar URL with http://, https://, or webcal:// scheme",
      schemeExpected: "calendar URL scheme must be http, https, or webcal",
      controlExpected: "calendar URL must not contain control characters",
      whitespaceExpected: "calendar URL must not contain whitespace; encode spaces as %20")
    return validateURLWithSchemeAllowlist(s, allowedPrefixes: allowed, msgs: msgs)
  }

  /// Validate a CSS-style hex color: `#RGB` (3 hex digits) or `#RRGGBB`
  /// (6 hex digits), reported under the `hex_color` field.
  public static func validateHexColor(_ s: String) -> Result<Void, ValidationError> {
    validateHexColorField(s, field: "hex_color")
  }

  /// Validate a CSS-style hex color under a caller-supplied field label.
  /// Length is measured in UTF-8 bytes.
  public static func validateHexColorField(
    _ s: String, field: String
  ) -> Result<Void, ValidationError> {
    let bytes = Array(s.utf8)
    let valid =
      (bytes.count == 4 || bytes.count == 7)
      && bytes.first == 0x23  // '#'
      && bytes.dropFirst().allSatisfy { isASCIIHexDigit($0) }
    if valid {
      return .success(())
    }
    return .failure(.invalidFormat(field: field, expected: "#RGB or #RRGGBB", actual: s))
  }

  static func isASCIIHexDigit(_ b: UInt8) -> Bool {
    (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66)
  }
}
