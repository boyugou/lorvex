/// Text-field validators (title, body, tag name).
///
/// All length checks count Unicode codepoints (scalars), so the domain layer
/// agrees with every other write boundary.
public enum ValidationText {
  /// Returns `true` when `s` contains nothing but invisible/strippable
  /// codepoints (zero-width joiners, bidi marks, BOM, control chars excluding
  /// the legitimate `\t \n \r`) plus whitespace.
  ///
  /// Treating "post-sanitize empty" as empty closes a gap that bare trimming
  /// leaves: trimming does not remove zero-width codepoints, so a title that
  /// reads as empty in the UI (nothing but ZWS / BOM / RLO padding) would pass
  /// a bare non-empty check.
  public static func isVisuallyEmpty(_ s: String) -> Bool {
    s.unicodeScalars.allSatisfy { c in
      c.properties.isWhitespace || UnicodeHygiene.isDisallowedCodepoint(c)
    }
  }

  /// Single-pass `(visuallyEmpty, scalarCount)` measurement, folding the
  /// visibility predicate and the codepoint count into one walk.
  static func measureVisibilityAndLength(_ s: String) -> (visuallyEmpty: Bool, count: Int) {
    var visuallyEmpty = true
    var count = 0
    for c in s.unicodeScalars {
      count += 1
      if !(c.properties.isWhitespace || UnicodeHygiene.isDisallowedCodepoint(c)) {
        visuallyEmpty = false
      }
    }
    return (visuallyEmpty, count)
  }

  /// Validate a task or list title: must be non-empty and within
  /// ``ValidationLimits/maxTitleLength`` Unicode codepoints. Also rejects
  /// titles that are visually empty after stripping zero-width / bidi /
  /// control codepoints.
  public static func validateTitle(_ title: String) -> Result<Void, ValidationError> {
    let m = measureVisibilityAndLength(title)
    if m.visuallyEmpty {
      return .failure(.empty("title"))
    }
    if m.count > ValidationLimits.maxTitleLength {
      return .failure(.tooLong(field: "title", max: ValidationLimits.maxTitleLength, actual: m.count))
    }
    return .success(())
  }

  /// Validate a task body: empty bodies are accepted (a body is optional) but
  /// a non-empty body that contains nothing visible after stripping zero-width
  /// / bidi / control codepoints is rejected as `empty("body")`. Beyond the
  /// codepoint cap, the body is also bounded by
  /// ``PayloadByteBudget/longTextEscapedBytes`` canonical-escaped bytes — this
  /// validator is shared by the sync applier for `body` / `ai_notes` /
  /// `raw_input`, and the long-text budget is the loosest of those writers'
  /// budgets, so every writer-legal value passes inbound.
  public static func validateBody(_ body: String) -> Result<Void, ValidationError> {
    if body.isEmpty {
      return .success(())
    }
    let m = measureVisibilityAndLength(body)
    if m.count > ValidationLimits.maxBodyLength {
      return .failure(.tooLong(field: "body", max: ValidationLimits.maxBodyLength, actual: m.count))
    }
    if m.visuallyEmpty {
      return .failure(.empty("body"))
    }
    if case .failure(let e) = PayloadByteBudget.validateEscapedBudget(
      body, field: "body", budget: PayloadByteBudget.longTextEscapedBytes)
    {
      return .failure(e)
    }
    return .success(())
  }

  /// Validate that an arbitrary string field does not exceed `max` Unicode
  /// codepoints, returning ``ValidationError/tooLong(field:max:actual:)`` on
  /// overflow.
  public static func validateStringLength(
    _ value: String, field: String, max: Int
  ) -> Result<Void, ValidationError> {
    let count = value.unicodeScalars.count
    if count > max {
      return .failure(.tooLong(field: field, max: max, actual: count))
    }
    return .success(())
  }

  /// Validate that an optional string field, if present, does not exceed `max`
  /// Unicode codepoints.
  public static func validateOptionalStringLength(
    _ value: String?, field: String, max: Int
  ) -> Result<Void, ValidationError> {
    if let v = value {
      return validateStringLength(v, field: field, max: max)
    }
    return .success(())
  }

  /// Validate a tag display name: must be non-empty and within
  /// ``ValidationLimits/maxTagNameLength`` Unicode codepoints. Also rejects
  /// names that are visually empty after stripping invisible codepoints.
  public static func validateTagName(_ name: String) -> Result<Void, ValidationError> {
    let m = measureVisibilityAndLength(name)
    if m.visuallyEmpty {
      return .failure(.empty("tag_name"))
    }
    if m.count > ValidationLimits.maxTagNameLength {
      return .failure(
        .tooLong(field: "tag_name", max: ValidationLimits.maxTagNameLength, actual: m.count))
    }
    return .success(())
  }
}
