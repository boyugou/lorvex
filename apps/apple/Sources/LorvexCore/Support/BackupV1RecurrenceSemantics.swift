import Foundation
import LorvexDomain

/// Frozen canonical recurrence language used by public-v1/native-graph-v1.
/// It intentionally owns its vocabulary and limits instead of delegating to
/// the current app's recurrence validator.
enum BackupV1RecurrenceSemantics {
  struct Violation: Error, CustomStringConvertible {
    let description: String
  }

  private static let knownKeys: Set<String> = [
    "FREQ", "INTERVAL", "BYDAY", "BYMONTH", "BYMONTHDAY",
    "BYSETPOS", "WKST", "UNTIL", "COUNT", "ANCHOR",
  ]
  private static let frequencies: Set<String> = ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"]
  private static let weekdays = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
  private static let maxInterval: Int64 = 10_000

  static func canonicalize(_ raw: String) throws -> String {
    guard let parsed = JSONValue.parse(raw), case .object(let object) = parsed else {
      throw Violation(description: "recurrence must be a JSON object")
    }
    if let unknown = object.keys.sorted().first(where: { !knownKeys.contains($0) }) {
      throw Violation(description: "recurrence uses graph-v1-unknown key \(unknown)")
    }
    guard let frequency = string(object["FREQ"]), frequencies.contains(frequency) else {
      throw Violation(description: "FREQ must be DAILY, WEEKLY, MONTHLY, or YEARLY")
    }
    let interval = try integer(object["INTERVAL"], default: 1, field: "INTERVAL")
    guard (1...maxInterval).contains(interval) else {
      throw Violation(description: "INTERVAL must be in 1...\(maxInterval)")
    }

    let byDay = try parseByDay(object["BYDAY"], frequency: frequency)
    let byMonth = try parseIntegerArray(
      object["BYMONTH"], field: "BYMONTH", range: 1...12,
      allowed: frequency != "DAILY")
    let byMonthDay = try parseMonthDays(object["BYMONTHDAY"], frequency: frequency)
    let bySetPos = try parseIntegerArray(
      object["BYSETPOS"], field: "BYSETPOS", range: -366...366,
      allowed: frequency == "MONTHLY" || frequency == "YEARLY", excludingZero: true)
    let weekStart = try parseWeekStart(object["WKST"])
    let until = try parseUntil(object["UNTIL"])
    let count = try parseCount(object["COUNT"])
    guard count == nil || until == nil else {
      throw Violation(description: "COUNT and UNTIL are mutually exclusive")
    }
    let anchor = try parseAnchor(object["ANCHOR"], wholeObject: object)

    var canonical: [String: JSONValue] = [
      "FREQ": .string(frequency), "INTERVAL": .int(interval),
    ]
    if let byDay { canonical["BYDAY"] = .array(byDay.map(JSONValue.string)) }
    if let byMonth { canonical["BYMONTH"] = .array(byMonth.map(JSONValue.int)) }
    if let byMonthDay { canonical["BYMONTHDAY"] = .array(byMonthDay.map(JSONValue.int)) }
    if let bySetPos { canonical["BYSETPOS"] = .array(bySetPos.map(JSONValue.int)) }
    if let weekStart { canonical["WKST"] = .string(weekStart) }
    if let until { canonical["UNTIL"] = .string(until) }
    if let count { canonical["COUNT"] = .int(count) }
    if let anchor { canonical["ANCHOR"] = .string(anchor) }
    do {
      return try canonicalizeJSON(.object(canonical))
    } catch {
      throw Violation(description: "recurrence cannot be serialized canonically")
    }
  }

  private static func parseByDay(
    _ value: JSONValue?, frequency: String
  ) throws -> [String]? {
    guard let value else { return nil }
    guard case .array(let array) = value else {
      throw Violation(description: "BYDAY must be an array")
    }
    if !array.isEmpty && !["WEEKLY", "MONTHLY", "YEARLY"].contains(frequency) {
      throw Violation(description: "BYDAY is not valid for \(frequency)")
    }
    var result: [String] = []
    for item in array {
      guard let token = string(item), validByDay(token, frequency: frequency) else {
        throw Violation(description: "BYDAY contains an invalid graph-v1 token")
      }
      result.append(token)
    }
    guard !result.isEmpty else { return nil }
    result.sort {
      let lhs = byDaySortKey($0)
      let rhs = byDaySortKey($1)
      return lhs == rhs ? $0 < $1 : lhs < rhs
    }
    return adjacentDedup(result)
  }

  private static func parseIntegerArray(
    _ value: JSONValue?, field: String, range: ClosedRange<Int64>, allowed: Bool,
    excludingZero: Bool = false
  ) throws -> [Int64]? {
    guard let value else { return nil }
    guard allowed else { throw Violation(description: "\(field) is not valid for this FREQ") }
    guard case .array(let array) = value else {
      throw Violation(description: "\(field) must be an array of integers")
    }
    var result: [Int64] = []
    for item in array {
      guard let number = integer(item), range.contains(number), !excludingZero || number != 0 else {
        throw Violation(description: "\(field) contains an out-of-range integer")
      }
      result.append(number)
    }
    guard !result.isEmpty else { return nil }
    result.sort()
    return adjacentDedup(result)
  }

  private static func parseMonthDays(
    _ value: JSONValue?, frequency: String
  ) throws -> [Int64]? {
    guard let value else { return nil }
    let values: [Int64]
    if let scalar = integer(value) {
      values = [scalar]
    } else if case .array(let array) = value {
      values = try array.map {
        guard let number = integer($0) else {
          throw Violation(description: "BYMONTHDAY must contain integers")
        }
        return number
      }
    } else {
      throw Violation(description: "BYMONTHDAY must be an integer or integer array")
    }
    guard !values.isEmpty else { return nil }
    guard frequency == "MONTHLY" || frequency == "YEARLY" else {
      throw Violation(description: "BYMONTHDAY is not valid for \(frequency)")
    }
    guard values.allSatisfy({ $0 != 0 && (-31...31).contains($0) }) else {
      throw Violation(description: "BYMONTHDAY contains an out-of-range integer")
    }
    return adjacentDedup(values.sorted())
  }

  private static func parseWeekStart(_ value: JSONValue?) throws -> String? {
    guard let value else { return nil }
    guard let code = string(value), weekdays.contains(code) else {
      throw Violation(description: "WKST must be a weekday code")
    }
    return code
  }

  private static func parseUntil(_ value: JSONValue?) throws -> String? {
    guard let value else { return nil }
    guard let raw = string(value),
      let date = BackupV1NativeTaskGraphSemantics.canonicalUntilDate(raw)
    else { throw Violation(description: "UNTIL is not a supported date") }
    return date
  }

  private static func parseCount(_ value: JSONValue?) throws -> Int64? {
    guard let value else { return nil }
    guard let count = integer(value), count >= 1 else {
      throw Violation(description: "COUNT must be a positive integer")
    }
    return count
  }

  private static func parseAnchor(
    _ value: JSONValue?, wholeObject: [String: JSONValue]
  ) throws -> String? {
    guard let value else { return nil }
    guard let anchor = string(value) else {
      throw Violation(description: "ANCHOR must be schedule or completion")
    }
    if anchor == "schedule" { return nil }
    guard anchor == "completion" else {
      throw Violation(description: "ANCHOR must be schedule or completion")
    }
    for key in ["BYDAY", "BYMONTH", "BYMONTHDAY", "BYSETPOS", "WKST"]
    where wholeObject[key] != nil {
      throw Violation(description: "ANCHOR=completion cannot combine with \(key)")
    }
    return anchor
  }

  private static func validByDay(_ token: String, frequency: String) -> Bool {
    let bytes = Array(token.utf8)
    guard bytes.count >= 2,
      let code = String(bytes: bytes.suffix(2), encoding: .utf8), weekdays.contains(code)
    else { return false }
    let prefix = Array(bytes.dropLast(2))
    if prefix.isEmpty { return true }
    guard frequency == "MONTHLY" || frequency == "YEARLY" else { return false }
    var digits = prefix
    if digits.first == 0x2B || digits.first == 0x2D { digits.removeFirst() }
    guard !digits.isEmpty, digits.allSatisfy({ (0x30...0x39).contains($0) }),
      !(digits.count > 1 && digits[0] == 0x30),
      let ordinal = Int(String(bytes: digits, encoding: .utf8) ?? "")
    else { return false }
    return (1...(frequency == "MONTHLY" ? 5 : 53)).contains(ordinal)
  }

  private static func byDaySortKey(_ token: String) -> (Int, Int) {
    let bytes = Array(token.utf8)
    let code = String(bytes: bytes.suffix(2), encoding: .utf8) ?? ""
    let weekday = weekdays.firstIndex(of: code) ?? 7
    let prefix = String(bytes: bytes.dropLast(2), encoding: .utf8) ?? ""
    return (prefix.isEmpty ? 0 : (Int(prefix) ?? Int.max), weekday)
  }

  private static func integer(
    _ value: JSONValue?, default defaultValue: Int64, field: String
  ) throws -> Int64 {
    guard let value else { return defaultValue }
    guard let result = integer(value) else {
      throw Violation(description: "\(field) must be an integer")
    }
    return result
  }

  private static func integer(_ value: JSONValue) -> Int64? {
    switch value {
    case .int(let number): return number
    case .uint(let number) where number <= UInt64(Int64.max): return Int64(number)
    default: return nil
    }
  }

  private static func string(_ value: JSONValue?) -> String? {
    guard let value, case .string(let result) = value else { return nil }
    return result
  }

  private static func adjacentDedup<T: Equatable>(_ values: [T]) -> [T] {
    var result: [T] = []
    for value in values where result.last != value { result.append(value) }
    return result
  }
}
