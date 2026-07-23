import Foundation

/// Canonical JSON serialization: sorted keys, compact format.
///
/// The output is a stable wire contract: sync checksums are computed over these
/// bytes, so the serialization must be byte-stable across every surface — a
/// single differing byte would make every synced record look changed.
///
/// Contract:
/// - Object keys are sorted by their **UTF-8 byte sequence** (not Unicode
///   collation), then emitted compactly as `{"k":v,...}`.
/// - Arrays preserve order: `[v,v,...]`.
/// - Strings use a fixed escape table (`"`, `\`, `\n`, `\r`, `\t`, `\b`=0x08,
///   `\f`=0x0c, other control chars `<0x20` as lowercase `\u00xx`); all other
///   bytes — including multi-byte UTF-8 — pass through unescaped.
/// - Nesting deeper than ``maxJSONDepth`` throws ``CanonError/depthExceeded``.
/// - A non-finite ``JSONValue/double(_:)`` (`nan`/`inf`/`-inf`) throws
///   ``CanonError/nonFiniteDouble`` rather than emitting an invalid JSON token.
public enum CanonError: Error, Equatable {
  /// Input JSON nested deeper than ``maxJSONDepth``.
  case depthExceeded
  /// A ``JSONValue/double(_:)`` holding a non-finite value (`nan`/`inf`/`-inf`),
  /// which has no valid JSON representation. Parsed input never yields one (the
  /// parser rejects overflow literals), so this signals a hand-built value.
  case nonFiniteDouble
}

/// Maximum accepted nesting depth. Depths in `0..<maxJSONDepth` are accepted
/// (the outermost value is depth 0); the first level at `maxJSONDepth` errors.
/// This limit is part of the wire contract; every surface must use the same
/// value so all sides accept the same inputs.
public let maxJSONDepth = 32

/// Canonicalize a JSON value to its sorted-key, compact string form.
public func canonicalizeJSON(_ value: JSONValue) throws -> String {
  var out = ""
  try writeCanonical(value, depth: 0, into: &out)
  return out
}

private func writeCanonical(_ value: JSONValue, depth: Int, into out: inout String) throws {
  if depth >= maxJSONDepth {
    throw CanonError.depthExceeded
  }
  switch value {
  case .object(let map):
    // Sort by UTF-8 bytes for a stable byte order.
    // Swift's default `String` comparison is Unicode-canonical and would
    // diverge for non-ASCII keys.
    let entries = map.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
    out.append("{")
    for (i, entry) in entries.enumerated() {
      if i > 0 { out.append(",") }
      writeJSONString(entry.key, into: &out)
      out.append(":")
      try writeCanonical(entry.value, depth: depth + 1, into: &out)
    }
    out.append("}")
  case .array(let arr):
    out.append("[")
    for (i, v) in arr.enumerated() {
      if i > 0 { out.append(",") }
      try writeCanonical(v, depth: depth + 1, into: &out)
    }
    out.append("]")
  case .null:
    out.append("null")
  case .bool(let b):
    out.append(b ? "true" : "false")
  case .int(let n):
    out.append(String(n))
  case .uint(let n):
    out.append(String(n))
  case .double(let d):
    // `nan`/`inf`/`-inf` have no valid JSON form; emitting a bare token would
    // yield unparseable, non-round-tripping output, so fail loudly instead.
    guard d.isFinite else { throw CanonError.nonFiniteDouble }
    out.append(formatDouble(d))
  case .string(let s):
    writeJSONString(s, into: &out)
  }
}

/// A fixed string escape table, applied so output is byte-stable across surfaces.
///
/// Iterates Unicode scalars rather than bytes: every escaped code point is
/// single-byte ASCII (`<0x80`), and multi-byte UTF-8 scalars are appended
/// verbatim, so scalar iteration produces the same bytes as byte-iteration
/// would.
private func writeJSONString(_ s: String, into out: inout String) {
  out.append("\"")
  for scalar in s.unicodeScalars {
    switch scalar.value {
    case 0x22: out.append("\\\"")
    case 0x5C: out.append("\\\\")
    case 0x0A: out.append("\\n")
    case 0x0D: out.append("\\r")
    case 0x09: out.append("\\t")
    case 0x08: out.append("\\b")
    case 0x0C: out.append("\\f")
    case let v where v < 0x20:
      out.append("\\u")
      out.append(String(format: "%04x", v))
    default:
      out.unicodeScalars.append(scalar)
    }
  }
  out.append("\"")
}

/// Formats a finite `Double` for the common cases the domain produces (integral
/// values render with a `.0`).
///
/// Float payloads are rare in canonicalized domain data (durations, priorities,
/// and clocks are integers; timestamps are strings). Exhaustive shortest-round-trip
/// float formatting is deferred until a real float-bearing payload appears; the
/// fixtures stay on integers/strings/bool/null for the byte-equality gate.
private func formatDouble(_ d: Double) -> String {
  if d == d.rounded() && abs(d) < 1e16 {
    return String(format: "%.1f", d)
  }
  return String(d)
}
