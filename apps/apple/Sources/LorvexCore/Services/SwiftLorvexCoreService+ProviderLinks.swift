import Foundation
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
          "Provider event '\(providerEventID)' is not available. Refresh/search calendar events first, then link using a returned event id."
        )
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
          // Provider mirrors and links are strictly device-local, and so is the
          // audit row that records this change (`ai_changelog` never syncs). The
          // summary still names no provider scope, external event key, title, or
          // other EventKit detail, because the log is readable by assistants.
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

  public func getLinkedEventsForTask(taskID: LorvexTask.ID) async throws -> [CalendarTimelineEvent]
  {
    try read { db in
      var events = try Self.linkedCanonicalEvents(db, taskID: taskID)
      // Honor the effective calendar AI-access tier (read in the same
      // transaction, fail closed on a malformed value) so a link can't become a
      // side channel that leaks provider detail the tier forbids: `off` exposes
      // no provider events at all, and `busy_only` exposes occupancy only with
      // detail fields redacted — mirroring the timeline / search gate.
      let accessMode = try DeviceStateRepo.readCalendarAiAccessMode(db)
      guard accessMode.includesProvider else { return events }
      let providerEvents = try CalendarTimelineQueries.linkedProviderEvents(
        db, taskId: taskID, accessMode: accessMode
      ).map(SwiftLorvexCalendarDeserializers.event)
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

}
