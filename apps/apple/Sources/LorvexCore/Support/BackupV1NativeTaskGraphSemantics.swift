import CryptoKit
import Foundation
import LorvexDomain

/// Primitive semantics owned by the retained public-v1/native-graph-v1
/// decoder. These constants and algorithms must not follow mutable runtime
/// helpers: a future app may evolve its live contracts without changing what a
/// version-1 backup meant when it was published.
enum BackupV1NativeTaskGraphSemantics {
  private static let successorDomain = "lorvex.task-recurrence-successor.v1"
  private static let maxOperationalHLCPhysicalMs: UInt64 = 9_999_913_599_999
  private static let maxHLCCounter: UInt32 = 9_999

  static func isOperationallyAcceptable(_ value: Hlc) -> Bool {
    value.physicalMs <= maxOperationalHLCPhysicalMs
  }

  static func hasOperationalSuccessor(after value: Hlc) -> Bool {
    value.physicalMs < maxOperationalHLCPhysicalMs
      || (value.physicalMs == maxOperationalHLCPhysicalMs && value.counter < maxHLCCounter)
  }

  static func isCanonicalUUID(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 36 else { return false }
    for (index, byte) in bytes.enumerated() {
      if index == 8 || index == 13 || index == 18 || index == 23 {
        guard byte == 0x2D else { return false }
      } else {
        guard isLowerHex(byte) else { return false }
      }
    }
    return true
  }

  static func isCanonicalListID(_ value: String) -> Bool {
    value == "inbox" || isCanonicalUUID(value)
  }

  static func isCanonicalDate(_ value: String) -> Bool {
    guard let parts = dateParts(value) else { return false }
    return parts.day <= daysInMonth(year: parts.year, month: parts.month)
  }

  /// Public-v1 portable task dates were emitted either as a canonical date or
  /// as the exporter's exact millisecond UTC timestamp. Project both to the
  /// native graph's calendar-date representation without consulting mutable
  /// formatters or the host locale.
  static func portableTaskDate(_ value: String) -> String? {
    if isCanonicalDate(value) { return value }
    guard isCanonicalTimestamp(value) else { return nil }
    return String(value.prefix(10))
  }

  static func isCanonicalTimestamp(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 24,
      bytes[4] == 0x2D, bytes[7] == 0x2D, bytes[10] == 0x54,
      bytes[13] == 0x3A, bytes[16] == 0x3A, bytes[19] == 0x2E,
      bytes[23] == 0x5A
    else { return false }
    let digitPositions = [
      0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18, 20, 21, 22,
    ]
    guard digitPositions.allSatisfy({ isDigit(bytes[$0]) }) else { return false }
    let date = String(value.prefix(10))
    guard isCanonicalDate(date) else { return false }
    let hour = number(bytes[11], bytes[12])
    let minute = number(bytes[14], bytes[15])
    let second = number(bytes[17], bytes[18])
    return hour <= 23 && minute <= 59 && second <= 59
  }

  static func recurrenceInstanceKey(groupID: String, date: String) -> String? {
    guard isCanonicalUUID(groupID), isCanonicalDate(date) else { return nil }
    return "\(groupID):\(date)"
  }

  static func recurrenceSuccessorID(parentTaskID: String, groupID: String) -> String {
    var material = Data()
    material.append(contentsOf: successorDomain.utf8)
    material.append(0)
    material.append(contentsOf: parentTaskID.utf8)
    material.append(0)
    material.append(contentsOf: groupID.utf8)
    var bytes = Array(SHA256.hash(data: material).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x80
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    var output = ""
    output.reserveCapacity(36)
    for index in bytes.indices {
      if index == 4 || index == 6 || index == 8 || index == 10 { output.append("-") }
      output.append(hex(bytes[index] >> 4))
      output.append(hex(bytes[index] & 0x0F))
    }
    return output
  }

  static func dependencyEntityID(taskID: String, dependsOnTaskID: String) -> String {
    "\(taskID):\(dependsOnTaskID)"
  }

  static func isCanonicalTaskSyncIdentity(kind: EntityKind, entityID: String) -> Bool {
    switch kind {
    case .task, .taskReminder, .taskChecklistItem:
      return isCanonicalUUID(entityID)
    case .taskTag, .taskDependency, .taskCalendarEventLink:
      guard let pair = splitPair(entityID) else { return false }
      return isCanonicalUUID(pair.0) && isCanonicalUUID(pair.1)
    default:
      return false
    }
  }

  /// Preserve forward-compatible IANA identifiers without consulting the host
  /// OS timezone database, whose contents vary over time. A producer-generated
  /// v1 value is a compact, trimmed ASCII identifier; runtime scheduling may
  /// resolve it after the retained backup has been adapted to the current app.
  static func isStableTimezoneIdentifier(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard !bytes.isEmpty, bytes.count <= 255,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    else { return false }
    return bytes.allSatisfy {
      isDigit($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
        || $0 == 0x2B || $0 == 0x2D || $0 == 0x2E || $0 == 0x2F || $0 == 0x5F
    }
  }

  static func entityKind(_ raw: String) -> EntityKind? {
    switch raw {
    case "task": return .task
    case "task_reminder": return .taskReminder
    case "task_checklist_item": return .taskChecklistItem
    case "task_tag": return .taskTag
    case "task_dependency": return .taskDependency
    case "task_calendar_event_link": return .taskCalendarEventLink
    default: return nil
    }
  }

  static func canonicalUntilDate(_ value: String) -> String? {
    if isCanonicalDate(value) { return value }
    let bytes = Array(value.utf8)
    if bytes.count == 8, bytes.allSatisfy(isDigit) {
      let expanded = String(bytes: bytes[0..<4], encoding: .utf8)! + "-"
        + String(bytes: bytes[4..<6], encoding: .utf8)! + "-"
        + String(bytes: bytes[6..<8], encoding: .utf8)!
      return isCanonicalDate(expanded) ? expanded : nil
    }
    guard bytes.count == 16, bytes[8] == 0x54, bytes[15] == 0x5A,
      Array(bytes[0..<8]).allSatisfy(isDigit),
      Array(bytes[9..<15]).allSatisfy(isDigit)
    else { return nil }
    let hour = number(bytes[9], bytes[10])
    let minute = number(bytes[11], bytes[12])
    let second = number(bytes[13], bytes[14])
    guard hour <= 23, minute <= 59, second <= 60 else { return nil }
    let expanded = String(bytes: bytes[0..<4], encoding: .utf8)! + "-"
      + String(bytes: bytes[4..<6], encoding: .utf8)! + "-"
      + String(bytes: bytes[6..<8], encoding: .utf8)!
    return isCanonicalDate(expanded) ? expanded : nil
  }

  private static func splitPair(_ value: String) -> (String, String)? {
    guard value.utf8.filter({ $0 == 0x3A }).count == 1,
      let separator = value.firstIndex(of: ":")
    else { return nil }
    let left = String(value[..<separator])
    let right = String(value[value.index(after: separator)...])
    return left.isEmpty || right.isEmpty ? nil : (left, right)
  }

  private static func dateParts(_ value: String) -> (year: Int, month: Int, day: Int)? {
    let bytes = Array(value.utf8)
    guard bytes.count == 10, bytes[4] == 0x2D, bytes[7] == 0x2D,
      [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy({ isDigit(bytes[$0]) })
    else { return nil }
    let year = number(bytes[0], bytes[1], bytes[2], bytes[3])
    let month = number(bytes[5], bytes[6])
    let day = number(bytes[8], bytes[9])
    guard (1...12).contains(month), day >= 1 else { return nil }
    return (year, month, day)
  }

  private static func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 2: return isLeapYear(year) ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }

  private static func isLeapYear(_ year: Int) -> Bool {
    year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
  }

  private static func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
  private static func isLowerHex(_ byte: UInt8) -> Bool {
    isDigit(byte) || (0x61...0x66).contains(byte)
  }
  private static func number(_ bytes: UInt8...) -> Int {
    bytes.reduce(0) { $0 * 10 + Int($1 - 0x30) }
  }
  private static func hex(_ nibble: UInt8) -> Character {
    Character(String(UnicodeScalar(nibble < 10 ? 48 + nibble : 87 + nibble)))
  }
}
