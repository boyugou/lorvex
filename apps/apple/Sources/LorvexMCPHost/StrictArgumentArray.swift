import LorvexDomain
import MCP

/// Whole-or-nothing decoders for the typed-array arguments MCP tools accept —
/// task/list/habit id lists, tag lists, review link lists, status/level/source
/// filters, and field projections.
///
/// A JSON string array is decoded element-by-element; a wrong-typed or malformed
/// element REJECTS the whole call with a structured ``ValidationError`` instead
/// of being silently dropped. Dropping an element would apply a DIFFERENT set
/// than the caller sent — a missing id in a batch mutation, a lost tag on a
/// task, a filter that quietly matches a different set — and then report that
/// partial result as a full success. Rejecting surfaces the mismatch as a
/// `validation` tool error the caller can correct. Integer-array arguments
/// (recurrence `bymonth`/`bysetpos`, habit `weekdays`) carry domain-specific
/// range hints and keep their own bespoke strict decoders rather than routing
/// through here.
///
/// Emptiness is a caller concern, not a type error: an absent argument (missing
/// key or JSON `null`) decodes to `nil`, and an explicit empty array decodes to
/// `[]`. Callers that require a non-empty array enforce that after decoding, so
/// their own "at least one X is required" wording is preserved.
enum StrictArgumentArray {
  /// Decode an optional homogeneous `[String]`. Absent key or JSON `null` →
  /// `nil`; a JSON array of strings → the array; a non-array value or any
  /// non-string element throws ``ValidationError/invalidFormat``.
  static func optionalStrings(_ value: Value?, field: String) throws -> [String]? {
    guard let value, !value.isNull else { return nil }
    guard case .array(let elements) = value else {
      throw ValidationError.invalidFormat(
        field: field, expected: "an array of strings", actual: describe(value))
    }
    return try elements.enumerated().map { index, element in
      guard let string = element.stringValue else {
        throw ValidationError.invalidFormat(
          field: "\(field)[\(index)]", expected: "a string", actual: describe(element))
      }
      return string
    }
  }

  /// Decode a homogeneous `[String]`, defaulting an absent key or JSON `null` to
  /// `[]`. Wrong-typed input still throws (see ``optionalStrings(_:field:)``), so
  /// a required-non-empty caller's own emptiness check runs against a faithfully
  /// decoded array rather than a silently pruned one.
  static func requiredStrings(_ value: Value?, field: String) throws -> [String] {
    try optionalStrings(value, field: field) ?? []
  }

  /// Decode a string array and reject duplicate identities before a batch write.
  /// A repeated entity id is never a second intent: depending on the operation
  /// it could otherwise be written twice, appear once as changed and once as
  /// skipped, or let two conflicting patches race by input order. Rejecting the
  /// whole request gives every batch one deterministic meaning.
  static func requiredUniqueStrings(_ value: Value?, field: String) throws -> [String] {
    let values = try requiredStrings(value, field: field)
    try requireUnique(values, field: field)
    return values
  }

  static func requireUnique(_ values: [String], field: String) throws {
    var seen = Set<String>()
    for (index, value) in values.enumerated() where !seen.insert(value).inserted {
      throw ValidationError.invalidFormat(
        field: "\(field)[\(index)]",
        expected: "a unique entity id",
        actual: "duplicate \"\(value)\"")
    }
  }

  /// Render a wrong-typed argument value for a ``ValidationError`` `actual`
  /// field: strings quoted, scalars bare, containers and `null` named. Accessor-
  /// based (not case-based) to stay robust to the `Value` enum's exact cases,
  /// matching the quoting style the task-patch validators use.
  static func describe(_ value: Value) -> String {
    if value.isNull { return "null" }
    if let string = value.stringValue { return "\"\(string)\"" }
    if let int = value.intValue { return String(int) }
    if let double = value.doubleValue { return String(double) }
    if let bool = value.boolValue { return String(bool) }
    if value.arrayValue != nil { return "an array" }
    if value.objectValue != nil { return "an object" }
    return "an unsupported value"
  }
}
