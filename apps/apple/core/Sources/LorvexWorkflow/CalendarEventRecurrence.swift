import Foundation
import LorvexDomain

/// EXDATE skeleton-preserve comparator used by the calendar-event update
/// path to decide whether a recurrence patch keeps the stored exception
/// list.
///
/// Two canonical recurrence-rule JSON blobs share the same skeleton (and
/// therefore name the same instance grid) iff they agree on every scalar
/// bound (`FREQ`, `INTERVAL`, `WKST`) and every BY-array (`BYDAY`,
/// `BYMONTHDAY`, `BYMONTH`, `BYSETPOS`, `BYHOUR`, `BYMINUTE`, `BYSECOND`)
/// treated as a set. UNTIL / COUNT differences do not move the grid and
/// therefore do not invalidate EXDATE.
///
/// A parse failure on either side conservatively returns `false`
/// (drop EXDATE).
public enum CalendarEventRecurrence {
  public static func recurrenceSkeletonMatches(
    _ oldJSON: String, _ newJSON: String
  ) -> Bool {
    guard let oldVal = JSONValue.parse(oldJSON),
      let newVal = JSONValue.parse(newJSON),
      case .object(let oldObj) = oldVal,
      case .object(let newObj) = newVal
    else { return false }

    let scalarFields = ["FREQ", "INTERVAL", "WKST"]
    for field in scalarFields {
      if (oldObj[field] ?? .null) != (newObj[field] ?? .null) { return false }
    }

    let arrayFields = [
      "BYDAY", "BYMONTHDAY", "BYMONTH", "BYSETPOS",
      "BYHOUR", "BYMINUTE", "BYSECOND",
    ]
    for field in arrayFields {
      if !jsonArraySetEq(oldObj[field], newObj[field]) { return false }
    }
    return true
  }

  /// Compare two optional JSON values as sorted+deduped sets. `nil` and
  /// `.null` are the empty set; mismatched shapes (array vs scalar)
  /// compare unequal.
  static func jsonArraySetEq(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
    func canonical(_ v: JSONValue?) -> [String] {
      switch v {
      case .none, .some(.null): return []
      case .some(.array(let items)):
        var s = items.map(jsonValueToCompactString)
        s.sort()
        // Dedup consecutive duplicates (post-sort).
        var deduped: [String] = []
        for x in s { if deduped.last != x { deduped.append(x) } }
        return deduped
      case .some(let other):
        return [jsonValueToCompactString(other)]
      }
    }
    return canonical(a) == canonical(b)
  }
}

/// Compact JSON encoding of a single ``JSONValue`` used as the key for the
/// skeleton set comparison, covering the value shapes produced by canonicalized
/// recurrence rules (strings, integers, booleans). Strings are rendered with
/// double quotes and standard escapes.
private func jsonValueToCompactString(_ v: JSONValue) -> String {
  switch v {
  case .null: return "null"
  case .bool(let b): return b ? "true" : "false"
  case .int(let i): return String(i)
  case .uint(let u): return String(u)
  case .double(let d): return String(d)
  case .string(let s):
    // Render strings with double quotes and standard escapes.
    var out = "\""
    for scalar in s.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out += String(scalar)
        }
      }
    }
    out += "\""
    return out
  case .array(let items):
    return "[" + items.map(jsonValueToCompactString).joined(separator: ",") + "]"
  case .object(let map):
    // Stable: sort by key.
    let pairs = map.keys.sorted().map { k -> String in
      jsonValueToCompactString(.string(k)) + ":" + jsonValueToCompactString(map[k]!)
    }
    return "{" + pairs.joined(separator: ",") + "}"
  }
}
