import Foundation
import LorvexCore

extension MobileStore {
  func loadPlanningSnapshotsPreservingLoadedState(date: String) async -> (any Error)? {
    let endDate = Self.calendarEndDateString(from: date)
    // Refresh the EventKit mirror for the window before reading the timeline, so
    // today's external system-calendar events are present both in the Today
    // schedule and for the focus scheduler — which reads the same
    // `provider_calendar_events` mirror and would otherwise only see what the
    // Calendar surface or the change observer last ingested. A no-op when
    // calendar integration is off, and it never prompts for access.
    await ingestEventKitWindow(fromDay: date, throughDay: endDate)
    async let loadedLists = capturePlanningLoad { try await core.loadLists() }
    async let loadedHabits = capturePlanningLoad { try await core.loadHabits(date: date) }
    async let loadedCalendar = capturePlanningLoad {
      try await core.loadCalendarTimeline(from: date, to: endDate)
    }
    async let loadedScheduledTasks = capturePlanningLoad {
      try await core.getScheduledTasks(
        from: date,
        to: endDate,
        limit: 500)
    }

    let results = await (loadedLists, loadedHabits, loadedCalendar, loadedScheduledTasks)
    var firstError: (any Error)?

    switch results.0 {
    case .success(let loadedLists):
      lists = loadedLists
    case .failure(let error):
      firstError = firstError ?? error
    }

    switch results.1 {
    case .success(let loadedHabits):
      habits = loadedHabits
    case .failure(let error):
      firstError = firstError ?? error
    }

    switch results.2 {
    case .success(let loadedCalendar):
      calendarTimeline = loadedCalendar
    case .failure(let error):
      firstError = firstError ?? error
    }

    switch results.3 {
    case .success(let loadedScheduledTasks):
      calendarScheduledTasks = loadedScheduledTasks
    case .failure(let error):
      firstError = firstError ?? error
    }

    return firstError
  }

  private func capturePlanningLoad<T>(_ operation: () async throws -> T) async -> Result<T, any Error> {
    do {
      return .success(try await operation())
    } catch {
      return .failure(error)
    }
  }

  nonisolated static func calendarEndDateString(from date: String) -> String {
    let formatter = LorvexDateFormatters.ymdUTC
    guard let parsed = formatter.date(from: date),
      let end = formatter.calendar.date(byAdding: .day, value: 14, to: parsed)
    else {
      return date
    }
    return formatter.string(from: end)
  }

  nonisolated static var ymdFormatter: DateFormatter { LorvexDateFormatters.ymd }

  nonisolated static var hmFormatter: DateFormatter { LorvexDateFormatters.hourMinute }
}
