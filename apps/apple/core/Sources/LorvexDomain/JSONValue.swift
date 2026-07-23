/// A JSON value preserving the integer/unsigned/float distinction that
/// canonical serialization depends on.
///
/// This is the in-process JSON representation used across the domain — notably
/// as the input to ``canonicalizeJSON(_:)``, whose byte output is a stable wire
/// contract.
///
/// Numbers are split into `.int` / `.uint` / `.double` so canonicalization can
/// reproduce the canonical number formatting exactly: integers render with
/// no decimal point, and the signedness follows how a literal is parsed
/// (non-negative integers that fit `UInt64` but not `Int64` stay `.uint`).
public enum JSONValue: Sendable, Equatable {
  case null
  case bool(Bool)
  case int(Int64)
  case uint(UInt64)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
}

extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) { self = .int(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
  }
}
