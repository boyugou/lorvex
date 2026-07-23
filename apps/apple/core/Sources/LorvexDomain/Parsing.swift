import Foundation

/// Small string parsers shared across the domain layer.
///
/// A self-contained subset of the domain's string parsing: the canonical
/// JSON-string preference parser, the `HH:MM` ↔ minute-of-day pair, and the SQL
/// `LIKE` escaper. Preference-state helpers such as the sync-backend preference
/// parser and HLC cursor projection live with the runtime/sync surfaces that
/// consume them, not in this domain parser subset.
public enum Parsing {
  /// Parse a canonical JSON string preference value.
  ///
  /// Returns `nil` when the input is missing, blank, malformed, or not a JSON
  /// string. The raw payload must decode as a JSON string; its trimmed inner value
  /// must then NOT itself decode as a JSON string (so a doubly-quoted
  /// `"\"foo\""` layer is rejected).
  public static func parseJsonStringPreference(_ raw: String?) -> String? {
    guard let raw = raw else { return nil }
    guard let parsed = decodeJsonString(raw) else { return nil }
    let trimmed = ValidationFormat.trimWhitespace(parsed)
    // Reject a nested JSON-string layer: if the trimmed value still decodes as a
    // JSON string, the caller passed a doubly-encoded value.
    if decodeJsonString(trimmed) != nil {
      return nil
    }
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Decode `raw` as a single JSON string scalar, returning the unescaped value.
  /// Returns `nil` for any non-string JSON or invalid JSON.
  static func decodeJsonString(_ raw: String) -> String? {
    guard let data = raw.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    // `JSONDecoder` requires a fragment-allowing top level; `String` is a fragment.
    return try? decoder.decode(String.self, from: data)
  }

  /// Parse an `HH:MM` string into minute-of-day (0–1439). Returns `nil` if the
  /// format is invalid or out of range.
  ///
  /// Requires both halves to be exactly two ASCII digits before parsing, so signs,
  /// whitespace, and non-ASCII digits all reject up front: a bare length check
  /// plus integer parse would accept `+9:00` / `-1:30` and break round-trip.
  public static func parseHhmmToMinutes(_ value: String) -> Int64? {
    let bytes = Array(value.utf8)
    guard bytes.count == 5, bytes[2] == UInt8(ascii: ":") else { return nil }
    for i in [0, 1, 3, 4] where !isAsciiDigit(bytes[i]) {
      return nil
    }
    let hour = Int64(bytes[0] - 0x30) * 10 + Int64(bytes[1] - 0x30)
    let minute = Int64(bytes[3] - 0x30) * 10 + Int64(bytes[4] - 0x30)
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    return hour * 60 + minute
  }

  /// Format a minute-of-day integer (0–1439) as `HH:MM`. Returns `nil` if `value`
  /// is outside `0..<1440`.
  public static func formatMinutesHhmm(_ value: Int64) -> String? {
    guard (0..<1440).contains(value) else { return nil }
    return String(format: "%02d:%02d", value / 60, value % 60)
  }

  /// Escape LIKE wildcards (`%`, `_`, `\`) so a literal substring match is
  /// performed when using `LIKE ? ESCAPE '\'`.
  public static func escapeLike(_ input: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(input.count)
    for ch in input {
      if ch == "%" || ch == "_" || ch == "\\" {
        escaped.append("\\")
      }
      escaped.append(ch)
    }
    return escaped
  }

  static func isAsciiDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
}
