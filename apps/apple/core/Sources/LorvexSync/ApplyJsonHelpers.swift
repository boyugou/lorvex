import Foundation
import LorvexDomain

/// Shared JSON-payload extraction helpers for the apply pipeline.
///
/// Every helper returns through Swift `throws` of ``ApplyError/invalidPayload``
/// so callers funnel through one typed error variant. Empty-string-as-absent
/// semantics: a `""` value is
/// treated as absent in ``optionalStr(_:_:entity:)`` because older devices
/// serialize "unset" as `""` rather than omitting the field.
enum ApplyJSON {
  /// The object map for a payload value, or `nil` if it is not an object.
  static func object(_ value: JSONValue) -> [String: JSONValue]? {
    if case let .object(map) = value { return map }
    return nil
  }

  /// Parse a sync-envelope payload string into its top-level JSON object.
  /// Unparseable JSON and a non-object top-level value are the two shape errors
  /// every aggregate / child / edge apply path rejects with this same wording.
  static func parseObject(_ payload: String) throws -> [String: JSONValue] {
    guard let parsed = JSONValue.parse(payload) else {
      throw ApplyError.invalidPayload("malformed sync payload JSON")
    }
    guard let obj = object(parsed) else {
      throw ApplyError.invalidPayload("sync payload must be a JSON object")
    }
    return obj
  }

  /// Inner string when present and string-shaped; `nil` for missing key, JSON
  /// null, or non-string values.
  static func strField(_ obj: [String: JSONValue], _ key: String) -> String? {
    if case let .string(s)? = obj[key] { return s }
    return nil
  }

  static func requiredStr(_ obj: [String: JSONValue], _ key: String, entity: String) throws
    -> String
  {
    guard let s = strField(obj, key) else {
      throw ApplyError.invalidPayload("\(entity) payload: \(key) must be a string")
    }
    return s
  }

  /// Accepts absent, null, AND empty-string all as `nil`. Used where a column
  /// treats `""` as "unset" on both write and read paths.
  static func optionalStr(_ obj: [String: JSONValue], _ key: String, entity: String) throws
    -> String?
  {
    switch obj[key] {
    case .none, .null:
      return nil
    case let .string(s):
      return s.isEmpty ? nil : s
    default:
      throw ApplyError.invalidPayload("\(entity) payload: \(key) must be a string when present")
    }
  }

  /// JSON boolean stored in SQLite's integer-bool columns.
  static func requiredBoolAsInt64(_ obj: [String: JSONValue], _ key: String, entity: String)
    throws -> Int64
  {
    if case let .bool(b)? = obj[key] { return b ? 1 : 0 }
    throw ApplyError.invalidPayload("\(entity) payload: \(key) must be a boolean")
  }

  /// Optional JSON boolean for SQLite integer-bool columns. Missing / null keep
  /// the SQL column default (returns `nil`); a non-boolean present value errors.
  static func optionalBoolAsInt64(_ obj: [String: JSONValue], _ key: String, entity: String)
    throws -> Int64?
  {
    switch obj[key] {
    case .none, .null:
      return nil
    case let .bool(b):
      return b ? 1 : 0
    default:
      throw ApplyError.invalidPayload("\(entity) payload: \(key) must be a boolean when present")
    }
  }

  /// Required integer field.
  static func requiredInt64(_ obj: [String: JSONValue], _ key: String, entity: String) throws
    -> Int64
  {
    if case let .int(i)? = obj[key] { return i }
    throw ApplyError.invalidPayload("\(entity) payload: \(key) must be an integer")
  }

  /// Optional integer field. Absent / null → `nil`; non-integer present errors.
  static func optionalInt64(_ obj: [String: JSONValue], _ key: String, entity: String) throws
    -> Int64?
  {
    switch obj[key] {
    case .none, .null:
      return nil
    case let .int(i):
      return i
    default:
      throw ApplyError.invalidPayload("\(entity) payload: \(key) must be an integer when present")
    }
  }

  /// Optional JSON array of objects. Absent / null → `nil`; a non-array present
  /// value errors. Elements are returned as-is (the caller validates each one).
  static func optionalObjectArray(_ obj: [String: JSONValue], _ key: String, entity: String)
    throws -> [JSONValue]?
  {
    switch obj[key] {
    case .none, .null:
      return nil
    case let .array(items):
      return items
    default:
      throw ApplyError.invalidPayload("\(entity) payload: \(key) must be an array when present")
    }
  }
}
