@preconcurrency import EventKit
import Foundation

/// Abstraction over EKEventStore for the subset of operations used by
/// `LiveEventKitAccess` (event read/write + Lorvex-calendar management).
/// Enables fake injection in tests without touching the real calendar database.
///
/// `authorizationStatus(for:)` is intentionally omitted — it is a class method
/// on EKEventStore and cannot be expressed as an instance requirement.
/// Use `EKEventStore.authorizationStatus(for:)` directly at the call site.
protocol EventKitEventStoring: Sendable {
  func requestFullAccessToEvents() async throws -> Bool
  func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws
  func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws
  func events(matching predicate: NSPredicate) -> [EKEvent]
  func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]?)
    -> NSPredicate
  func calendarItem(withIdentifier identifier: String) -> EKCalendarItem?
  var defaultCalendarForNewEvents: EKCalendar? { get }
  func makeEvent() -> EKEvent

  // Calendar management — used to create + address the isolated "Lorvex"
  // calendar that Lorvex-originated write-back targets.
  func calendar(withIdentifier identifier: String) -> EKCalendar?
  func makeCalendar() -> EKCalendar
  func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws
  func eventCalendars() -> [EKCalendar]
  var preferredCalendarSource: EKSource? { get }

  /// Refresh the store's cached state. EKEventStore caches the calendar
  /// database (and its effective authorization) at creation, so a store made
  /// before the user granted access keeps reading an empty/denied snapshot for
  /// the rest of the session; calling `reset()` after a grant makes it see the
  /// newly-authorized calendars without an app relaunch.
  func reset()
}

extension EKEventStore: EventKitEventStoring {
  func makeEvent() -> EKEvent {
    EKEvent(eventStore: self)
  }

  func makeCalendar() -> EKCalendar {
    EKCalendar(for: .event, eventStore: self)
  }

  func eventCalendars() -> [EKCalendar] {
    sources.flatMap { $0.calendars(for: .event) }
  }

  /// Prefer the iCloud (CalDAV) source so the Lorvex calendar syncs across the
  /// user's devices; fall back to the on-device local source, then any source.
  var preferredCalendarSource: EKSource? {
    sources.first { $0.sourceType == .calDAV }
      ?? sources.first { $0.sourceType == .local }
      ?? defaultCalendarForNewEvents?.source
      ?? sources.first
  }
}
