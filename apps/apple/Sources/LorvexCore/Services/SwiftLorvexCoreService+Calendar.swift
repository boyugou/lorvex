import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// `LorvexCalendarServicing` over the pure-Swift core.
///
/// Event CRUD funnels through the `CalendarEventCreate` / `CalendarEventUpdate`
/// workflow orchestrators (via the `+WriteSurface` adapter); timeline and search
/// reads go through `CalendarTimelineQueries`. ICS export composes
/// `CalendarIcsEventFields` from the stored rows in range and emits via
/// `exportCalendarIcs`. Event mapping reuses `SwiftLorvexCalendarDeserializers`.
///
/// The timeline blends canonical Lorvex events with any provider
/// (EventKit-mirrored) events present in `provider_calendar_events`, gated by
/// each scope's availability. The four task↔provider-event link methods are
/// implemented in `SwiftLorvexCoreService+ProviderLinks`, operating on the
/// `task_provider_event_links` + `provider_calendar_events` tables.
extension SwiftLorvexCoreService {
  public func getCalendarEvent(id: CalendarTimelineEvent.ID) async throws -> CalendarTimelineEvent?
  {
    try read { db in
      try CalendarTimelineQueries.getCalendarEvent(db, id: id)
        .map(SwiftLorvexCalendarDeserializers.event)
    }
  }

  public func createCalendarEvent(
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
  ) async throws -> CalendarTimelineEvent {
    try withWrite { db, hlc, deviceId in
      // Stamp the new event in the configured Lorvex timezone (falling back to
      // the device zone), matching how every read path anchors — not the raw
      // device zone, which would mis-stamp a user whose preference differs.
      let input = CalendarEventCreateInput(
        title: title,
        recurrence: (recurrence?.canonicalRecurrenceJSON()).trimmedNilIfEmpty,
        timezone: try timezone.trimmedNilIfEmpty ?? WorkflowTimezone.anchoredTimezoneName(db),
        startDate: startDate,
        startTime: startTime, endDate: endDate, endTime: endTime, allDay: allDay,
        description: notes,
        location: location,
        url: url.trimmedNilIfEmpty,
        color: color.trimmedNilIfEmpty,
        eventType: try Self.calendarEventType(eventType),
        personName: personName.trimmedNilIfEmpty,
        attendees: Self.attendeeInputs(attendees))
      let result = try CalendarEventCreate.createCalendarEvent(
        db, hlc: hlc, eventId: EntityID.newEntityIDString(), input: input)
      try self.enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .calendarEvent, entityId: result.eventId)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opUpsert, entityType: EntityName.calendarEvent,
          entityId: result.eventId, summary: result.summary, after: result.event),
        deviceId: deviceId)
      return try SwiftLorvexCalendarDeserializers.event(result.event)
    }
  }

  public func batchCreateCalendarEvents(_ drafts: [CalendarEventCreateDraft]) async throws
    -> [CalendarTimelineEvent]
  {
    try withWrite { db, hlc, deviceId in
      guard !drafts.isEmpty else {
        throw LorvexCoreError.validation(
          field: nil, message: "At least one calendar event is required.")
      }
      var created: [CalendarTimelineEvent] = []
      var createdIds: [String] = []
      created.reserveCapacity(drafts.count)
      createdIds.reserveCapacity(drafts.count)
      for draft in drafts {
        let input = CalendarEventCreateInput(
          title: draft.title,
          recurrence: (draft.recurrence?.canonicalRecurrenceJSON()).trimmedNilIfEmpty,
          timezone: try draft.timezone.trimmedNilIfEmpty
            ?? WorkflowTimezone.anchoredTimezoneName(db),
          startDate: draft.startDate,
          startTime: draft.allDay ? nil : draft.startTime,
          endDate: draft.endDate,
          endTime: draft.allDay ? nil : draft.endTime,
          allDay: draft.allDay,
          description: draft.notes,
          location: draft.location,
          url: draft.url.trimmedNilIfEmpty,
          color: draft.color.trimmedNilIfEmpty,
          eventType: try Self.calendarEventType(draft.eventType),
          personName: draft.personName.trimmedNilIfEmpty,
          attendees: Self.attendeeInputs(draft.attendees))
        let result = try CalendarEventCreate.createCalendarEvent(
          db, hlc: hlc, eventId: EntityID.newEntityIDString(), input: input)
        try self.enqueueUpsert(
          db, hlc: hlc, deviceId: deviceId, kind: .calendarEvent, entityId: result.eventId)
        createdIds.append(result.eventId)
        created.append(try SwiftLorvexCalendarDeserializers.event(result.event))
      }
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "batch_create_calendar_events",
          entityId: createdIds.first,
          entityIds: createdIds,
          summary: "Created \(created.count) calendar event\(created.count == 1 ? "" : "s")"),
        deviceId: deviceId)
      return created
    }
  }

  public func updateCalendarEvent(
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
  ) async throws -> CalendarTimelineEvent {
    try withWrite { db, hlc, deviceId in
      guard let beforeRow = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: id) else {
        throw LorvexCoreError.notFound(entity: .calendarEvent, id: id)
      }
      if beforeRow.seriesCutoverId != nil || beforeRow.seriesId != nil {
        guard
          let ownership = try CalendarTimelineQueries.getCalendarSeriesOwnership(
            db, eventId: id), ownership.isActive,
          beforeRow.recurrenceInstanceDate.map({
            ownership.owns(recurrenceInstanceDate: $0)
          }) ?? true
        else {
          throw LorvexCoreError.validation(
            field: "id", message: "The addressed calendar-series value is no longer active.")
        }
      }
      guard let before = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: id) else {
        throw LorvexCoreError.notFound(entity: .calendarEvent, id: id)
      }
      let existing = CalendarUpdateExisting(
        startDate: beforeRow.startDate.asString,
        startTime: beforeRow.startTime?.asString,
        endDate: beforeRow.endDate?.asString,
        endTime: beforeRow.endTime?.asString,
        allDay: beforeRow.allDay,
        timezone: beforeRow.timezone,
        recurrence: beforeRow.recurrence)
      let input = CalendarEventUpdateInput(
        id: id,
        title: title,
        recurrence: try Self.patchRecurrence(recurrence),
        timezone: Self.patchString(timezone),
        startDate: startDate.map { Patch.set($0) } ?? .unset,
        startTime: startTime.map { Patch.set($0) } ?? .unset,
        endDate: endDate.map { Patch.set($0) } ?? .unset,
        endTime: endTime.map { Patch.set($0) } ?? .unset,
        allDay: allDay,
        description: notes.map { Patch.set($0) } ?? .unset,
        location: location.map { Patch.set($0) } ?? .unset,
        url: Self.patchString(url),
        color: Self.patchString(color),
        eventType: try Self.patchEventType(eventType),
        personName: Self.patchString(personName),
        attendees: Self.patchAttendees(attendees))
      let result = try CalendarEventUpdate.updateCalendarEvent(
        db, hlc: hlc, input: input, before: before,
        beforeRecurrence: beforeRow.recurrence, existing: existing)
      try self.enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .calendarEvent, entityId: result.eventId)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "update", entityType: EntityName.calendarEvent, entityId: result.eventId,
          summary: result.summary, before: result.before, after: result.event),
        deviceId: deviceId)
      return try SwiftLorvexCalendarDeserializers.event(result.event)
    }
  }

  @discardableResult
  public func deleteCalendarEvent(id: CalendarTimelineEvent.ID) async throws
    -> CalendarTimelineEvent?
  {
    try withWrite { db, hlc, deviceId -> CalendarTimelineEvent? in
      guard let row = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: id) else {
        return nil
      }
      let previous = SwiftLorvexCalendarDeserializers.event(row)
      // A visible replacement is the materialized value of an occurrence
      // decision. Generic delete must transition that same register to
      // `cancelled`; physically deleting it would let the master occurrence
      // reappear and would race a remote replacement upsert.
      if row.seriesId != nil, let occurrenceDate = row.recurrenceInstanceDate {
        _ = try self.cancelOccurrenceDecisionInline(
          db, hlc: hlc, deviceId: deviceId,
          eventID: row.id, occurrenceDate: occurrenceDate)
        return previous
      }
      if let cutoverId = row.seriesCutoverId {
        guard
          let ownership = try CalendarTimelineQueries.getCalendarSeriesOwnership(
            db, eventId: row.id), ownership.isActive,
          ownership.segmentCutoverId == cutoverId,
          let cutoverDate = ownership.lowerBoundCutoverDate
        else {
          return nil
        }
        _ = try self.upsertCalendarSeriesCutover(
          db, hlc: hlc, deviceId: deviceId,
          lineageRootId: ownership.lineageRootId,
          cutoverDate: cutoverDate,
          state: .deleted,
          operation: "delete_calendar_series_segment")
      }
      let deleted = try self.deleteCalendarEventRowInline(
        db, hlc: hlc, deviceId: deviceId, id: id)
      // A master tombstone makes every linked decision invisible regardless of
      // arrival order. Remove locally-known rows as bounded storage cleanup.
      try self.sweepSeriesDecisions(
        db, hlc: hlc, deviceId: deviceId, seriesId: id, scope: .all)
      return deleted ? previous : nil
    }
  }

  public func addCalendarEventException(
    eventID: CalendarTimelineEvent.ID, date: String
  ) async throws -> CalendarTimelineEvent {
    let result = try deleteThisOnlyCalendarEvent(
      eventID: eventID, occurrenceDate: date)
    guard let event = result.event else {
      throw LorvexCoreError.notFound(entity: .calendarEvent, id: eventID)
    }
    return event
  }

  public func removeCalendarEventException(
    eventID: CalendarTimelineEvent.ID, date: String
  ) async throws -> CalendarTimelineEvent {
    try restoreThisOnlyCalendarEvent(eventID: eventID, occurrenceDate: date)
  }

}
