import CryptoKit
import Foundation

/// SHA-256 lowercase hex digests for content addressing and checksum
/// verification (schema migrations, idempotency-request checksums, wire
/// payload checksums).
public enum Sha256Checksum {
  /// The SHA-256 digest of `data` as a 64-character lowercase hex string.
  public static func hexDigest(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
    var hex = [UInt8]()
    hex.reserveCapacity(SHA256.Digest.byteCount * 2)
    for byte in digest {
      hex.append(hexDigits[Int(byte >> 4)])
      hex.append(hexDigits[Int(byte & 0x0F)])
    }
    return String(decoding: hex, as: UTF8.self)
  }
}
