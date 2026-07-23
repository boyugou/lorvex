import GRDB
import LorvexDomain
import LorvexStore

extension SwiftLorvexCoreService {
  /// Resolve any linkable canonical event address to the synced series-level
  /// endpoint stored by `task_calendar_event_links`.
  ///
  /// Base events already are link targets. A visible replacement decision is
  /// normalized to its recurring master so changing/resetting the occurrence
  /// decision never strands the task edge on an ephemeral child row. Cancelled,
  /// inherited, stale-generation, and otherwise invisible decision rows are not
  /// valid link endpoints.
  static func canonicalCalendarLinkTargetID(
    _ db: Database, eventID: String
  ) throws -> String {
    guard let stored = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: eventID) else {
      throw LorvexCoreError.notFound(entity: .calendarEvent, id: eventID)
    }
    guard let seriesID = stored.seriesId else {
      guard try CalendarTimelineQueries.getCalendarEvent(db, id: stored.id) != nil else {
        throw LorvexCoreError.validation(
          field: "event_id",
          message: "Calendar event '\(eventID)' is not active in its series.")
      }
      return stored.id
    }
    guard stored.occurrenceState == .replacement,
      try CalendarTimelineQueries.getCalendarEvent(db, id: stored.id) != nil,
      let master = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: seriesID),
      master.seriesId == nil,
      master.recurrence != nil
    else {
      throw LorvexCoreError.validation(
        field: "event_id",
        message: "Calendar occurrence '\(eventID)' is not an active replacement in its series.")
    }
    return master.id
  }

  static func linkedCanonicalEvents(
    _ db: Database, taskID: String
  ) throws -> [CalendarTimelineEvent] {
    let eventIDs = try String.fetchAll(
      db,
      sql: """
        SELECT link.calendar_event_id
        FROM task_calendar_event_links link
        JOIN calendar_events event ON event.id = link.calendar_event_id
        WHERE link.task_id = ? AND event.series_id IS NULL
        ORDER BY event.start_date ASC, event.start_time ASC NULLS LAST,
                 event.title ASC, event.id ASC
        """,
      arguments: [taskID])
    return try eventIDs.compactMap { eventID in
      try CalendarTimelineQueries.getCalendarEvent(db, id: eventID)
        .map(SwiftLorvexCalendarDeserializers.event)
    }
  }

  static func linkedCanonicalTaskIDs(
    _ db: Database, calendarEventID: String
  ) throws -> [String] {
    try String.fetchAll(
      db,
      sql: """
        SELECT t.id
        FROM task_calendar_event_links link
        JOIN tasks t ON t.id = link.task_id AND t.archived_at IS NULL
        WHERE link.calendar_event_id = ?
        ORDER BY t.priority_effective ASC, t.due_date ASC NULLS LAST, t.id ASC
        """,
      arguments: [calendarEventID])
  }

  static func providerEventIsLinkable(_ db: Database, fields: ProviderLinkFields) throws -> Bool {
    let exists = try Int.fetchOne(
      db,
      sql: """
        SELECT 1 \
        FROM provider_calendar_events pce \
        WHERE pce.provider_kind = ? \
          AND pce.provider_scope = ? \
          AND pce.provider_event_key = ? \
          AND EXISTS ( \
            SELECT 1 FROM provider_scope_runtime_state psr \
            WHERE psr.provider_kind = pce.provider_kind \
              AND psr.provider_scope = pce.provider_scope \
              AND psr.availability_state = '\(AvailabilityState.enabled)' \
              AND psr.last_refresh_success_at IS NOT NULL \
          ) \
        LIMIT 1
        """,
      arguments: [fields.providerKind, fields.providerScope, fields.providerEventKey])
    return exists != nil
  }

  static func linkedTaskIDs(
    _ db: Database,
    eventID: CalendarTimelineEvent.ID,
    fields: ProviderLinkFields?
  ) throws -> [String] {
    if let fields {
      return try String.fetchAll(
        db,
        sql: """
          SELECT t.id \
          FROM task_provider_event_links tpl \
          JOIN provider_calendar_events pce \
            ON pce.provider_kind = tpl.provider_kind \
           AND pce.provider_scope = tpl.provider_scope \
           AND pce.provider_event_key = tpl.provider_event_key \
          JOIN tasks t ON t.id = tpl.task_id AND t.archived_at IS NULL \
          WHERE tpl.provider_kind = ? AND tpl.provider_scope = ? AND tpl.provider_event_key = ? \
            AND \(providerScopeEnabledExistsClause) \
          ORDER BY t.priority_effective ASC, t.due_date ASC NULLS LAST, t.id ASC
          """,
        arguments: [fields.providerKind, fields.providerScope, fields.providerEventKey])
    }
    return try String.fetchAll(
      db,
      sql: """
        SELECT t.id \
        FROM task_provider_event_links tpl \
        JOIN provider_calendar_events pce \
          ON pce.provider_kind = tpl.provider_kind \
         AND pce.provider_scope = tpl.provider_scope \
         AND pce.provider_event_key = tpl.provider_event_key \
        JOIN tasks t ON t.id = tpl.task_id AND t.archived_at IS NULL \
        WHERE tpl.provider_event_key = ? \
          AND \(providerScopeEnabledExistsClause) \
        ORDER BY t.priority_effective ASC, t.due_date ASC NULLS LAST, t.id ASC
        """,
      arguments: [eventID])
  }

  private static var providerScopeEnabledExistsClause: String {
    """
      EXISTS ( \
        SELECT 1 FROM provider_scope_runtime_state psr \
        WHERE psr.provider_kind = pce.provider_kind \
          AND psr.provider_scope = pce.provider_scope \
          AND psr.availability_state = '\(AvailabilityState.enabled)' \
          AND psr.last_refresh_success_at IS NOT NULL \
      )
      """
  }

  static func sortLinkedEvents(_ events: inout [CalendarTimelineEvent]) {
    events.sort { lhs, rhs in
      if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
      switch (lhs.startTime, rhs.startTime) {
      case let (left?, right?):
        if left != right { return left < right }
      case (.some, nil): return true
      case (nil, .some): return false
      case (nil, nil): break
      }
      if lhs.title != rhs.title {
        return lhs.title.utf8.lexicographicallyPrecedes(rhs.title.utf8)
      }
      return lhs.id.utf8.lexicographicallyPrecedes(rhs.id.utf8)
    }
  }

  static func providerEvent(_ row: Row) -> CalendarTimelineEvent {
    let providerKind: String = row[0]
    let providerScope: String = row[1]
    let providerEventKey: String = row[2]
    let recurrence: String? = row[11]
    let sourceTimeKind: String = row[12]
    let sourceTzid: String? = row[13]
    let timezone: String?
    switch sourceTimeKind {
    case "utc": timezone = "UTC"
    case "tzid": timezone = sourceTzid
    default: timezone = nil
    }
    return CalendarTimelineEvent(
      id: "\(providerKind):\(providerScope):\(providerEventKey)",
      title: row[3],
      source: "provider",
      editable: false,
      startDate: row[4],
      startTime: row[5],
      endDate: row[6],
      endTime: row[7],
      allDay: (row[8] as Int64) != 0,
      location: row[9],
      color: row[10],
      eventType: "event",
      timezone: timezone,
      isRecurring: recurrence != nil,
      recurrenceRule: recurrence,
      recurrenceSummary: nil
    )
  }
}
