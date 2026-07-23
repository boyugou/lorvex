import Foundation

/// Entity identity helpers backed by UUIDv7.
///
/// UUIDv7 (RFC 9562) is time-sortable: the most significant bits encode a Unix
/// millisecond timestamp followed by random bits, so:
/// - `min(id)` ≈ "first-created" semantics
/// - Lexicographic string ordering ≈ chronological ordering
/// - 122 bits of post-timestamp entropy → natural collision resistance
///
/// The timestamp prefix is millisecond-granularity. Two ids minted within the
/// same millisecond differ only in their random suffix, so lexicographic
/// compare on those two is a stable-but-arbitrary order rather than
/// chronological.
public enum EntityID {
  /// Mint a new UUIDv7-shaped entity ID as a canonical hyphenated lowercase
  /// string (`8-4-4-4-12`, version nibble `7`, RFC 4122 variant).
  public static func newEntityIDString() -> String {
    newEntityIDString(nowMilliseconds: currentUnixMilliseconds(), randomBytes: randomTen)
  }

  /// Test seam: deterministic generation from an injected Unix-millisecond
  /// timestamp and a 10-byte random tail (the bytes after the 48-bit
  /// timestamp and 4-bit version nibble). The UUIDv7 byte layout is
  /// deterministic, so a fixed-input test can assert the exact string format.
  ///
  /// `randomBytes` must yield exactly 10 bytes. The high 2 bits of the first
  /// returned byte are overwritten with the RFC 4122 variant marker (`0b10`).
  public static func newEntityIDString(
    nowMilliseconds: UInt64,
    randomBytes: () -> [UInt8]
  ) -> String {
    var bytes = [UInt8](repeating: 0, count: 16)

    // 48-bit big-endian Unix-ms timestamp in the first 6 bytes.
    let ms = nowMilliseconds & 0xFFFF_FFFF_FFFF
    bytes[0] = UInt8((ms >> 40) & 0xFF)
    bytes[1] = UInt8((ms >> 32) & 0xFF)
    bytes[2] = UInt8((ms >> 24) & 0xFF)
    bytes[3] = UInt8((ms >> 16) & 0xFF)
    bytes[4] = UInt8((ms >> 8) & 0xFF)
    bytes[5] = UInt8(ms & 0xFF)

    let tail = randomBytes()
    precondition(tail.count == 10, "UUIDv7 random tail must be 10 bytes")
    for i in 0..<10 {
      bytes[6 + i] = tail[i]
    }

    // Version 7 in the high nibble of byte 6.
    bytes[6] = (bytes[6] & 0x0F) | 0x70
    // RFC 4122 variant (0b10) in the top two bits of byte 8.
    bytes[8] = (bytes[8] & 0x3F) | 0x80

    return formatHyphenated(bytes)
  }

  /// Parse a UUID-shaped entity ID at a trust boundary, with optional support
  /// for a single non-UUID sentinel value (e.g. the schema-seeded inbox
  /// sentinel for list IDs).
  ///
  /// The contract:
  /// 1. The input is trimmed first; surrounding whitespace is silently
  ///    absorbed.
  /// 2. If the trimmed value is empty, returns ``ValidationError/empty(_:)``
  ///    carrying `field`.
  /// 3. If `sentinel` is non-nil and the trimmed value equals it, the trimmed
  ///    string is returned verbatim — no UUID shape check runs.
  /// 4. Otherwise the trimmed value must be a canonical hyphenated lowercase
  ///    UUID (any version); a failure surfaces as
  ///    ``ValidationError/invalidFormat(field:expected:actual:)`` with the
  ///    trimmed value as `actual` and `expected` = `"UUID"`.
  ///
  /// The returned string is the trimmed input verbatim, not a re-canonicalized
  /// form.
  public static func parseIDWithSentinel(
    _ value: String,
    field: String,
    sentinel: String? = nil
  ) -> Result<String, ValidationError> {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return .failure(.empty(field))
    }
    if let sentinel, trimmed == sentinel {
      return .success(trimmed)
    }
    if isCanonicalUUID(trimmed) {
      return .success(trimmed)
    }
    return .failure(.invalidFormat(field: field, expected: "UUID", actual: trimmed))
  }

  // MARK: - Internals

  private static func currentUnixMilliseconds() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000.0)
  }

  private static func randomTen() -> [UInt8] {
    var out = [UInt8](repeating: 0, count: 10)
    var rng = SystemRandomNumberGenerator()
    for i in 0..<10 {
      out[i] = UInt8.random(in: 0...255, using: &rng)
    }
    return out
  }

  private static let hexDigits: [Character] = Array("0123456789abcdef")

  private static func formatHyphenated(_ bytes: [UInt8]) -> String {
    var s = ""
    s.reserveCapacity(36)
    for (index, byte) in bytes.enumerated() {
      if index == 4 || index == 6 || index == 8 || index == 10 {
        s.append("-")
      }
      s.append(hexDigits[Int(byte >> 4)])
      s.append(hexDigits[Int(byte & 0x0F)])
    }
    return s
  }

  /// True iff `value` is a canonical hyphenated lowercase UUID: 36 chars,
  /// hyphens at positions 8/13/18/23, all other chars lowercase hex.
  ///
  /// This is intentionally strict: uppercase, unhyphenated, braced, and
  /// `urn:uuid:` forms are all rejected. The Lorvex wire format only ever emits
  /// canonical hyphenated lowercase UUIDs. Delegates to
  /// ``SyncEntityId/isCanonicalUuid(_:)``, the module's single implementation
  /// of the canonical-UUID byte check.
  static func isCanonicalUUID(_ value: String) -> Bool {
    SyncEntityId.isCanonicalUuid(value)
  }
}
