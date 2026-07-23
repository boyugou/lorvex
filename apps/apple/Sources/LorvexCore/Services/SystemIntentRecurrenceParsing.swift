import Foundation

extension LorvexSystemIntentRunner {
  public static func parsedRecurrenceWeekdays(_ value: String?) throws -> [String]? {
    guard let value else { return nil }
    let days = value
      .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
      .filter { !$0.isEmpty }
    guard !days.isEmpty else { return nil }
    let allowed = Set(["MO", "TU", "WE", "TH", "FR", "SA", "SU"])
    guard days.allSatisfy({ allowed.contains($0) }) else {
      throw LorvexCoreError.validation(
        field: "weekdays", message: "Weekdays must use MO TU WE TH FR SA SU.")
    }
    return days
  }

  public static func validatedRecurrenceInterval(_ value: Int?) throws -> Int? {
    guard let value else { return nil }
    guard value > 0 else {
      throw LorvexCoreError.validation(
        field: "interval", message: "Recurrence interval must be greater than zero.")
    }
    return value
  }

  public static func validatedRecurrenceCount(_ value: Int?) throws -> Int? {
    guard let value else { return nil }
    guard value > 0 else {
      throw LorvexCoreError.validation(
        field: "count", message: "Recurrence count must be greater than zero.")
    }
    return value
  }

  public static func validatedRecurrenceDate(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(
        field: "date", message: "A recurrence date is required.")
    }
    return trimmed
  }
}
