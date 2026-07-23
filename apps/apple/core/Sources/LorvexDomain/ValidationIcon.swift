/// Validator for `icon` tokens on lists and habits.
///
/// An icon must be provably a machine token — an SF Symbol name or a single
/// emoji grapheme — never arbitrary free text. This closes a prompt-injection
/// vector: `icon` is returned UNFENCED in read-tool responses (it is a
/// system-controlled glyph identifier, not user prose), so accepting arbitrary
/// text there would let injected instructions cross the fence and, via sync,
/// the trust boundary between devices.
public enum ValidationIcon {

  /// Validate an already-trimmed, non-empty icon token.
  ///
  /// Accepted shapes:
  ///   * a single visible grapheme cluster (an emoji or a single glyph), or
  ///   * an SF Symbol name: 1…``ValidationLimits/maxIconLength`` codepoints,
  ///     each one of `A–Z`, `a–z`, `0–9`, or `.`.
  ///
  /// Any invisible / bidi / control codepoint (per
  /// ``UnicodeHygiene/isDisallowedCodepoint(_:)``) is rejected outright, so a
  /// crafted zero-width or bidi-override payload can never masquerade as an icon.
  public static func validateIconToken(
    _ value: String, field: String
  ) -> Result<Void, ValidationError> {
    let graphemeCount = value.count
    if graphemeCount == 0 {
      return .failure(.empty(field))
    }
    if value.unicodeScalars.contains(where: UnicodeHygiene.isDisallowedCodepoint) {
      return .failure(invalid(field, value))
    }
    // A single visible grapheme (emoji or lone glyph) is always a valid icon.
    if graphemeCount == 1 {
      return .success(())
    }
    // Multi-character icons must be SF-Symbol-shaped ASCII within the cap.
    if graphemeCount <= ValidationLimits.maxIconLength
      && value.unicodeScalars.allSatisfy(isSFSymbolScalar)
    {
      return .success(())
    }
    return .failure(invalid(field, value))
  }

  private static func invalid(_ field: String, _ value: String) -> ValidationError {
    .invalidFormat(
      field: field,
      expected:
        "an SF Symbol name ([A-Za-z0-9.], ≤\(ValidationLimits.maxIconLength) chars) or a single emoji",
      actual: value)
  }

  /// `A–Z`, `a–z`, `0–9`, or `.` — the SF Symbol name character set.
  private static func isSFSymbolScalar(_ s: Unicode.Scalar) -> Bool {
    let v = s.value
    return (v >= 0x30 && v <= 0x39)  // 0-9
      || (v >= 0x41 && v <= 0x5A)  // A-Z
      || (v >= 0x61 && v <= 0x7A)  // a-z
      || v == 0x2E  // .
  }
}
