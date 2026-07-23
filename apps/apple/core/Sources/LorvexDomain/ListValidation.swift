/// Input hygiene for list write fields, shared by every list write path
/// (create / update / import / set-ai-notes).
///
/// Free-text fields (`name`, `description`, `ai_notes`) are run through
/// ``UnicodeHygiene/sanitizeUserText(_:)`` (strip bidi / zero-width / control
/// codepoints, then NFC) and length-capped, matching the task/calendar write
/// paths. `color` and `icon` are validated as machine tokens (hex color / SF
/// Symbol name or single emoji) so they stay safe to return UNFENCED and to
/// replicate across the sync boundary.
public enum ListValidation {

  /// Sanitize and validate a required list name: non-empty after stripping
  /// invisibles, within ``ValidationLimits/maxTitleLength`` codepoints.
  public static func normalizeName(_ raw: String) throws -> String {
    let trimmed = UnicodeHygiene.sanitizeUserText(raw)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || ValidationText.isVisuallyEmpty(trimmed) {
      throw ValidationError.empty("name")
    }
    if case let .failure(e) = ValidationText.validateStringLength(
      trimmed, field: "name", max: ValidationLimits.maxTitleLength)
    {
      throw e
    }
    return trimmed
  }

  /// Sanitize and validate an optional free-text field (`description` /
  /// `ai_notes`). A value that is blank after stripping invisibles collapses to
  /// `nil` ("no value"); a non-blank value is capped at `max` codepoints and at
  /// `escapedBudget` canonical-escaped bytes (the field's share of the entity's
  /// sync-payload byte cap; see ``PayloadByteBudget``).
  public static func normalizeOptionalText(
    _ raw: String?, field: String, max: Int, escapedBudget: Int
  ) throws -> String? {
    guard let raw else { return nil }
    let trimmed = UnicodeHygiene.sanitizeUserText(raw)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    if case let .failure(e) = ValidationText.validateStringLength(
      trimmed, field: field, max: max)
    {
      throw e
    }
    if case let .failure(e) = PayloadByteBudget.validateEscapedBudget(
      trimmed, field: field, budget: escapedBudget)
    {
      throw e
    }
    return trimmed
  }

  /// Trim, drop-if-blank, and hex-validate an optional `color`. Returns the
  /// trimmed hex string or `nil`.
  public static func normalizeColor(_ raw: String?) throws -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else { return nil }
    if case let .failure(e) = ValidationFormat.validateHexColorField(trimmed, field: "color") {
      throw e
    }
    return trimmed
  }

  /// Trim, drop-if-blank, and token-validate an optional `icon` (SF Symbol name
  /// or single emoji). Returns the trimmed token or `nil`.
  public static func normalizeIcon(_ raw: String?) throws -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else { return nil }
    if case let .failure(e) = ValidationIcon.validateIconToken(trimmed, field: "icon") {
      throw e
    }
    return trimmed
  }
}
