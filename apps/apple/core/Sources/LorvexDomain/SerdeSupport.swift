import Foundation

/// Shared serde-style helpers for cross-language SQLite value handling.
public enum SerdeSupport {
  /// Convert a SQLite REAL (`Double`) to a ``JSONValue``, preserving NaN /
  /// ±Infinity as canonical sentinel strings.
  ///
  /// `JSONValue.number` represents finite floats only; serde-equivalent
  /// behavior encodes non-finite values as `"NaN"` / `"Infinity"` /
  /// `"-Infinity"` so peers reading the wire form see the same sentinel
  /// the local row stored, rather than the silently-coerced `null` an
  /// earlier path used.
  public static func sqliteRealToJson(_ value: Double) -> JSONValue {
    if value.isFinite {
      return .double(value)
    }
    if value.isNaN {
      return .string("NaN")
    }
    return .string(value > 0 ? "Infinity" : "-Infinity")
  }
}
