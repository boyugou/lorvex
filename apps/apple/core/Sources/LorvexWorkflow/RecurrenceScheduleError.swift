import Foundation

/// A change to a repeating task's schedule that its series refuses.
///
/// ``description`` is the English sentence the MCP boundary returns under the
/// `validation` code; the app recognizes each case and words it in the
/// interface language.
public enum RecurrenceScheduleError: Error, Equatable, Sendable, CustomStringConvertible,
  LocalizedError
{
  /// Moving the occurrence `taskId` to `date` (`YYYY-MM-DD`) was refused because
  /// another occurrence of the same series already falls on that day, and a
  /// series holds one occurrence per day.
  case occurrenceDateTaken(taskId: String, date: String)

  public var description: String {
    switch self {
    case let .occurrenceDateTaken(_, date):
      return
        "Another occurrence of this repeating task already falls on \(date). "
        + "Choose a different date."
    }
  }

  public var errorDescription: String? { description }
}
