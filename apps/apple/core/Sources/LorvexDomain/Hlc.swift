import Foundation

/// Hybrid Logical Clock value type — `physical_ms` (Unix ms) + monotonic
/// `counter` + 16-hex `deviceSuffix` triple.
///
/// Canonical wire format: `{physical_ms:013}_{counter:04}_{deviceSuffix}`
/// (13-digit zero-padded ms, 4-digit zero-padded counter, 16-char
/// lowercase-hex device suffix). Persisted in sync cursors and compared
/// lexicographically by raw bytes in SQL, so format and ordering are a stable
/// wire contract:
///
/// - `Comparable`: lex over `(physical_ms, counter, deviceSuffix)`, identical
///   to the string-byte order of the canonical display form.
/// - Construction normalizes mixed-case input to lowercase so cross-device
///   case drift can't break LWW. Stored `deviceSuffix` is invariably 16
///   lowercase hex chars.
public struct Hlc: Sendable, Equatable, Hashable {
  /// Maximum `physical_ms` value. `9_999_999_999_999` is the largest
  /// 13-digit integer the canonical `{:013}` zero-pad emits without
  /// inflating to 14 digits — going past it would lex-sort above every
  /// 13-digit HLC forever and poison cluster-wide LWW. Corresponds to
  /// ~Nov 20, year 2286.
  public static let maxPhysicalMs: UInt64 = 9_999_999_999_999

  /// Highest physical component that may participate in the operational wire
  /// contract. The same ceiling governs inbound acceptance, local generation,
  /// durable snapshots, audit metadata, and outbound emission. Reserving the
  /// final 24 hours of the 13-digit range is arithmetic safety only. Values at
  /// this physical ceiling remain ordinary shared state while their counter has
  /// successor headroom; the exact terminal `(ceiling, maxCounter)` remains
  /// parseable provenance but is held before canonical apply because no local
  /// convergence write could ever dominate it.
  public static let maxOperationalWirePhysicalMs: UInt64 =
    maxPhysicalMs - 86_400_000

  /// Maximum in-millisecond counter. The wire format reserves four
  /// decimal digits (`0000`…`9999`); a larger value would widen the
  /// segment and break raw string ordering.
  public static let maxCounter: UInt32 = 9_999

  /// Whether an HLC is representable inside the operational wire range. Apply
  /// additionally requires ``hasOperationalWireSuccessor(after:)`` before a
  /// remote value may enter canonical state. This distinction retains exact
  /// opaque provenance at the terminal value without creating an uneditable row.
  public static func isOperationallyAcceptableWire(_ value: Hlc) -> Bool {
    value.physicalMs <= maxOperationalWirePhysicalMs
  }

  /// Whether the clock can mint a strictly-greater HLC without leaving the
  /// operational wire range. This is stricter than representability: the final
  /// reserved day remains parseable provenance, but may never become ordinary
  /// canonical state or outbound work.
  public static func hasOperationalWireSuccessor(after value: Hlc) -> Bool {
    value.physicalMs < maxOperationalWirePhysicalMs
      || (value.physicalMs == maxOperationalWirePhysicalMs && value.counter < maxCounter)
  }

  /// Canonical seed version for test fixtures. Starts with a digit so it
  /// sorts strictly below every realistic HLC under the lex ordering LWW
  /// gates rely on.
  public static let testVersion = "0000000000000_0000_a0a0a0a0a0a0a0a0"

  public let physicalMs: UInt64
  public let counter: UInt32
  public let deviceSuffix: String

  /// Constructor — validates and lowercases the device suffix; rejects
  /// `physicalMs > maxPhysicalMs` and `counter > maxCounter`.
  public init(physicalMs: UInt64, counter: UInt32, deviceSuffix: String) throws {
    if physicalMs > Hlc.maxPhysicalMs {
      throw HlcParseError.physicalMsOutOfRange(physicalMs)
    }
    if counter > Hlc.maxCounter {
      throw HlcParseError.counterOutOfRange(counter)
    }
    let lower = deviceSuffix.lowercased()
    try Hlc.validateDeviceSuffix(lower)
    self.physicalMs = physicalMs
    self.counter = counter
    self.deviceSuffix = lower
  }

  /// Parse from canonical string format `{physical_ms}_{counter}_{suffix}`.
  /// Strictly more permissive than `description` on width — unpadded
  /// `physical_ms`/`counter` segments parse to the same logical value — but the
  /// numeric segments MUST be all ASCII digits (a leading sign is rejected: it
  /// byte-sorts below `0` and would break the raw-byte ordering LWW rests on)
  /// and the device suffix MUST be 16 hex chars. Mixed case is normalized to
  /// lowercase so peers with case drift compare equal.
  public static func parse(_ s: String) throws -> Hlc {
    let parts = s.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3 else {
      throw HlcParseError.invalidFormat(s)
    }
    let physStr = String(parts[0])
    let ctrStr = String(parts[1])
    let suffix = String(parts[2])

    guard physStr.utf8.allSatisfy(hlcIsAsciiDigit), let physicalMs = UInt64(physStr) else {
      throw HlcParseError.invalidPhysicalMs(physStr)
    }
    if physicalMs > maxPhysicalMs {
      throw HlcParseError.physicalMsOutOfRange(physicalMs)
    }
    guard ctrStr.utf8.allSatisfy(hlcIsAsciiDigit), let counter = UInt32(ctrStr) else {
      throw HlcParseError.invalidCounter(ctrStr)
    }
    if counter > maxCounter {
      throw HlcParseError.counterOutOfRange(counter)
    }
    let lower = suffix.contains(where: { $0.isUppercase }) ? suffix.lowercased() : suffix
    try validateDeviceSuffix(lower)
    return Hlc(uncheckedPhysicalMs: physicalMs, counter: counter, deviceSuffix: lower)
  }

  /// Parse a persisted or wire HLC and require its exact canonical byte form.
  ///
  /// Use ``parse(_:)`` only when deliberately normalizing human/test input.
  /// Versions stored in SQLite or accepted across a sync boundary must use this
  /// entry point because SQL compares them with `BINARY` collation.
  public static func parseCanonical(_ s: String) throws -> Hlc {
    let parsed = try parse(s)
    guard parsed.description == s else {
      throw HlcParseError.invalidFormat(s)
    }
    return parsed
  }

  /// Backdoor constructor for code paths that have already validated the
  /// invariants (e.g. `parse`). Internal only.
  internal init(uncheckedPhysicalMs: UInt64, counter: UInt32, deviceSuffix: String) {
    self.physicalMs = uncheckedPhysicalMs
    self.counter = counter
    self.deviceSuffix = deviceSuffix
  }

  internal static func validateDeviceSuffix(_ suffix: String) throws {
    if suffix.isEmpty { throw HlcParseError.emptyDeviceSuffix }
    if suffix.count != HlcConstants.deviceSuffixHexLen {
      throw HlcParseError.invalidDeviceSuffixLength(
        suffix: suffix,
        expected: HlcConstants.deviceSuffixHexLen,
        actual: suffix.count)
    }
    for scalar in suffix.unicodeScalars {
      let v = scalar.value
      let isHex = (0x30...0x39).contains(v) || (0x61...0x66).contains(v) || (0x41...0x46).contains(v)
      if !isHex { throw HlcParseError.invalidDeviceSuffixCharset(suffix) }
    }
  }
}

public enum HlcConstants {
  /// Zero-pad width of the physical-millisecond segment in the canonical wire
  /// format. 13 digits holds `Hlc.maxPhysicalMs` (9_999_999_999_999) so the
  /// segment byte-sorts in physical-time order.
  public static let physicalMsDigits = 13
  /// Zero-pad width of the counter segment. 4 digits holds `Hlc.maxCounter`
  /// (9_999) so the segment byte-sorts in counter order.
  public static let counterDigits = 4
  /// 16 hex chars = 64 bits of device-isolation entropy.
  public static let deviceSuffixHexLen = 16
}

extension Hlc: CustomStringConvertible {
  /// Canonical wire format. The zero-pad widths
  /// (``HlcConstants/physicalMsDigits``, ``HlcConstants/counterDigits``) and
  /// `_` separators must remain stable — sync cursors and SQL string ordering
  /// depend on them.
  public var description: String {
    let phys = String(format: "%0\(HlcConstants.physicalMsDigits)llu", physicalMs)
    let ctr = String(format: "%0\(HlcConstants.counterDigits)u", counter)
    return "\(phys)_\(ctr)_\(deviceSuffix)"
  }
}

extension Hlc: Comparable {
  public static func < (lhs: Hlc, rhs: Hlc) -> Bool {
    if lhs.physicalMs != rhs.physicalMs { return lhs.physicalMs < rhs.physicalMs }
    if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
    return lhs.deviceSuffix.utf8.lexicographicallyPrecedes(rhs.deviceSuffix.utf8)
  }
}

extension Hlc: Codable {
  public init(from decoder: Decoder) throws {
    let s = try decoder.singleValueContainer().decode(String.self)
    do {
      self = try Hlc.parseCanonical(s)
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "HLC wire value is not in canonical fixed-width lowercase form"))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

/// Surface tag baked into the HLC device suffix so every Apple writer surface
/// and the MCP host emit distinct device suffixes despite sharing one
/// `sync_checkpoints.device_id`.
public enum HlcSurface: String, Sendable, CaseIterable {
  case app
  case appIntent = "app_intent"
  case widget
  case notification
  case mobile
  case mcp

  /// All surfaces in a fixed order.
  public static let allSurfaces: [HlcSurface] = [
    .app, .appIntent, .widget, .notification, .mobile, .mcp,
  ]
}

/// Compare two HLC version strings, falling back to a byte compare when
/// either side fails to parse — preserves LWW safety against tainted
/// envelopes (a malformed local value that byte-sorts above a
/// well-formed remote still wins, refusing a delete).
public func compareVersionsWithFallback(_ left: String, _ right: String)
  -> ComparisonResult
{
  if let ordering = compareCanonicalHlcStrs(left, right) { return ordering }
  // Byte compare fallback.
  if left.utf8.lexicographicallyPrecedes(right.utf8) { return .orderedAscending }
  if right.utf8.lexicographicallyPrecedes(left.utf8) { return .orderedDescending }
  return .orderedSame
}

/// Whether `incoming` should WIN a last-writer-wins tiebreak over `existing`
/// under the canonical-preferring policy — the rule that resolves a conflict
/// between a well-formed and a malformed version so a tainted value can never
/// displace a canonical one. Distinct from ``compareVersionsWithFallback(_:_:)``,
/// which is a plain three-way ordering with NO canonical preference.
///
/// Four cases over canonical `Hlc` validity:
/// - both are canonical → the strictly-greater typed `Hlc` wins (`incoming > existing`);
/// - exactly one is canonical → the canonical side wins regardless of raw
///   bytes, so a malformed value never overwrites a well-formed one and a
///   canonical value always clears a tainted one;
/// - neither is canonical → a raw UTF-8 byte compare breaks the tie so resolution
///   still terminates (the same byte ordering SQL string comparison uses).
///
/// Returns `true` only when `incoming` STRICTLY dominates `existing`; an equal or
/// losing `incoming` returns `false`. Callers read it as "overwrite `existing`
/// with `incoming`?" (tombstone monotonicity gate, SCC edge tiebreak).
public func canonicalPreferringDominates(incoming: String, existing: String) -> Bool {
  let incomingParse = canonicalHlc(incoming)
  let existingParse = canonicalHlc(existing)
  switch (incomingParse, existingParse) {
  case let (.some(incomingHlc), .some(existingHlc)):
    return incomingHlc > existingHlc
  case (.some, .none):
    // Canonical incoming vs tainted existing: incoming wins (clears taint).
    return true
  case (.none, .some):
    // Tainted incoming vs canonical existing: the canonical existing stands.
    return false
  case (.none, .none):
    // Neither parses: raw UTF-8 byte compare (the SQL string ordering).
    return existing.utf8.lexicographicallyPrecedes(incoming.utf8)
  }
}

private func canonicalHlc(_ value: String) -> Hlc? {
  try? Hlc.parseCanonical(value)
}

private func compareCanonicalHlcStrs(_ left: String, _ right: String)
  -> ComparisonResult?
{
  guard let l = splitCanonicalHlcSegments(left),
        let r = splitCanonicalHlcSegments(right) else { return nil }
  if l.phys != r.phys { return l.phys < r.phys ? .orderedAscending : .orderedDescending }
  if l.ctr != r.ctr { return l.ctr < r.ctr ? .orderedAscending : .orderedDescending }
  // The suffix is guaranteed 16 lowercase-hex bytes by the split, so a plain
  // byte compare matches SQLite BINARY exactly — no case folding.
  if l.suffix.utf8.lexicographicallyPrecedes(r.suffix.utf8) { return .orderedAscending }
  if r.suffix.utf8.lexicographicallyPrecedes(l.suffix.utf8) { return .orderedDescending }
  return .orderedSame
}

/// Split a string into canonical HLC segments, or `nil` if it is not exactly
/// canonical. Returning `nil` routes the caller to the byte-compare fallback,
/// which is the ground truth for ordering; the numeric fast path here must only
/// fire for strings whose three fixed-width segments byte-sort identically to
/// numeric order. Each segment is held to its exact width AND charset — the two
/// numeric segments all ASCII digits, the suffix 16 lowercase-hex bytes — so a
/// sign-prefixed digit, an over-range width, a non-hex suffix, or mixed case
/// (any string that byte-sorts differently from its numeric interpretation) is
/// rejected rather than parsed.
private func splitCanonicalHlcSegments(_ s: String)
  -> (phys: UInt64, ctr: UInt32, suffix: String)?
{
  let parts = s.split(separator: "_", omittingEmptySubsequences: false)
  guard parts.count == 3,
        parts[0].count == HlcConstants.physicalMsDigits,
        parts[1].count == HlcConstants.counterDigits,
        parts[2].count == HlcConstants.deviceSuffixHexLen,
        parts[0].utf8.allSatisfy(hlcIsAsciiDigit),
        parts[1].utf8.allSatisfy(hlcIsAsciiDigit),
        parts[2].utf8.allSatisfy(hlcIsLowercaseHex),
        let phys = UInt64(parts[0]),
        let ctr = UInt32(parts[1])
  else { return nil }
  return (phys, ctr, String(parts[2]))
}

/// ASCII digit `0`…`9`. Canonical HLC numeric segments admit no sign or other
/// byte, so numeric order stays identical to raw-byte order.
private func hlcIsAsciiDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

/// Lowercase-hex byte `0`…`9` / `a`…`f`. The canonical device suffix charset;
/// uppercase is excluded so the suffix byte-sorts identically to its stored form.
private func hlcIsLowercaseHex(_ b: UInt8) -> Bool {
  (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x66)
}
