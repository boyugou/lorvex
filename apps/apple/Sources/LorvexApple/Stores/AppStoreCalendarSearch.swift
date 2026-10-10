import Foundation
import LorvexCore

extension AppStore {
  /// The most events one calendar search returns. A query broad enough to
  /// match more is not a lookup anyone reads to the end.
  static let calendarSearchLimit = 500

  /// Searches every calendar event for `query`, not only the ones in the
  /// loaded window, and returns them as the days the results list shows
  /// (``CalendarSearchDay/days(for:todayKey:)``). The query matches the start
  /// of words in an event's title, notes, and location. A blank query finds
  /// nothing; a failed read is shown to the user and finds nothing.
  func searchCalendarDays(matching query: String) async -> [CalendarSearchDay] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    do {
      let events = try await core.searchCalendarEvents(
        query: trimmed, from: nil, to: nil, limit: Self.calendarSearchLimit)
      return CalendarSearchDay.days(for: events, todayKey: logicalTodayDateString)
    } catch {
      await presentUserFacingError(error)
      return []
    }
  }
}
