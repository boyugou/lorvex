import Foundation

enum CloudSyncHex {
  private static let digits: [UInt8] = Array("0123456789abcdef".utf8)

  static func lowercase<S: Sequence<UInt8>>(_ bytes: S, capacity: Int? = nil) -> String {
    var hex = [UInt8]()
    hex.reserveCapacity((capacity ?? 0) * 2)
    for byte in bytes {
      hex.append(digits[Int(byte >> 4)])
      hex.append(digits[Int(byte & 0x0F)])
    }
    return String(decoding: hex, as: UTF8.self)
  }
}
