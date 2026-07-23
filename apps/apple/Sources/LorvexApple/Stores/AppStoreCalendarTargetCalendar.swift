import Foundation
import LorvexCore

// EventKit calendar identity for the calendar surface: which calendar the draft
// event is filed into, which calendars can be chosen, and which one a given
// event's mirror lives in.
extension AppStore {
  /// Resolve the fine-grained origin calendar (title + account) of a provider
  /// (system-calendar) event for the inspector, matching the calendar-filter
  /// settings list. The timeline cache collapses every system calendar into one
  /// device scope, so this reaches back to EventKit live. Nil for Lorvex-owned
  /// (editable) events, non-EventKit ids, or when the integration is unavailable.
  func calendarEventSource(for event: CalendarTimelineEvent) async -> EventKitEventSource? {
    guard !event.editable, let eventKitCoordinator else { return nil }
    return await eventKitCoordinator.eventSource(
      forTimelineID: event.eventID, dayHint: event.startDate)
  }

  /// The writable EventKit calendar the draft event is filed into, by
  /// `calendarIdentifier`; nil selects the dedicated Lorvex calendar. Bound by
  /// the event form's calendar picker.
  var draftCalendarTargetCalendarID: String? {
    get { calendarStorage.draftCalendarTargetCalendarID }
    set { calendarStorage.draftCalendarTargetCalendarID = newValue }
  }

  /// The draft's calendar choice as an ``EventKitWriteTarget`` for the write
  /// path: a concrete id targets that calendar, nil the dedicated Lorvex one.
  var draftEventKitWriteTarget: EventKitWriteTarget {
    draftCalendarTargetCalendarID.map(EventKitWriteTarget.calendar(id:)) ?? .lorvexDefault
  }

  /// Readable EventKit calendars for the mirror include/exclude settings list.
  func loadEventKitCalendars() async throws -> [EventKitCalendarDescriptor] {
    guard let eventKitCoordinator else { return [] }
    return try await eventKitCoordinator.availableCalendars()
  }

  /// Writable EventKit calendars for the event form's calendar picker (each with
  /// its color), excluding the dedicated Lorvex calendar (the picker's default).
  /// Empty when the integration is disabled or access is not granted.
  func loadWritableEventKitCalendars() async throws -> [EventKitCalendarDescriptor] {
    guard let eventKitCoordinator else { return [] }
    return try await eventKitCoordinator.writableCalendars()
  }

  /// Preselect the edit form's calendar picker to the calendar `event`'s mirror
  /// currently lives in, resolved live from EventKit (the choice lives only in
  /// the mirror, not the canonical core event). Leaves the default (nil) for a
  /// mirror in the Lorvex calendar, an unresolvable mirror, or a non-editable
  /// event. Called after ``prepareCalendarDraft(for:)`` when opening the edit
  /// sheet; nil-safe when the integration is unavailable.
  func resolveDraftTargetCalendar(for event: CalendarTimelineEvent) async {
    guard event.editable, let eventKitCoordinator else { return }
    // Natural occurrences are represented by the recurring master in EventKit;
    // a materialized replacement is a separate one-off keyed by its own id.
    let mirrorID = event.occurrenceState == .replacement ? event.id : event.eventID
    let resolved = await eventKitCoordinator.lorvexEventCalendarID(lorvexEventID: mirrorID)
    // Guard against a stale resolution landing after the user switched to a
    // different event's draft (or picked a calendar manually in the meantime).
    guard selectedCalendarEventID == event.id else { return }
    draftCalendarTargetCalendarID = resolved
  }
}
