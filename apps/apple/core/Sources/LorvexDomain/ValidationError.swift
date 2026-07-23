/// A single domain validation failure.
///
/// Domain-side validators return `Result<Void, ValidationError>` so caller
/// surfaces (the MCP host, platform surfaces, and sync apply) can format
/// domain-aware error messages without recreating the discriminant set. The
/// ``description`` strings are the wire wording surfaced to AI clients and
/// must stay byte-identical across surfaces.
public enum ValidationError: Error, Equatable, Sendable, CustomStringConvertible {
  /// A required string field is empty (or whitespace-only). The associated
  /// value is the field label.
  case empty(String)

  /// A string field exceeds its maximum length.
  ///
  /// `max` and `actual` are measured in Unicode codepoints for text-facing
  /// fields (titles, bodies, tag names, short-text strings). Byte-counted
  /// checks (SQL identifiers, raw JSON blobs) bypass this enum entirely.
  case tooLong(field: String, max: Int, actual: Int)

  /// A numeric field is outside its allowed inclusive range.
  case outOfRange(field: String, min: Int64, max: Int64, actual: Int64)

  /// A string field does not match the expected format.
  case invalidFormat(field: String, expected: String, actual: String)

  /// A free-form ad-hoc validation message without a structured discriminant.
  /// New code should prefer the structured variants whenever the
  /// field/limit/value are known.
  case message(String)

  public var description: String {
    switch self {
    case let .empty(field):
      return "\(field) must not be empty"
    case let .tooLong(field, max, actual):
      return "\(field) exceeds maximum length (\(actual) chars, limit \(max))"
    case let .outOfRange(field, min, max, actual):
      return "\(field) is out of range (\(actual), must be \(min)..=\(max))"
    case let .invalidFormat(field, expected, actual):
      return "\(field) has invalid format (got \"\(actual)\", expected \(expected))"
    case let .message(message):
      return message
    }
  }
}

extension ValidationError {
  /// An untyped string becomes a ``message`` carrier.
  public init(message: String) {
    self = .message(message)
  }
}
