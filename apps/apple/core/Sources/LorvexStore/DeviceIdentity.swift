import CryptoKit
import Foundation
import LorvexDomain

public enum DeviceIdentity {
  /// Derive the 16-character HLC device suffix from a stable `deviceId` and
  /// an emitting `surface` tag.
  ///
  /// The derivation:
  ///
  /// 1. Stream the UTF-8 bytes of `deviceId`, **skipping ASCII `'-'` (0x2D)**.
  /// 2. Fold any ASCII uppercase byte to lowercase via `byte | 0x20`. (Only
  ///    safe because device ids are ASCII hex by construction; the same trick
  ///    is fine on lowercase letters and digits because their bit 5 is already
  ///    set or the value is preserved.)
  /// 3. Hash the normalized bytes, then `b"|"`, then `surface.rawValue` bytes.
  /// 4. Take the first 8 bytes of the SHA-256 digest and emit them as 16
  ///    lowercase hex characters.
  ///
  /// 16 hex characters = 64 bits — birthday-collision probability remains
  /// negligible at any realistic install scale, so same-millisecond writes
  /// from different surfaces (or different devices on the same surface) tie-
  /// break deterministically in LWW order.
  public static func deviceIdToHlcSuffix(
    _ deviceId: String, surface: HlcSurface
  ) -> String {
    var hasher = SHA256()
    var normalized: [UInt8] = []
    normalized.reserveCapacity(deviceId.utf8.count)
    for byte in deviceId.utf8 {
      if byte == 0x2D { continue }  // skip '-'
      let folded: UInt8 = (byte >= 0x41 && byte <= 0x5A) ? (byte | 0x20) : byte
      normalized.append(folded)
    }
    hasher.update(data: normalized)
    hasher.update(data: Data([0x7C]))  // '|'
    hasher.update(data: Data(surface.rawValue.utf8))
    let digest = hasher.finalize()
    let bytesNeeded = HlcConstants.deviceSuffixHexLen / 2
    var out = ""
    out.reserveCapacity(HlcConstants.deviceSuffixHexLen)
    for byte in digest.prefix(bytesNeeded) {
      out.append(hexChar(byte >> 4))
      out.append(hexChar(byte & 0x0F))
    }
    return out
  }

  private static func hexChar(_ nibble: UInt8) -> Character {
    let table: [Character] = [
      "0", "1", "2", "3", "4", "5", "6", "7",
      "8", "9", "a", "b", "c", "d", "e", "f",
    ]
    return table[Int(nibble)]
  }
}

public enum DeviceIdentityError: Error, Equatable {
  /// The if-absent device-id claim reported the slot was already populated,
  /// but the follow-up read returned `nil`. Only reachable on a misbehaving
  /// store.
  case unavailable
}
