import Foundation

extension LorvexZipArchive {
  static func readUInt16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
  }

  static func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
      | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
  }

  /// CRC-32 (IEEE 802.3 polynomial, reflected form `0xEDB88320`) over `data`.
  public static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      for byte in buffer {
        let index = Int((crc ^ UInt32(byte)) & 0xFF)
        crc = (crc >> 8) ^ crcTable[index]
      }
    }
    return crc ^ 0xFFFF_FFFF
  }

  private static let crcTable: [UInt32] = {
    (0..<256).map { i -> UInt32 in
      var c = UInt32(i)
      for _ in 0..<8 {
        c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
      }
      return c
    }
  }()
}
