import LorvexDomain
import MCP

/// Strict scalar decoding for tool arguments on state-changing paths.
///
/// JSON Schema is advisory at the MCP boundary; runtime parsing must reject a
/// request whose meaning would otherwise change. A PRESENT argument of the
/// wrong type therefore throws ``ValidationError/invalidFormat`` naming the
/// parameter — it is never treated as absent, because every absent-argument
/// default (`?? today`, `?? 1`, `?? false`) would silently apply a DIFFERENT
/// value than the caller sent. Absent keys and JSON `null` keep their
/// documented defaults. The strict set is every state-changing argument plus
/// read-path ENTITY SELECTORS (a wrong-typed `read_memory` key silently
/// ignored would return the whole store instead of the requested entry);
/// read-path range filters and `limit`/`offset` clamps follow the same rule: a
/// missing value may default, but a present value of the wrong type is always a
/// validation error. This keeps every JSON scalar faithful to client intent.
///
/// Integer decoding accepts exactly what the SDK's `Value.intValue` accepts
/// (a JSON integer; fractional doubles and numeric strings are rejected),
/// matching the recurrence wire contract's established choice.
enum StrictScalarArguments {
  /// Absent/null → nil; string → the string; anything else throws.
  static func optionalString(_ value: Value?, field: String) throws -> String? {
    guard let value, !value.isNull else { return nil }
    guard let string = value.stringValue else {
      throw ValidationError.invalidFormat(
        field: field, expected: "a string", actual: StrictArgumentArray.describe(value))
    }
    return string
  }

  /// Absent/null → nil; integer → the integer; anything else throws.
  static func optionalInt(_ value: Value?, field: String) throws -> Int? {
    guard let value, !value.isNull else { return nil }
    guard let int = value.intValue else {
      throw ValidationError.invalidFormat(
        field: field, expected: "an integer", actual: StrictArgumentArray.describe(value))
    }
    return int
  }

  /// Absent/null → nil; boolean → the boolean; anything else throws.
  static func optionalBool(_ value: Value?, field: String) throws -> Bool? {
    guard let value, !value.isNull else { return nil }
    guard let bool = value.boolValue else {
      throw ValidationError.invalidFormat(
        field: field, expected: "a boolean", actual: StrictArgumentArray.describe(value))
    }
    return bool
  }

  /// Boolean with an absent-key default: `optionalBool` then `?? defaultValue`.
  static func bool(_ value: Value?, field: String, default defaultValue: Bool) throws -> Bool {
    try optionalBool(value, field: field) ?? defaultValue
  }

  /// Integer with an absent-key default: `optionalInt` then `?? defaultValue`.
  static func int(_ value: Value?, field: String, default defaultValue: Int) throws -> Int {
    try optionalInt(value, field: field) ?? defaultValue
  }

  /// String with an absent-key default computed lazily (the write-path
  /// `date ?? today` idiom): a present wrong-typed value throws instead of
  /// silently targeting the default date.
  static func string(
    _ value: Value?, field: String, default defaultValue: @autoclosure () -> String
  ) throws -> String {
    try optionalString(value, field: field) ?? defaultValue()
  }
}
