import Foundation

/// A habit reminder change the habit's existing reminder slots refuse.
///
/// ``description`` is the English sentence the MCP boundary returns under the
/// `validation` code; the app recognizes the case and words it in the
/// interface language.
public enum HabitReminderError: Error, Equatable, Sendable, CustomStringConvertible,
  LocalizedError
{
  /// The habit `habitId` already has a reminder slot at `time` (`HH:MM`); a
  /// habit holds at most one slot per time.
  case timeTaken(habitId: String, time: String)

  public var description: String {
    switch self {
    case let .timeTaken(habitId, time):
      return "habit '\(habitId)' already has a reminder slot at \(time)"
    }
  }

  public var errorDescription: String? { description }
}
