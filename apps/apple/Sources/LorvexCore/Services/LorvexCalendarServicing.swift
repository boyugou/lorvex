import Foundation

public struct CalendarEventCreateDraft: Equatable, Sendable {
  public var title: String
  public var startDate: String
  public var endDate: String?
  public var startTime: String?
  public var endTime: String?
  public var allDay: Bool
  public var location: String?
  public var notes: String?
  /// Typed recurrence rule. Serialized to canonical JSON at the service
  /// boundary; storage remains the same canonical JSON TEXT.
  public var recurrence: TaskRecurrenceRule?
  public var timezone: String?
  public var url: String?
  public var color: String?
  public var eventType: String?
  public var personName: String?
  public var attendees: [CalendarEventAttendee]?

  public init(
    title: String,
    startDate: String,
    endDate: String? = nil,
    startTime: String? = nil,
    endTime: String? = nil,
    allDay: Bool = false,
    location: String? = nil,
    notes: String? = nil,
    recurrence: TaskRecurrenceRule? = nil,
    timezone: String? = nil,
    url: String? = nil,
    color: String? = nil,
    eventType: String? = nil,
    personName: String? = nil,
    attendees: [CalendarEventAttendee]? = nil
  ) {
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.startTime = startTime
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.notes = notes
    self.recurrence = recurrence
    self.timezone = timezone
    self.url = url
    self.color = color
    self.eventType = eventType
    self.personName = personName
    self.attendees = attendees
  }
}

public protocol LorvexCalendarServicing: Sendable {
  func loadCalendarTimeline(from: String, to: String) async throws -> CalendarTimelineSnapshot

  /// The single canonical Lorvex event with `id`, or nil when none exists.
  /// Reads only the `calendar_events` root (no provider blend), so it doubles as
  /// an id-existence probe for the import path.
  func getCalendarEvent(id: CalendarTimelineEvent.ID) async throws -> CalendarTimelineEvent?

  /// The canonical event projected for an external calendar adapter. For a
  /// recurring segment this clips recurrence at the next durable series
  /// cutover without mutating the raw recurrence stored in Lorvex.
  func getCalendarEventForExternalProjection(
    id: CalendarTimelineEvent.ID
  ) async throws -> CalendarTimelineEvent?

  /// Creates a canonical calendar event. `endDate` (YYYY-MM-DD) spans the event
  /// across multiple days when it differs from `startDate`; pass nil for a
  /// single-day event. When `allDay` is true the times are ignored.
  func createCalendarEvent(
    title: String,
    startDate: String,
    endDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String?,
    recurrence: TaskRecurrenceRule?,
    timezone: String?,
    url: String?,
    color: String?,
    eventType: String?,
    personName: String?,
    attendees: [CalendarEventAttendee]?
  ) async throws -> CalendarTimelineEvent

  func batchCreateCalendarEvents(_ drafts: [CalendarEventCreateDraft]) async throws
    -> [CalendarTimelineEvent]

  /// Patches an existing calendar event. Each nil field is left untouched. A
  /// non-nil `endDate` (YYYY-MM-DD) sets the multi-day span; nil leaves the
  /// existing end date unchanged.
  func updateCalendarEvent(
    id: CalendarTimelineEvent.ID,
    title: String?,
    startDate: String?,
    endDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool?,
    location: String?,
    notes: String?,
    recurrence: CalendarEventRecurrencePatch,
    timezone: String?,
    url: String?,
    color: String?,
    eventType: String?,
    personName: String?,
    attendees: CalendarEventAttendeesPatch
  ) async throws -> CalendarTimelineEvent

  /// Deletes the calendar event with `id`, returning the removed event (its
  /// pre-delete field values) or nil when no such row exists. A nil return marks
  /// a no-op the caller reports honestly rather than as a phantom deletion; the
  /// `ai_changelog` row is written only when a row is actually removed.
  @discardableResult
  func deleteCalendarEvent(id: CalendarTimelineEvent.ID) async throws -> CalendarTimelineEvent?

  /// Id-preserving idempotent upsert for data import/restore. Inserts the
  /// canonical event at the supplied `id`, or overwrites the existing row when
  /// that id is already present. No version gate: an import always wins, so
  /// re-importing the same payload overwrites in place rather than duplicating.
  /// When `allDay` is true, `startTime` / `endTime` are forced to nil to satisfy
  /// the `all_day = 0 OR (start_time IS NULL AND end_time IS NULL)` CHECK.
  /// `eventType` defaults to `event`. Newer export payloads preserve the raw
  /// calendar row's optional metadata, recurrence, attendees, and scoped
  /// occurrence-decision linkage. Restore mints fresh sync-register clocks;
  /// backup data carries final state, not sync provenance.
  func importCalendarEvent(
    id: CalendarTimelineEvent.ID,
    title: String,
    startDate: String,
    startTime: String?,
    endDate: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String?,
    url: String?,
    color: String?,
    eventType: String?,
    personName: String?,
    attendees: [CalendarEventAttendee]?,
    timezone: String?,
    recurrence: String?,
    seriesId: String?,
    recurrenceInstanceDate: String?,
    occurrenceState: String?,
    recurrenceGeneration: String?,
    seriesCutoverId: String?
  ) async throws -> CalendarTimelineEvent

  /// Search calendar events by title substring across Lorvex-owned and
  /// provider-mirror events, ordered by (start_date, start_time NULLS LAST, id).
  /// Returns up to `limit` events starting at `offset` in that order, so a
  /// caller pages by fetching `limit + 1` to detect whether more remain.
  func searchCalendarEvents(
    query: String,
    from: String?,
    to: String?,
    limit: Int?,
    offset: Int
  ) async throws -> [CalendarTimelineEvent]

  func linkTaskToProviderEvent(
    taskID: LorvexTask.ID,
    providerEventID: String,
    providerSource: String
  ) async throws -> TaskCalendarEventLink

  /// Removes the task↔provider-event link(s) for `taskID`/`providerEventID`,
  /// returning whether any link was actually removed. A false return marks a
  /// no-op (no such link) the caller reports honestly; the `ai_changelog` row is
  /// written only when a link is removed.
  @discardableResult
  func unlinkTaskFromProviderEvent(
    taskID: LorvexTask.ID,
    providerEventID: String
  ) async throws -> Bool

  func getLinkedEventsForTask(taskID: LorvexTask.ID) async throws -> [CalendarTimelineEvent]

  func getLinkedTasksForEvent(eventID: CalendarTimelineEvent.ID) async throws -> [LorvexTask]

  /// Store a cancellation decision for one recurring-calendar occurrence.
  func addCalendarEventException(
    eventID: CalendarTimelineEvent.ID, date: String
  ) async throws -> CalendarTimelineEvent

  /// Restore a previously skipped occurrence by storing an inherit decision.
  /// Returns the updated event.
  func removeCalendarEventException(
    eventID: CalendarTimelineEvent.ID, date: String
  ) async throws -> CalendarTimelineEvent

  /// Scoped edit of a recurring calendar event (all_in_series / this_only / this_and_following).
  func editScopedCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    occurrenceDate: String,
    scope: String,
    updates: ScopedCalendarEventUpdates
  ) async throws -> ScopedCalendarEventEditResult

  /// Scoped delete of a recurring calendar event (all_in_series / this_only / this_and_following).
  func deleteScopedCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    occurrenceDate: String,
    scope: String
  ) async throws -> ScopedCalendarEventDeleteResult

  /// Exports calendar events within the given date range as an RFC 5545 ICS string.
  ///
  /// Both `from` and `to` are inclusive `yyyy-MM-dd` date strings. When nil,
  /// `from` defaults to today and `to` defaults to 30 days from today. All
  /// canonical Lorvex events in the range are included; there is no per-calendar
  /// filter because Lorvex treats the event store as a single calendar namespace.
  func exportCalendarICS(from: String?, to: String?) async throws -> String
}

extension LorvexCalendarServicing {
  /// Offset-free convenience for callers that only want the first page.
  public func searchCalendarEvents(
    query: String,
    from: String?,
    to: String?,
    limit: Int?
  ) async throws -> [CalendarTimelineEvent] {
    try await searchCalendarEvents(query: query, from: from, to: to, limit: limit, offset: 0)
  }
}

public extension LorvexCalendarServicing {
  func importCalendarEvent(
    id: CalendarTimelineEvent.ID,
    title: String,
    startDate: String,
    startTime: String?,
    endDate: String?,
    endTime: String?,
    allDay: Bool,
    location: String?
  ) async throws -> CalendarTimelineEvent {
    try await importCalendarEvent(
      id: id,
      title: title,
      startDate: startDate,
      startTime: startTime,
      endDate: endDate,
      endTime: endTime,
      allDay: allDay,
      location: location,
      notes: nil,
      url: nil,
      color: nil,
      eventType: nil,
      personName: nil,
      attendees: nil,
      timezone: nil,
      recurrence: nil,
      seriesId: nil,
      recurrenceInstanceDate: nil,
      occurrenceState: nil,
      recurrenceGeneration: nil,
      seriesCutoverId: nil)
  }

  func createCalendarEvent(
    title: String,
    startDate: String,
    endDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String?
  ) async throws -> CalendarTimelineEvent {
    try await createCalendarEvent(
      title: title,
      startDate: startDate,
      endDate: endDate,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      location: location,
      notes: notes,
      recurrence: nil,
      timezone: nil,
      url: nil,
      color: nil,
      eventType: nil,
      personName: nil,
      attendees: nil)
  }

  func updateCalendarEvent(
    id: CalendarTimelineEvent.ID,
    title: String?,
    startDate: String?,
    endDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool?,
    location: String?,
    notes: String?
  ) async throws -> CalendarTimelineEvent {
    try await updateCalendarEvent(
      id: id,
      title: title,
      startDate: startDate,
      endDate: endDate,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      location: location,
      notes: notes,
      recurrence: .unset,
      timezone: nil,
      url: nil,
      color: nil,
      eventType: nil,
      personName: nil,
      attendees: .unset)
  }
}
