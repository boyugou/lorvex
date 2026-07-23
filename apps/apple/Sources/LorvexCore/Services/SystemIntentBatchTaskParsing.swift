import Foundation

extension LorvexSystemIntentRunner {
  public static func parsedTaskTitleList(_ value: String) throws -> [String] {
    let titles = value
      .split(whereSeparator: { $0 == "," || $0 == "\n" })
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !titles.isEmpty else {
      throw LorvexCoreError.validation(
        field: "titles", message: "At least one task title is required.")
    }
    return titles
  }

  public static func parsedPriority(_ value: Int?) throws -> LorvexTask.Priority {
    switch value ?? 2 {
    case 1: .p1
    case 2: .p2
    case 3: .p3
    default:
      throw LorvexCoreError.validation(
        field: "priority", message: "Task priority must be 1, 2, or 3.")
    }
  }

  public static func parsedIntentDate(_ value: String) throws -> Date {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: "date", message: "A date is required.")
    }
    let formatter = LorvexDateFormatters.ymdUTC
    guard let date = formatter.date(from: trimmed) else {
      throw LorvexCoreError.validation(field: "date", message: "Dates must use yyyy-MM-dd.")
    }
    return date
  }
}
