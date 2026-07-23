import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension SwiftLorvexCoreService {
  public func linkTaskToProviderEvent(
    taskID: LorvexTask.ID,
    providerEventID: String,
    providerSource: String
  ) async throws -> TaskCalendarEventLink {
    let fields = try Self.providerLinkFields(
      providerSource: providerSource,
      providerEventID: providerEventID
    )
    let link = try withWrite { db, _, deviceId in
      guard try TaskRepo.Read.taskExistsActive(db, taskId: TaskId(trusted: taskID)) else {
        throw LorvexCoreError.taskNotFound
      }
      guard try Self.providerEventIsLinkable(db, fields: fields) else {
        throw LorvexCoreError.unsupportedOperation(
          "Provider event '\(providerEventID)' is not available. Refresh/search calendar events first, then link using a returned event id.")
      }
      let link = try ProviderRepo.upsertProviderEventLink(
        db,
        taskId: TaskId(trusted: taskID),
        providerKind: fields.providerKind,
        providerScope: fields.providerScope,
        providerEventKey: fields.providerEventKey
      )
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opUpsert,
          entityType: EntityName.task,
          entityId: taskID,
          // Provider mirrors and links are strictly device-local. The audit row
          // itself syncs, so its cloud projection must not include a provider
          // scope, external event key, title, or any other EventKit detail.
          summary: "Changed a device-local calendar link for task \(taskID)."
        ),
        deviceId: deviceId
      )
      return link
    }
    return Self.calendarEventLink(from: link)
  }

  @discardableResult
  public func unlinkTaskFromProviderEvent(
    taskID: LorvexTask.ID,
    providerEventID: String
  ) async throws -> Bool {
    let fields = try Self.providerEventLookupFields(providerEventID: providerEventID)
    return try withWrite { db, _, deviceId in
      if let fields {
        return try self.unlinkKnownProviderEvent(
          db, taskID: taskID, fields: fields, deviceId: deviceId)
      } else {
        return try self.unlinkProviderEventByKey(
          db, taskID: taskID, providerEventID: providerEventID, deviceId: deviceId)
      }
    }
  }

  public func getLinkedEventsForTask(taskID: LorvexTask.ID) async throws -> [CalendarTimelineEvent] {
    try read { db in
      var events = try Self.linkedCanonicalEvents(db, taskID: taskID)
      // Honor the effective calendar AI-access tier (read in the same
      // transaction, fail closed on a malformed value) so a link can't become a
      // side channel that leaks provider detail the tier forbids: `off` exposes
      // no provider events at all, and `busy_only` exposes occupancy only with
      // detail fields redacted — mirroring the timeline / search gate.
      let accessMode = try DeviceStateRepo.readCalendarAiAccessMode(db)
      guard accessMode.includesProvider else { return events }
      // Surface only events whose provider scope is still enabled and has
      // refreshed at least once — the same gate the calendar timeline applies —
      // so a link into a disabled or permission-revoked scope can't keep leaking
      // that event's details after the user pulls access.
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT pce.provider_kind, pce.provider_scope, pce.provider_event_key, \
                 pce.title, pce.start_date, pce.start_time, pce.end_date, pce.end_time, \
                 pce.all_day, pce.location, pce.color, pce.recurrence, \
                 pce.source_time_kind, pce.source_tzid \
          FROM task_provider_event_links tpl \
          JOIN provider_calendar_events pce \
            ON tpl.provider_kind = pce.provider_kind \
           AND tpl.provider_scope = pce.provider_scope \
           AND tpl.provider_event_key = pce.provider_event_key \
          WHERE tpl.task_id = ? \
            AND EXISTS ( \
              SELECT 1 FROM provider_scope_runtime_state psr \
              WHERE psr.provider_kind = pce.provider_kind \
                AND psr.provider_scope = pce.provider_scope \
                AND psr.availability_state = '\(AvailabilityState.enabled)' \
                AND psr.last_refresh_success_at IS NOT NULL \
            ) \
          ORDER BY pce.start_date ASC, pce.start_time ASC NULLS LAST, pce.title ASC, pce.provider_event_key ASC
          """,
        arguments: [taskID])
      var providerEvents = rows.map(Self.providerEvent)
      if !accessMode.includesDetails {
        providerEvents = providerEvents.map(Self.redactedProviderEvent)
      }
      let canonicalIDs = Set(events.map(\.id))
      events.append(contentsOf: providerEvents.filter { !canonicalIDs.contains($0.id) })
      Self.sortLinkedEvents(&events)
      return events
    }
  }

  public func getLinkedTasksForEvent(eventID: CalendarTimelineEvent.ID) async throws -> [LorvexTask]
  {
    return try read { db in
      let taskIDs: [String]
      if try CalendarTimelineQueries.getStoredCalendarEvent(db, id: eventID) != nil {
        let canonicalID = try Self.canonicalCalendarLinkTargetID(db, eventID: eventID)
        taskIDs = try Self.linkedCanonicalTaskIDs(db, calendarEventID: canonicalID)
      } else {
        let accessMode = try DeviceStateRepo.readCalendarAiAccessMode(db)
        guard accessMode.includesProvider else { return [] }
        let fields = try Self.providerEventLookupFields(providerEventID: eventID)
        taskIDs = try Self.linkedTaskIDs(db, eventID: eventID, fields: fields)
      }
      var seen = Set<String>()
      return try taskIDs.compactMap { id in
        guard seen.insert(id).inserted else { return nil }
        return try Self.loadTaskMapped(db, id: id)
      }
    }
  }

  /// Collapse a provider event to bare occupancy for the `busy_only` tier,
  /// mirroring ``CalendarTimelineQueries/redactProviderDetails``: the title
  /// becomes the generic "Busy" and every private field (location, notes,
  /// person, attendees, url) is dropped, leaving only occupancy (dates/times).
  static func redactedProviderEvent(_ event: CalendarTimelineEvent) -> CalendarTimelineEvent {
    var redacted = event
    redacted.title = EventKitIngest.busyTitle
    redacted.location = nil
    redacted.notes = nil
    redacted.personName = nil
    redacted.attendees = nil
    redacted.url = nil
    return redacted
  }
}
