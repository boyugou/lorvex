@preconcurrency import EventKit
import Foundation
import LorvexCore

enum EventKitRecurrenceBridge {
  static func json(from rule: EKRecurrenceRule?) -> String? {
    guard let rule else { return nil }
    var object: [String: Any] = [
      "FREQ": frequencyString(rule.frequency),
    ]
    if rule.interval > 1 {
      object["INTERVAL"] = rule.interval
    }
    if let end = rule.recurrenceEnd {
      if end.occurrenceCount > 0 {
        object["COUNT"] = end.occurrenceCount
      } else if let endDate = end.endDate {
        object["UNTIL"] = LorvexDateFormatters.ymd.string(from: endDate)
      }
    }
    if let days = rule.daysOfTheWeek, !days.isEmpty {
      object["BYDAY"] = days.map(dayString)
    }
    if let monthDays = rule.daysOfTheMonth, !monthDays.isEmpty {
      object["BYMONTHDAY"] = monthDays.map(\.intValue)
    }
    if let months = rule.monthsOfTheYear, !months.isEmpty {
      object["BYMONTH"] = months.map(\.intValue)
    }
    if let positions = rule.setPositions, !positions.isEmpty {
      object["BYSETPOS"] = positions.map(\.intValue)
    }
    guard JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func rules(from json: String?) throws -> [EKRecurrenceRule]? {
    guard let json = json?.trimmingCharacters(in: .whitespacesAndNewlines), !json.isEmpty
    else { return nil }
    guard let data = json.data(using: .utf8),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rawFreq = object["FREQ"] as? String,
      let frequency = frequency(rawFreq)
    else {
      throw EventKitRecurrenceBridgeError.invalidRule
    }
    let recurrenceEnd: EKRecurrenceEnd? = {
      if let count = intValue(object["COUNT"]), count > 0 {
        return EKRecurrenceEnd(occurrenceCount: count)
      }
      if let until = object["UNTIL"] as? String,
        let date = LorvexDateFormatters.ymd.date(from: until)
      {
        return EKRecurrenceEnd(end: date)
      }
      return nil
    }()
    return [
      EKRecurrenceRule(
        recurrenceWith: frequency,
        interval: max(1, intValue(object["INTERVAL"]) ?? 1),
        daysOfTheWeek: daysOfTheWeek(object["BYDAY"]),
        daysOfTheMonth: nsNumbers(object["BYMONTHDAY"]),
        monthsOfTheYear: nsNumbers(object["BYMONTH"]),
        weeksOfTheYear: nil,
        daysOfTheYear: nil,
        setPositions: nsNumbers(object["BYSETPOS"]),
        end: recurrenceEnd)
    ]
  }

  private static func frequencyString(_ frequency: EKRecurrenceFrequency) -> String {
    switch frequency {
    case .daily: "DAILY"
    case .weekly: "WEEKLY"
    case .monthly: "MONTHLY"
    case .yearly: "YEARLY"
    @unknown default: "DAILY"
    }
  }

  private static func frequency(_ raw: String) -> EKRecurrenceFrequency? {
    switch raw.uppercased() {
    case "DAILY": .daily
    case "WEEKLY": .weekly
    case "MONTHLY": .monthly
    case "YEARLY": .yearly
    default: nil
    }
  }

  private static func dayString(_ day: EKRecurrenceDayOfWeek) -> String {
    let code =
      switch day.dayOfTheWeek {
      case .sunday: "SU"
      case .monday: "MO"
      case .tuesday: "TU"
      case .wednesday: "WE"
      case .thursday: "TH"
      case .friday: "FR"
      case .saturday: "SA"
      @unknown default: "MO"
      }
    return day.weekNumber == 0 ? code : "\(day.weekNumber)\(code)"
  }

  private static func daysOfTheWeek(_ value: Any?) -> [EKRecurrenceDayOfWeek]? {
    guard let values = value as? [String], !values.isEmpty else { return nil }
    let days = values.compactMap(dayOfWeek)
    return days.isEmpty ? nil : days
  }

  private static func dayOfWeek(_ raw: String) -> EKRecurrenceDayOfWeek? {
    let code = String(raw.suffix(2)).uppercased()
    let prefix = raw.dropLast(2)
    let weekNumber = Int(prefix) ?? 0
    let weekday: EKWeekday? =
      switch code {
      case "SU": .sunday
      case "MO": .monday
      case "TU": .tuesday
      case "WE": .wednesday
      case "TH": .thursday
      case "FR": .friday
      case "SA": .saturday
      default: nil
      }
    guard let weekday else { return nil }
    return EKRecurrenceDayOfWeek(weekday, weekNumber: weekNumber)
  }

  private static func nsNumbers(_ value: Any?) -> [NSNumber]? {
    if let ints = value as? [Int], !ints.isEmpty {
      return ints.map(NSNumber.init(value:))
    }
    if let numbers = value as? [NSNumber], !numbers.isEmpty {
      return numbers
    }
    return nil
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber { return number.intValue }
    return nil
  }
}

enum EventKitRecurrenceBridgeError: LocalizedError {
  case invalidRule

  var errorDescription: String? {
    "Invalid EventKit recurrence rule."
  }
}
