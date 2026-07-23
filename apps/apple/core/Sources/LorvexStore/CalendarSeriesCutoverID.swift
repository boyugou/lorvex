import CryptoKit
import Foundation

/// Deterministic UUIDv8 identity for one recurring-series lineage boundary.
public enum CalendarSeriesCutoverID {
  private static let domain = "lorvex.calendar-series-cutover.v1"

  public static func make(lineageRootId: String, cutoverDate: String) -> String {
    var material = Data()
    material.append(contentsOf: domain.utf8)
    material.append(0)
    material.append(contentsOf: lineageRootId.utf8)
    material.append(0)
    material.append(contentsOf: cutoverDate.utf8)

    var bytes = Array(SHA256.hash(data: material).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x80
    bytes[8] = (bytes[8] & 0x3F) | 0x80

    var output = ""
    output.reserveCapacity(36)
    for index in bytes.indices {
      if index == 4 || index == 6 || index == 8 || index == 10 {
        output.append("-")
      }
      output.append(hex(bytes[index] >> 4))
      output.append(hex(bytes[index] & 0x0F))
    }
    return output
  }

  private static func hex(_ nibble: UInt8) -> Character {
    Character(String(UnicodeScalar(nibble < 10 ? 48 + nibble : 87 + nibble)))
  }
}
