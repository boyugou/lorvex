import Foundation

/// Locale-aware display label for a stored `HH:MM` time-of-day string.
///
/// Storage and the domain layer use 24-hour `HH:MM`; the UI must respect the
/// user's system clock preference — "9:00 AM" where the device is 12-hour,
/// "09:00" where it is 24-hour. Every schedule / focus-block time display on
/// every surface (macOS and mobile) goes through this one helper so the format
/// is consistent and native everywhere. Returns the input unchanged if it is
/// not a parseable `HH:MM`.
public func lorvexClockTimeLabel(_ hourMinute: String) -> String {
  let trimmed = hourMinute.trimmingCharacters(in: .whitespaces)
  guard let date = LorvexDateFormatters.hourMinute.date(from: trimmed) else {
    return hourMinute
  }
  return date.formatted(date: .omitted, time: .shortened)
}
