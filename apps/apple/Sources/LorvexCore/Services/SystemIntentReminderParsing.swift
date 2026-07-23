import Foundation

extension LorvexSystemIntentRunner {
  public static func validatedReminderTimestamp(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(
        field: "reminder_at", message: "A reminder timestamp is required.")
    }
    return trimmed
  }

  public static func validatedReminderID(_ value: TaskReminder.ID) throws -> TaskReminder.ID {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(
        field: "reminder_id", message: "A reminder ID is required.")
    }
    return trimmed
  }

  public static func validatedReminderLimit(_ value: Int?) throws -> Int {
    let limit = value ?? 50
    guard limit > 0 else {
      throw LorvexCoreError.validation(
        field: "limit", message: "Reminder limit must be greater than zero.")
    }
    return min(limit, 500)
  }

  public static func validatedHoursAhead(_ value: Int?) throws -> Int {
    let hours = value ?? 24
    guard hours > 0 else {
      throw LorvexCoreError.validation(
        field: "horizon", message: "Reminder horizon must be greater than zero.")
    }
    return hours
  }
}
