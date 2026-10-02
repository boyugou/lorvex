import Foundation
import LorvexDomain
import MCP

/// Prepares a tool call's arguments against the tool's declared input schema
/// before any handler or the idempotency checksum sees them. The dispatcher
/// runs it once per call, so every tool gets both passes without opting in.
///
/// **Fence tokens.** Read tools wrap user text in ⟦user⟧…⟦/user⟧ (see
/// ``SecurityFencing``). A client that copies a fenced title, tag, or memory
/// key into a later call means the bare text, so every string in the argument
/// tree loses the whole `⟦user⟧` and `⟦/user⟧` tokens wherever they appear.
/// A lone ⟦ or ⟧ is kept: it is legitimate text (Scott brackets in a note),
/// and responses strip lone sentinels themselves, so a stored one can never
/// forge a fence boundary.
///
/// **Enums.** A value at a property whose schema declares `enum`, directly or
/// as an array's `items`, must be one of the declared values. A string matches
/// case-insensitively after trimming and is rewritten to the declared
/// spelling; an integer matches by value. Any other pairing (a string for an
/// integer enum, a fractional number, a boolean) is left for the handler,
/// whose strict parsing reports the type error or accepts a documented alias
/// such as "P1" for priority 1. Nested objects, including the objects inside
/// an array of batch items, are checked the same way. A mismatch throws
/// ``ValidationError/notOneOf(field:allowed:actual:)`` naming the argument's
/// path (`tasks[2].priority`) and every allowed value, so a client
/// that asks for `status: "done"` learns the vocabulary instead of silently
/// receiving a default.
enum ToolArgumentNormalization {
  static func normalize(_ arguments: [String: Value], schema: Value) throws -> [String: Value] {
    try normalizeObject(arguments, schema: schema, path: "")
  }

  /// `text` without any ⟦user⟧ or ⟦/user⟧ fence token.
  static func stripFenceTokens(_ text: String) -> String {
    guard text.contains(SecurityFencing.openSentinel) else { return text }
    return text.replacingOccurrences(of: openToken, with: "")
      .replacingOccurrences(of: closeToken, with: "")
  }

  private static let openToken =
    "\(SecurityFencing.openSentinel)user\(SecurityFencing.closeSentinel)"
  private static let closeToken =
    "\(SecurityFencing.openSentinel)/user\(SecurityFencing.closeSentinel)"

  private static func normalizeObject(
    _ object: [String: Value], schema: Value?, path: String
  ) throws -> [String: Value] {
    let properties = schema?.objectValue?["properties"]?.objectValue ?? [:]
    var result: [String: Value] = [:]
    for (key, value) in object {
      result[key] = try normalize(
        value, schema: properties[key], path: path.isEmpty ? key : "\(path).\(key)")
    }
    return result
  }

  private static func normalize(_ value: Value, schema: Value?, path: String) throws -> Value {
    let allowed = schema?.objectValue?["enum"]?.arrayValue
    switch value {
    case .string(let text):
      let bare = stripFenceTokens(text)
      guard let allowed else { return .string(bare) }
      return try matchString(bare, allowed: allowed.compactMap(\.stringValue), path: path)
    case .int(let number):
      guard let allowed else { return value }
      return try matchInteger(number, allowed: allowed.compactMap(\.intValue), path: path)
    case .array(let elements):
      let items = schema?.objectValue?["items"]
      return .array(
        try elements.enumerated().map { index, element in
          try normalize(element, schema: items, path: "\(path)[\(index)]")
        })
    case .object(let object):
      return .object(try normalizeObject(object, schema: schema, path: path))
    case .null, .bool, .double, .data:
      return value
    }
  }

  /// A string against a string enum: the declared spelling of the case-
  /// insensitive match. An enum with no string values leaves the string for
  /// the handler.
  private static func matchString(_ text: String, allowed: [String], path: String) throws -> Value {
    guard !allowed.isEmpty else { return .string(text) }
    let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let match = allowed.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
      return .string(match)
    }
    throw mismatch(path: path, actual: text, allowed: allowed)
  }

  /// An integer against an integer enum. An enum with no integer values leaves
  /// the integer for the handler.
  private static func matchInteger(_ number: Int, allowed: [Int], path: String) throws -> Value {
    guard !allowed.isEmpty, !allowed.contains(number) else { return .int(number) }
    throw mismatch(path: path, actual: String(number), allowed: allowed.map(String.init))
  }

  private static func mismatch(path: String, actual: String, allowed: [String]) -> ValidationError {
    .notOneOf(field: path, allowed: allowed, actual: actual)
  }
}
