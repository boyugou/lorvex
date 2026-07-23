import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func batchCreateCalendarEventsForMcp(
    _ specs: [McpCalendarEventCreateSpec]
  ) async throws -> [McpCalendarEventCreateOutcome] {
    try withWrite { db, hlc, deviceId in
      var outcomes: [McpCalendarEventCreateOutcome] = []
      outcomes.reserveCapacity(specs.count)
      for spec in specs {
        do {
          let event = try StoreTransactions.withSavepoint(db, "mcp_calendar_create") { db in
            try self.createCalendarEventForMcpInTx(
              db, hlc: hlc, deviceId: deviceId, spec: spec)
          }
          outcomes.append(.created(event))
        } catch where Self.isMcpWriteFunnelControlFlow(error) {
          throw error
        } catch {
          outcomes.append(.failed(reference: spec.reference, error: error))
        }
      }
      return outcomes
    }
  }

  private func createCalendarEventForMcpInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, spec: McpCalendarEventCreateSpec
  ) throws -> CalendarTimelineEvent {
    let draft = spec.draft
    if let id = spec.originalID {
      guard SyncEntityId.isCanonicalUuid(id) else {
        throw LorvexCoreError.validation(
          field: "original_id", message: "original_id must be a canonical UUID.")
      }
      if let existing = try CalendarTimelineQueries.getCalendarEvent(db, id: id) {
        return SwiftLorvexCalendarDeserializers.event(existing)
      }
      if try Tombstone.isTombstoned(
        db, entityType: EntityName.calendarEvent, entityId: id)
      {
        throw LorvexCoreError.conflict(
          message:
            "That original_id belongs to a deleted calendar event. Omit original_id to create a new event.")
      }
      return try writeImportedCalendarEventInTx(
        db, hlc: hlc, deviceId: deviceId, id: id, title: draft.title,
        startDate: draft.startDate, startTime: draft.allDay ? nil : draft.startTime,
        endDate: draft.endDate, endTime: draft.allDay ? nil : draft.endTime,
        allDay: draft.allDay, location: draft.location, notes: draft.notes,
        url: draft.url, color: draft.color, eventType: draft.eventType,
        personName: draft.personName, attendees: draft.attendees, timezone: draft.timezone,
        recurrence: draft.recurrence?.canonicalRecurrenceJSON(), seriesId: nil,
        recurrenceInstanceDate: nil, occurrenceState: nil, recurrenceGeneration: nil,
        seriesCutoverId: nil)
    }

    let input = CalendarEventCreateInput(
      title: draft.title,
      recurrence: (draft.recurrence?.canonicalRecurrenceJSON()).trimmedNilIfEmpty,
      timezone: try draft.timezone.trimmedNilIfEmpty
        ?? WorkflowTimezone.anchoredTimezoneName(db),
      startDate: draft.startDate, startTime: draft.allDay ? nil : draft.startTime,
      endDate: draft.endDate, endTime: draft.allDay ? nil : draft.endTime,
      allDay: draft.allDay, description: draft.notes, location: draft.location,
      url: draft.url.trimmedNilIfEmpty, color: draft.color.trimmedNilIfEmpty,
      eventType: try Self.calendarEventType(draft.eventType),
      personName: draft.personName.trimmedNilIfEmpty,
      attendees: Self.attendeeInputs(draft.attendees))
    let result = try CalendarEventCreate.createCalendarEvent(
      db, hlc: hlc, eventId: EntityID.newEntityIDString(), input: input)
    try enqueueUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .calendarEvent, entityId: result.eventId)
    try writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert, entityType: EntityName.calendarEvent,
        entityId: result.eventId, summary: result.summary, after: result.event),
      deviceId: deviceId)
    return try SwiftLorvexCalendarDeserializers.event(result.event)
  }

  private static func isMcpWriteFunnelControlFlow(_ error: any Error) -> Bool {
    switch error {
    case is StorageCutoverDuringWrite: return true
    case StoreError.staleVersion, StoreError.versionSuperseded: return true
    case EnqueueError.versionSuperseded: return true
    default: return false
    }
  }
}
