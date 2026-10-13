import Foundation
import LorvexDomain

/// Moving a recurring task's due date moves the day its rule is pinned to: a
/// monthly rule on the 6th, moved to the 15th, repeats on the 15th from then on.
enum RecurrenceReanchor {
  private static let weekdayCodes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

  /// The canonical rule `json` with its one pinned day (day of the month, month
  /// of the year, or weekday) set to the one `date` falls on, or nil when the rule
  /// pins no single day or already names it. A rule that lists several days, or
  /// counts an ordinal weekday, is left as the user wrote it.
  static func rule(_ json: String, movedTo date: String) -> String? {
    guard let ymd = IsoDate.parse(date),
      case .object(var object)? = JSONValue.parse(json),
      case .string(let freq)? = object["FREQ"]
    else { return nil }
    var changed = false

    func pin(_ key: String, to value: JSONValue) {
      guard case .array(let current)? = object[key], current.count == 1, current[0] != value
      else { return }
      object[key] = .array([value])
      changed = true
    }

    switch freq {
    case "MONTHLY":
      pin("BYMONTHDAY", to: .int(Int64(ymd.day)))
    case "YEARLY":
      pin("BYMONTH", to: .int(Int64(ymd.month)))
      pin("BYMONTHDAY", to: .int(Int64(ymd.day)))
    case "WEEKLY":
      let index = ((IsoDate.dayNumber(ymd) + 3) % 7 + 7) % 7
      pin("BYDAY", to: .string(weekdayCodes[index]))
    default:
      break
    }
    guard changed else { return nil }
    return try? canonicalizeJSON(.object(object))
  }
}
