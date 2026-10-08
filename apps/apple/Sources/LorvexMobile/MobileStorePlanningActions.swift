import Foundation
import LorvexCore

extension MobileStore {
  func loadPlanningSnapshotsPreservingLoadedState(date: String) async -> (any Error)? {
    let endDate = Self.calendarEndDateString(from: date)
    // Refresh the EventKit mirror for the window before reading the timeline, so
    // today's external system-calendar events are present both in the Today
    // schedule and for Suggest Times, which reads the same
    // `provider_calendar_events` mirror and would otherwise only see what the
    // Calendar surface or the change observer last ingested. A no-op when
    // calendar integration is off, and it never prompts for access.
    await ingestEventKitWindow(fromDay: date, throughDay: endDate)

    // Load the calendar for the window the user is viewing, not a fixed today
    // window: a refresh (foreground, CloudKit push, day-change) must not snap a
    // far week back to today and silently empty the viewed days. The window is
    // the one the calendar surface asked for even while its own load is still
    // in flight: this refresh takes the next `calendarTimelineLoadToken`, which
    // discards that load, so it has to load the same window or the days the
    // surface lists would come up empty. A window other than today's is
    // ingested too so its external events are current before the read.
    let calendarFrom = calendarWindowToReload?.from ?? date
    let calendarTo = calendarWindowToReload?.to ?? endDate
    if calendarFrom != date || calendarTo != endDate {
      await ingestEventKitWindow(fromDay: calendarFrom, throughDay: calendarTo)
    }
    calendarTimelineLoadToken &+= 1
    let calendarToken = calendarTimelineLoadToken

    async let loadedLists = capturePlanningLoad { try await core.loadLists() }
    async let loadedHabits = capturePlanningLoad { try await core.loadHabits(date: date) }
    async let loadedCalendar = capturePlanningLoad {
      try await core.loadCalendarTimeline(from: calendarFrom, to: calendarTo)
    }
    async let loadedScheduledTasks = capturePlanningLoad {
      try await core.getScheduledTasks(
        from: calendarFrom,
        to: calendarTo,
        limit: CalendarGridModel.windowTaskLimit)
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

    // A newer window load (a page turn mid-refresh) superseded this one; skip the
    // stale commit so its window isn't clobbered — but still surface any error.
    let calendarCurrent = calendarToken == calendarTimelineLoadToken
    switch results.2 {
    case .success(let loadedCalendar):
      if calendarCurrent { calendarTimeline = loadedCalendar }
    case .failure(let error):
      firstError = firstError ?? error
    }

    switch results.3 {
    case .success(let loadedScheduledTasks):
      if calendarCurrent { calendarScheduledTasks = loadedScheduledTasks }
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
