/// Strict JSON parser producing a ``JSONValue``, used where the domain needs
/// type-preserving JSON semantics — notably the recurrence normalizer, which
/// branches on the integer-vs-float distinction (a number written with a decimal
/// point or exponent, even `2.0`, is never treated as an integer).
///
/// This is a self-contained recursive-descent parser rather than a wrapper over
/// `Foundation.JSONSerialization`: `NSNumber` erases whether a literal was an
/// integer or a float, so it cannot preserve that distinction. The
/// parser tracks each number literal's syntax and emits ``JSONValue/int(_:)`` /
/// ``JSONValue/uint(_:)`` only for integer literals that fit the signed/unsigned
/// 64-bit range, ``JSONValue/double(_:)`` otherwise.
///
/// Duplicate object keys resolve last-wins.
extension JSONValue {
  /// Parse a JSON document, returning `nil` on any syntax error or trailing
  /// non-whitespace input.
  ///
  /// Also rejects (returns `nil`), keeping the parser's accepted set aligned
  /// with ``canonicalizeJSON(_:)``'s emittable set:
  /// - Input nested at or beyond ``maxJSONDepth`` (the writer's cap): matching
  ///   the writer bounds the recursion so hostile deeply-nested input fails
  ///   deterministically instead of overflowing the stack.
  /// - A numeric literal that overflows `Double` to a non-finite value
  ///   (e.g. `1e999`), which has no valid JSON form and which serde_json also
  ///   rejects.
  public static func parse(_ s: String) -> JSONValue? {
    var parser = JSONParser(Array(s.utf8))
    parser.skipWhitespace()
    guard let value = parser.parseValue(depth: 0) else { return nil }
    parser.skipWhitespace()
    guard parser.atEnd else { return nil }
    return value
  }
}

private struct JSONParser {
  let bytes: [UInt8]
  var pos: Int = 0

  init(_ bytes: [UInt8]) { self.bytes = bytes }

  var atEnd: Bool { pos >= bytes.count }

  mutating func skipWhitespace() {
    while pos < bytes.count {
      let b = bytes[pos]
      if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
        pos += 1
      } else {
        break
      }
    }
  }

  /// Parse the value at nesting depth `depth` (the outermost value is depth 0).
  /// A value entered at `depth >= maxJSONDepth` is rejected, mirroring
  /// ``canonicalizeJSON(_:)``'s writer (which throws for the same depth) and
  /// bounding the mutual recursion so deeply-nested input cannot overflow the
  /// stack.
  mutating func parseValue(depth: Int) -> JSONValue? {
    guard depth < maxJSONDepth else { return nil }
    guard pos < bytes.count else { return nil }
    switch bytes[pos] {
    case UInt8(ascii: "{"): return parseObject(depth: depth)
    case UInt8(ascii: "["): return parseArray(depth: depth)
    case UInt8(ascii: "\""): return parseString().map { .string($0) }
    case UInt8(ascii: "t"), UInt8(ascii: "f"): return parseBool()
    case UInt8(ascii: "n"): return parseNull()
    case UInt8(ascii: "-"), 0x30...0x39: return parseNumber()
    default: return nil
    }
  }

  mutating func expect(_ b: UInt8) -> Bool {
    guard pos < bytes.count, bytes[pos] == b else { return false }
    pos += 1
    return true
  }

  mutating func parseObject(depth: Int) -> JSONValue? {
    guard expect(UInt8(ascii: "{")) else { return nil }
    var map: [String: JSONValue] = [:]
    skipWhitespace()
    if pos < bytes.count, bytes[pos] == UInt8(ascii: "}") {
      pos += 1
      return .object(map)
    }
    while true {
      skipWhitespace()
      guard pos < bytes.count, bytes[pos] == UInt8(ascii: "\"") else { return nil }
      guard let key = parseString() else { return nil }
      skipWhitespace()
      guard expect(UInt8(ascii: ":")) else { return nil }
      skipWhitespace()
      guard let value = parseValue(depth: depth + 1) else { return nil }
      map[key] = value  // last-wins on duplicate keys
      skipWhitespace()
      guard pos < bytes.count else { return nil }
      if bytes[pos] == UInt8(ascii: ",") {
        pos += 1
        continue
      }
      if bytes[pos] == UInt8(ascii: "}") {
        pos += 1
        return .object(map)
      }
      return nil
    }
  }

  mutating func parseArray(depth: Int) -> JSONValue? {
    guard expect(UInt8(ascii: "[")) else { return nil }
    var arr: [JSONValue] = []
    skipWhitespace()
    if pos < bytes.count, bytes[pos] == UInt8(ascii: "]") {
      pos += 1
      return .array(arr)
    }
    while true {
      skipWhitespace()
      guard let value = parseValue(depth: depth + 1) else { return nil }
      arr.append(value)
      skipWhitespace()
      guard pos < bytes.count else { return nil }
      if bytes[pos] == UInt8(ascii: ",") {
        pos += 1
        continue
      }
      if bytes[pos] == UInt8(ascii: "]") {
        pos += 1
        return .array(arr)
      }
      return nil
    }
  }

  mutating func parseBool() -> JSONValue? {
    if matchLiteral("true") { return .bool(true) }
    if matchLiteral("false") { return .bool(false) }
    return nil
  }

  mutating func parseNull() -> JSONValue? {
    if matchLiteral("null") { return .null }
    return nil
  }

  mutating func matchLiteral(_ literal: String) -> Bool {
    let lit = Array(literal.utf8)
    guard pos + lit.count <= bytes.count else { return false }
    for (i, b) in lit.enumerated() where bytes[pos + i] != b { return false }
    pos += lit.count
    return true
  }

  /// Parse a JSON string body (including the surrounding quotes), decoding the
  /// standard escapes and `\uXXXX` (with surrogate-pair combination).
  mutating func parseString() -> String? {
    guard expect(UInt8(ascii: "\"")) else { return nil }
    var scalars = String.UnicodeScalarView()
    while pos < bytes.count {
      let b = bytes[pos]
      if b == UInt8(ascii: "\"") {
        pos += 1
        return String(scalars)
      }
      if b == UInt8(ascii: "\\") {
        pos += 1
        guard pos < bytes.count else { return nil }
        let esc = bytes[pos]
        pos += 1
        switch esc {
        case UInt8(ascii: "\""): scalars.append("\"")
        case UInt8(ascii: "\\"): scalars.append("\\")
        case UInt8(ascii: "/"): scalars.append("/")
        case UInt8(ascii: "b"): scalars.append(Unicode.Scalar(0x08))
        case UInt8(ascii: "f"): scalars.append(Unicode.Scalar(0x0C))
        case UInt8(ascii: "n"): scalars.append("\n")
        case UInt8(ascii: "r"): scalars.append("\r")
        case UInt8(ascii: "t"): scalars.append("\t")
        case UInt8(ascii: "u"):
          guard let scalar = parseUnicodeEscape() else { return nil }
          scalars.append(scalar)
        default:
          return nil
        }
      } else if b < 0x20 {
        // Unescaped control characters are invalid in JSON strings.
        return nil
      } else {
        // Collect a UTF-8 byte run up to the next quote/backslash/control and
        // decode it; preserves multi-byte scalars without per-byte assembly.
        let start = pos
        while pos < bytes.count {
          let cur = bytes[pos]
          if cur == UInt8(ascii: "\"") || cur == UInt8(ascii: "\\") || cur < 0x20 { break }
          pos += 1
        }
        guard let chunk = String(bytes: bytes[start..<pos], encoding: .utf8) else { return nil }
        scalars.append(contentsOf: chunk.unicodeScalars)
      }
    }
    return nil
  }

  /// Parse the four hex digits after a `\u`, combining a high+low surrogate pair
  /// into a single scalar. Returns `nil` for malformed escapes or a lone
  /// surrogate.
  mutating func parseUnicodeEscape() -> Unicode.Scalar? {
    guard let high = readHex4() else { return nil }
    if (0xD800...0xDBFF).contains(high) {
      guard pos + 1 < bytes.count, bytes[pos] == UInt8(ascii: "\\"),
        bytes[pos + 1] == UInt8(ascii: "u")
      else { return nil }
      pos += 2
      guard let low = readHex4(), (0xDC00...0xDFFF).contains(low) else { return nil }
      let combined = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
      return Unicode.Scalar(combined)
    }
    if (0xDC00...0xDFFF).contains(high) { return nil }
    return Unicode.Scalar(high)
  }

  mutating func readHex4() -> Int? {
    guard pos + 4 <= bytes.count else { return nil }
    var value = 0
    for _ in 0..<4 {
      guard let d = hexDigit(bytes[pos]) else { return nil }
      value = value * 16 + d
      pos += 1
    }
    return value
  }

  func hexDigit(_ b: UInt8) -> Int? {
    switch b {
    case 0x30...0x39: return Int(b - 0x30)
    case 0x41...0x46: return Int(b - 0x41 + 10)
    case 0x61...0x66: return Int(b - 0x61 + 10)
    default: return nil
    }
  }

  /// Parse a JSON number. Integer literals (no `.`, `e`, or `E`) that fit a
  /// signed 64-bit value emit ``JSONValue/int(_:)``; non-negative integers that
  /// overflow `Int64` but fit `UInt64` emit ``JSONValue/uint(_:)``; everything
  /// else (any fractional/exponent literal, or an out-of-range integer literal)
  /// emits ``JSONValue/double(_:)`` — a literal written with a decimal point or
  /// exponent is never treated as an integer.
  ///
  /// A literal that overflows `Double` to a non-finite value (e.g. `1e999`) is
  /// rejected (`nil`), matching serde_json; only a finite double is accepted.
  mutating func parseNumber() -> JSONValue? {
    let start = pos
    var isFloat = false
    if pos < bytes.count, bytes[pos] == UInt8(ascii: "-") { pos += 1 }
    // Integer part.
    guard pos < bytes.count, isDigit(bytes[pos]) else { return nil }
    if bytes[pos] == 0x30 {
      pos += 1  // leading zero — no further integer digits allowed
    } else {
      while pos < bytes.count, isDigit(bytes[pos]) { pos += 1 }
    }
    // Fraction.
    if pos < bytes.count, bytes[pos] == UInt8(ascii: ".") {
      isFloat = true
      pos += 1
      guard pos < bytes.count, isDigit(bytes[pos]) else { return nil }
      while pos < bytes.count, isDigit(bytes[pos]) { pos += 1 }
    }
    // Exponent.
    if pos < bytes.count, bytes[pos] == UInt8(ascii: "e") || bytes[pos] == UInt8(ascii: "E") {
      isFloat = true
      pos += 1
      if pos < bytes.count, bytes[pos] == UInt8(ascii: "+") || bytes[pos] == UInt8(ascii: "-") {
        pos += 1
      }
      guard pos < bytes.count, isDigit(bytes[pos]) else { return nil }
      while pos < bytes.count, isDigit(bytes[pos]) { pos += 1 }
    }
    guard let literal = String(bytes: bytes[start..<pos], encoding: .utf8) else { return nil }
    if !isFloat {
      if let i = Int64(literal) { return .int(i) }
      if let u = UInt64(literal) { return .uint(u) }
    }
    guard let d = Double(literal), d.isFinite else { return nil }
    return .double(d)
  }

  func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
}
