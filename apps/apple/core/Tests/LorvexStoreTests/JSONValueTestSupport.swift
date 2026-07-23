import LorvexDomain

/// Ergonomic accessors used by the payload-loader / changelog tests to assert
/// over ``JSONValue`` trees the way the Rust tests index `serde_json::Value`.
extension JSONValue {
  /// Object-member access. Returns `.null` for a missing key or a non-object.
  subscript(_ key: String) -> JSONValue {
    if case .object(let obj) = self { return obj[key] ?? .null }
    return .null
  }

  /// `true` when the value is JSON `null`.
  var isNull: Bool {
    if case .null = self { return true }
    return false
  }

  /// `true` when the object has no member for `key` (distinct from a member
  /// whose value is `.null`). Mirrors Rust `value.get(key).is_none()`.
  func hasNoKey(_ key: String) -> Bool {
    if case .object(let obj) = self { return obj[key] == nil }
    return true
  }

  var asString: String? {
    if case .string(let s) = self { return s }
    return nil
  }

  var asInt: Int64? {
    if case .int(let i) = self { return i }
    if case .uint(let u) = self { return Int64(u) }
    return nil
  }

  var asBool: Bool? {
    if case .bool(let b) = self { return b }
    return nil
  }
}
