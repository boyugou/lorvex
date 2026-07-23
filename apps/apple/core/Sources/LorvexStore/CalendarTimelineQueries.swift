import Foundation
import GRDB
import LorvexDomain

/// DB-backed calendar-timeline reads over `calendar_events` (canonical,
/// synced) and `provider_calendar_events` (device-local mirror), applying
/// recurrence expansion + timezone projection before returning results.
///
/// Per-row / per-expansion skip paths keep their data behavior (skip the row,
/// render the partial occurrence list, apply occurrence-decision or provider-
/// EXDATE suppression). Diagnostic
/// breadcrumbs are a higher-level telemetry concern and are intentionally not
/// emitted from this pure store helper.
public enum CalendarTimelineQueries {

  static let calendarEventReadColumns: [String] = [
    "id", "title", "description", "recurrence", "recurrence_exceptions", "timezone",
    "start_date", "start_time", "end_date", "end_time", "all_day", "location", "color",
    "event_type", "person_name", "url", "created_at", "updated_at", "version",
    "series_id", "recurrence_instance_date", "occurrence_state", "recurrence_generation",
    "recurrence_topology_version", "attendees", "content_version", "series_cutover_id",
  ]

  /// Column projection (alias `pce`) for a `provider_calendar_events` read, in
  /// the exact order ``parseProviderRow(_:)`` expects. Shared by the timeline
  /// and search so both map provider rows identically.
  static let providerTimelineColumns = """
    pce.provider_kind, pce.provider_scope, pce.provider_event_key, \
    pce.title, pce.start_date, pce.start_time, pce.end_date, pce.end_time, \
    pce.all_day, pce.location, pce.color, pce.recurrence, pce.recurrence_exceptions, \
    pce.source_time_kind, pce.source_tzid, pce.attendees_json, \
    pce.description, pce.organizer_email, pce.video_call_url
    """

  /// `EXISTS` gate (alias `pce`) restricting provider rows to scopes that are
  /// enabled and have completed at least one successful refresh — the same
  /// access gate the timeline applies, so search can never surface mirror rows
  /// the timeline would hide.
  static var providerScopeEnabledExistsClause: String {
    let enabled = AvailabilityState.enabled
    return """
      EXISTS ( \
          SELECT 1 FROM provider_scope_runtime_state psr \
          WHERE psr.provider_kind = pce.provider_kind \
            AND psr.provider_scope = pce.provider_scope \
            AND psr.availability_state = '\(enabled)' \
            AND psr.last_refresh_success_at IS NOT NULL \
      )
      """
  }

  /// Column projection for a `calendar_events` SELECT. The legacy
  /// `recurrence_exceptions` response is derived from the master's active
  /// generation: replacement and cancelled decisions suppress the natural
  /// occurrence; inherit explicitly does not.
  static func calendarEventReadProjection(_ tableAlias: String?) -> String {
    let ownerPrefix = tableAlias ?? "calendar_events"
    let exceptionsExpr =
      "(SELECT NULLIF(json_group_array(exception_date), '[]') "
      + "FROM (SELECT decision.recurrence_instance_date AS exception_date "
      + "FROM calendar_events decision "
      + "WHERE decision.series_id = \(ownerPrefix).id "
      + "AND decision.recurrence_generation = \(ownerPrefix).recurrence_generation "
      + "AND decision.occurrence_state IN ('replacement', 'cancelled') "
      + "ORDER BY decision.recurrence_instance_date)) AS recurrence_exceptions"
    return calendarEventReadColumns.map { column in
      if column == "recurrence_exceptions" {
        return exceptionsExpr
      }
      if let alias = tableAlias {
        return "\(alias).\(column)"
      }
      return column
    }.joined(separator: ", ")
  }

  // -- get_calendar_event / list_calendar_events --------------------------

  public static func getCalendarEvent(_ db: Database, id: String) throws -> CalendarEventRow? {
    guard let event = try getStoredCalendarEvent(db, id: id) else { return nil }
    let index = try CalendarSeriesProjectionIndex(
      db, candidates: .init(events: [event]))
    return try isVisibleCanonicalEvent(db, event, index: index) ? event : nil
  }

  /// Raw canonical row lookup, including cancelled/inherit decisions and
  /// decisions whose master has not arrived yet. Mutation workflows and sync
  /// adapters must use this read-back path: user-facing visibility is a
  /// projection concern and must never make a successfully written register
  /// appear to have disappeared.
  public static func getStoredCalendarEvent(
    _ db: Database, id: String
  ) throws -> CalendarEventRow? {
    let sql = "SELECT \(calendarEventReadProjection(nil)) FROM calendar_events WHERE id = ?"
    guard let row = try Row.fetchOne(db, sql: sql, arguments: [id]) else { return nil }
    return try calendarEventFromRow(row)
  }

  public static func listCalendarEvents(
    _ db: Database, from: String, to: String, limit: UInt32, offset: UInt32
  ) throws -> [CalendarEventRow] {
    if limit == 0 { return [] }
    let targetCount = Int(offset) + Int(limit)
    let batchSize = max(Int(limit) * 2, 64)
    var rawOffset = 0
    var visible: [CalendarEventRow] = []
    var index = CalendarSeriesProjectionIndex()
    while visible.count < targetCount {
      let sql = """
        SELECT \(calendarEventReadProjection(nil)) \
        FROM calendar_events \
        WHERE start_date <= ?2 \
          AND ( \
            (recurrence IS NOT NULL \
              AND (recurrence_end_date IS NULL OR recurrence_end_date >= ?1)) \
            OR (recurrence IS NULL AND COALESCE(end_date, start_date) >= ?1) \
          ) \
          AND (series_id IS NULL OR occurrence_state = 'replacement') \
        ORDER BY start_date ASC, start_time ASC, id ASC \
        LIMIT ?3 OFFSET ?4
        """
      let rows = try Row.fetchAll(
        db, sql: sql, arguments: [from, to, Int64(batchSize), Int64(rawOffset)])
      if rows.isEmpty { break }
      rawOffset += rows.count
      let events = try rows.map(calendarEventFromRow)
      try index.load(db, candidates: .init(events: events))
      for event in events {
        if try isVisibleCanonicalEvent(db, event, index: index),
          canonicalEventOverlapsEffectiveRange(
            event: event, from: from, to: to, index: index)
        {
          visible.append(event)
        }
      }
      if rows.count < batchSize { break }
    }
    return Array(visible.dropFirst(Int(offset)).prefix(Int(limit)))
  }

  /// Native-backup projection. Unlike the user-facing list, this preserves all
  /// three active occurrence-decision states so a restore can reconstruct the
  /// register. Decisions from an old generation, with a missing master, or no
  /// longer on the master's recurrence grid are inert garbage and are omitted.
  public static func listCalendarEventRowsForNativeExport(
    _ db: Database, limit: UInt32, offset: UInt32
  ) throws -> [CalendarEventRow] {
    if limit == 0 { return [] }
    let targetCount = Int(offset) + Int(limit)
    let batchSize = max(Int(limit) * 2, 64)
    var rawOffset = 0
    var exportable: [CalendarEventRow] = []
    var index = CalendarSeriesProjectionIndex()
    while exportable.count < targetCount {
      let sql = """
        SELECT \(calendarEventReadProjection(nil)) \
        FROM calendar_events \
        ORDER BY CASE WHEN series_id IS NULL THEN 0 ELSE 1 END ASC, id ASC \
        LIMIT ? OFFSET ?
        """
      let rows = try Row.fetchAll(
        db, sql: sql, arguments: [Int64(batchSize), Int64(rawOffset)])
      if rows.isEmpty { break }
      rawOffset += rows.count
      let events = try rows.map(calendarEventFromRow)
      try index.load(db, candidates: .init(events: events))
      for event in events {
        if try isExportableCanonicalEvent(db, event, index: index) {
          exportable.append(event)
        }
      }
      if rows.count < batchSize { break }
    }
    return Array(exportable.dropFirst(Int(offset)).prefix(Int(limit)))
  }

  /// Active occurrence decisions for one recurring master, ordered by their
  /// original slot and stable id. Old generations and decisions that no
  /// longer belong to the master's recurrence grid are intentionally omitted.
  ///
  /// This is the canonical projection for adapters such as RFC 5545 export:
  /// cancelled decisions become EXDATE values, replacements become exception
  /// VEVENTs, and inherit decisions produce no output.
  public static func listActiveCalendarOccurrenceDecisions(
    _ db: Database, seriesId: String
  ) throws -> [CalendarEventRow] {
    try listActiveCalendarOccurrenceDecisions(db, seriesIds: [seriesId])[seriesId] ?? []
  }

  /// Batch sibling used by adapters that emit many recurrence components.
  /// It shares one cutover snapshot and keeps each SQL bind set under SQLite's
  /// conservative parameter limit.
  public static func listActiveCalendarOccurrenceDecisions(
    _ db: Database, seriesIds: [String]
  ) throws -> [String: [CalendarEventRow]] {
    let uniqueIds = Array(Set(seriesIds)).sorted()
    guard !uniqueIds.isEmpty else { return [:] }
    let index = try CalendarSeriesProjectionIndex(
      db, candidates: .init(ambiguousSegmentEventIds: uniqueIds))
    var decisionsBySeries: [String: [CalendarEventRow]] = [:]
    for start in stride(from: 0, to: uniqueIds.count, by: 500) {
      let ids = Array(uniqueIds[start..<min(start + 500, uniqueIds.count)])
      let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
      let sql = """
        SELECT \(calendarEventReadProjection(nil)) \
        FROM calendar_events \
        WHERE series_id IN (\(placeholders)) \
        ORDER BY series_id ASC, recurrence_instance_date ASC, id ASC
        """
      let rows = try Row.fetchAll(
        db, sql: sql, arguments: StatementArguments(ids))
      for row in rows {
        let event = try calendarEventFromRow(row)
        if try isExportableCanonicalEvent(db, event, index: index),
          let seriesId = event.seriesId
        {
          decisionsBySeries[seriesId, default: []].append(event)
        }
      }
    }
    return decisionsBySeries
  }

  // -- get_calendar_timeline ----------------------------------------------

  /// Retrieve all calendar-event occurrences overlapping `[from, to]`,
  /// sorted by `(start_date, start_time NULLS LAST, title)`. `accessMode`
  /// controls provider inclusion + detail redaction.
  public static func getCalendarTimeline(
    _ db: Database, from: String, to: String,
    accessMode: CalendarAiAccessMode, anchorTimezone: String
  ) throws -> [CalendarTimelineItem] {
    guard let fromDate = try? CalendarRecurrence.parseYmd(from) else {
      throw StoreError.validation("from: invalid YYYY-MM-DD")
    }
    guard let toDate = try? CalendarRecurrence.parseYmd(to) else {
      throw StoreError.validation("to: invalid YYYY-MM-DD")
    }

    var items = try queryCanonicalTimeline(db, fromDate, toDate, anchorTimezone)

    if accessMode.includesProvider {
      var providerItems = try queryProviderTimeline(db, fromDate, toDate, anchorTimezone)
      if !accessMode.includesDetails {
        for i in providerItems.indices {
          redactProviderDetails(&providerItems[i])
        }
      }
      items.append(contentsOf: providerItems)
    }

    items.sort { a, b in
      if a.startDate != b.startDate { return a.startDate < b.startDate }
      switch (a.startTime, b.startTime) {
      case let (at?, bt?):
        if at != bt { return at < bt }
      case (.some, nil):
        return true
      case (nil, .some):
        return false
      case (nil, nil):
        break
      }
      // Byte-wise UTF-8 ordering (Swift's `String <` is Unicode-canonical,
      // which can diverge on non-ASCII).
      return a.title.utf8.lexicographicallyPrecedes(b.title.utf8)
    }

    return items
  }

  // -- canonical timeline -------------------------------------------------

  static func queryCanonicalTimeline(
    _ db: Database, _ fromDate: RDate, _ toDate: RDate, _ anchorTimezone: String
  ) throws -> [CalendarTimelineItem] {
    // Widen the fetch window by a day for the timed-projection buffer; at the
    // calendar's boundary the day-shift is unrepresentable, so fall back to the
    // un-widened bound rather than trap.
    let fromWide = (fromDate.addingDays(-1) ?? fromDate).ymdString
    let toWide = (toDate.addingDays(1) ?? toDate).ymdString
    let exc =
      "(SELECT NULLIF(json_group_array(exception_date), '[]') "
      + "FROM (SELECT decision.recurrence_instance_date AS exception_date "
      + "FROM calendar_events decision "
      + "WHERE decision.series_id = calendar_events.id "
      + "AND decision.recurrence_generation = calendar_events.recurrence_generation "
      + "AND decision.occurrence_state IN ('replacement', 'cancelled') "
      + "ORDER BY decision.recurrence_instance_date))"
    let cols =
      "id, title, recurrence, \(exc), timezone, "
      + "start_date, start_time, end_date, end_time, all_day, location, color, "
      + "event_type, person_name, url, description, attendees, "
      + "series_id, recurrence_instance_date, recurrence_generation, occurrence_state, "
      + "series_cutover_id"
    let sql = """
      SELECT \(cols) \
      FROM calendar_events \
      WHERE series_id IS NULL AND recurrence IS NOT NULL AND start_date <= ?2 \
        AND (recurrence_end_date IS NULL OR recurrence_end_date >= ?1) \
      UNION ALL \
      SELECT \(cols) \
      FROM calendar_events \
      WHERE series_id IS NULL AND recurrence IS NULL AND start_date <= ?2 \
        AND end_date IS NOT NULL AND end_date >= ?1 \
      UNION ALL \
      SELECT \(cols) \
      FROM calendar_events \
      WHERE series_id IS NULL AND recurrence IS NULL AND end_date IS NULL \
        AND start_date BETWEEN ?1 AND ?2
      UNION ALL \
      SELECT \(cols) \
      FROM calendar_events \
      WHERE occurrence_state = 'replacement' AND start_date <= ?2 \
        AND end_date IS NOT NULL AND end_date >= ?1 \
      UNION ALL \
      SELECT \(cols) \
      FROM calendar_events \
      WHERE occurrence_state = 'replacement' AND end_date IS NULL \
        AND start_date BETWEEN ?1 AND ?2
    """
    let rows = try Row.fetchAll(db, sql: sql, arguments: [fromWide, toWide])
    var candidates = CalendarSeriesProjectionIndex.Candidates()
    for row in rows {
      let eventId: String = row[0]
      if let seriesId: String = row[17] {
        candidates.lineageRootIds.append(seriesId)
        candidates.cutoverIds.append(seriesId)
      } else if (row[21] as String?) == nil {
        candidates.lineageRootIds.append(eventId)
      } else {
        candidates.cutoverIds.append(eventId)
      }
    }
    let projectionIndex = try CalendarSeriesProjectionIndex(
      db, candidates: candidates)

    var items: [CalendarTimelineItem] = []
    for row in rows {
      let recurrence: String? = row[2]
      let parsed = parseCanonicalRow(row, recurrence: recurrence)
      guard let raw = parsed else { continue }
      if let state = raw.item.occurrenceState {
        if state != .replacement { continue }
        if try !isVisibleCanonicalItem(db, raw.item, index: projectionIndex) { continue }
      } else {
        guard
          let ownership = projectionIndex.ownership(
            segmentEventId: raw.item.eventId,
            seriesCutoverId: row[21] as String?),
          ownership.isActive
        else {
          continue
        }
        var bounded = raw
        bounded.ownedFromDate = ownership.lowerBoundCutoverDate
        bounded.ownedUntilDate = ownership.nextCutoverDate
        try extendWithTolerantExpansion(
          &items, bounded, fromDate, toDate, anchorTimezone)
        continue
      }
      try extendWithTolerantExpansion(&items, raw, fromDate, toDate, anchorTimezone)
    }
    return items
  }

  private static func parseCanonicalRow(_ row: Row, recurrence: String?) -> CalendarTimeline.RawCalendarRow? {
    guard let startDate = parseDate(row[5]) else { return nil }
    guard let startTime = parseOptTime(row[6]) else { return nil }
    guard let endDate = parseOptDate(row[7]) else { return nil }
    guard let endTime = parseOptTime(row[8]) else { return nil }
    let allDay: Bool = ((row[9] as Int64?) ?? 0) != 0
    let rowSeriesId: String? = row[17]
    let recurrenceGeneration: String? = row[19]
    let occurrenceState: CalendarOccurrenceState?
    if let rawState: String = row[20] {
      guard let parsed = CalendarOccurrenceState(rawValue: rawState) else { return nil }
      occurrenceState = parsed
    } else {
      occurrenceState = nil
    }
    let itemSeriesId: String? = recurrence == nil ? rowSeriesId : (row[0] as String)
    let made = CalendarTimelineItem.make(
      source: .canonical, editable: true, id: row[0], title: row[1],
      startDate: startDate, startTime: startTime, endDate: endDate, endTime: endTime,
      allDay: allDay, location: row[10], color: row[11], eventType: row[12],
      personName: row[13], timezone: row[4],
      providerKind: nil, providerScope: nil,
      isRecurring: recurrence != nil || rowSeriesId != nil,
      recurrenceRule: recurrence, sourceTimeKind: nil, sourceTzid: nil,
      url: row[14], attendeesJson: row[16], description: row[15],
      seriesId: itemSeriesId, recurrenceInstanceDate: row[18],
      recurrenceGeneration: recurrenceGeneration, occurrenceState: occurrenceState)
    guard case let .success(item) = made else { return nil }
    return CalendarTimeline.RawCalendarRow(
      item: item, recurrence: recurrence, recurrenceExceptions: row[3])
  }

  // -- provider timeline --------------------------------------------------

  static func queryProviderTimeline(
    _ db: Database, _ fromDate: RDate, _ toDate: RDate, _ anchorTimezone: String
  ) throws -> [CalendarTimelineItem] {
    // Widen the fetch window by a day for the timed-projection buffer; at the
    // calendar's boundary the day-shift is unrepresentable, so fall back to the
    // un-widened bound rather than trap.
    let fromWide = (fromDate.addingDays(-1) ?? fromDate).ymdString
    let toWide = (toDate.addingDays(1) ?? toDate).ymdString
    let scopeExists = Self.providerScopeEnabledExistsClause
    let cols = Self.providerTimelineColumns
    let sql = """
      SELECT \(cols) \
      FROM provider_calendar_events pce \
      WHERE pce.recurrence IS NOT NULL AND pce.start_date <= ?2 \
        AND (pce.recurrence_end_date IS NULL OR pce.recurrence_end_date >= ?1) \
        AND \(scopeExists) \
      UNION ALL \
      SELECT \(cols) \
      FROM provider_calendar_events pce \
      WHERE pce.recurrence IS NULL AND pce.start_date <= ?2 \
        AND pce.end_date IS NOT NULL AND pce.end_date >= ?1 \
        AND \(scopeExists) \
      UNION ALL \
      SELECT \(cols) \
      FROM provider_calendar_events pce \
      WHERE pce.recurrence IS NULL AND pce.end_date IS NULL \
        AND pce.start_date BETWEEN ?1 AND ?2 \
        AND \(scopeExists)
      """
    let rows = try Row.fetchAll(db, sql: sql, arguments: [fromWide, toWide])

    var items: [CalendarTimelineItem] = []
    for row in rows {
      guard let raw = parseProviderRow(row) else { continue }
      try extendWithTolerantExpansion(&items, raw, fromDate, toDate, anchorTimezone)
    }
    return items
  }

  static func parseProviderRow(_ row: Row) -> CalendarTimeline.RawCalendarRow? {
    let providerKind: String = row[0]
    let providerScope: String = row[1]
    let providerEventKey: String = row[2]
    let compositeId = "\(providerKind):\(providerScope):\(providerEventKey)"
    let recurrence: String? = row[11]

    guard let startDate = parseDate(row[4]) else { return nil }
    guard let startTime = parseOptTime(row[5]) else { return nil }
    guard let endDate = parseOptDate(row[6]) else { return nil }
    guard let endTime = parseOptTime(row[7]) else { return nil }
    let allDay: Bool = ((row[8] as Int64?) ?? 0) != 0
    // Provider mirrors expose their real organizer field through the timeline
    // item's generic person slot. Provider rows are ordinary calendar events;
    // EventKit birthday/contact calendars are still events from this mirror's
    // perspective and do not need a second, unwritten event-kind column.
    let personName: String? = row[17]
    let sourceTimeKind: String = row[13]
    let sourceTzid: String? = row[14]
    let timezone: String?
    switch sourceTimeKind {
    case "utc": timezone = "UTC"
    case "tzid": timezone = sourceTzid
    default: timezone = nil
    }
    let made = CalendarTimelineItem.make(
      source: .provider, editable: false, id: compositeId, title: row[3],
      startDate: startDate, startTime: startTime, endDate: endDate, endTime: endTime,
      allDay: allDay, location: row[9], color: row[10], eventType: "event",
      // The source-time metadata is authoritative for a timed provider event.
      // Project it into the public timeline timezone too; otherwise schema
      // normalization makes a correctly ingested zone disappear from UI/MCP
      // reads (`utc` is represented without a `source_tzid`).
      personName: personName, timezone: timezone,
      providerKind: providerKind, providerScope: providerScope, isRecurring: recurrence != nil,
      recurrenceRule: recurrence, sourceTimeKind: sourceTimeKind, sourceTzid: sourceTzid,
      url: row[18], attendeesJson: row[15], description: row[16])
    guard case let .success(item) = made else { return nil }
    return CalendarTimeline.RawCalendarRow(
      item: item, recurrence: recurrence, recurrenceExceptions: row[12])
  }

  // -- shared helpers -----------------------------------------------------

  /// Expand a row, tolerating per-row malformed RRULEs by skipping the row
  /// rather than aborting the whole query. `.validation` / `.invariant` are
  /// swallowed (skip + render partial); other `StoreError` kinds propagate.
  /// Diagnostics for skipped malformed rows are handled by higher-level
  /// telemetry.
  static func extendWithTolerantExpansion(
    _ items: inout [CalendarTimelineItem], _ row: CalendarTimeline.RawCalendarRow,
    _ fromDate: RDate, _ toDate: RDate, _ anchorTimezone: String
  ) throws {
    do {
      let expanded = try CalendarTimeline.expandRowForRange(row, fromDate, toDate, anchorTimezone)
      items.append(contentsOf: expanded.items)
    } catch StoreError.validation, StoreError.invariant {
      // Skip the unsupported / non-advancing row; render what we have.
    }
  }

  /// Replace detail fields on a provider item for `busyOnly` mode, so the read
  /// surface honors the tier as defense in depth behind ingest-time redaction.
  /// `person_name` also carries a provider row's organizer email
  /// (see ``parseProviderRow(_:)``), so nilling it redacts the organizer too.
  static func redactProviderDetails(_ item: inout CalendarTimelineItem) {
    item.title = EventKitIngest.busyTitle
    item.location = nil
    item.personName = nil
    item.attendeesJson = nil
    item.description = nil
    item.url = nil
  }

  /// Whether a stored canonical row belongs to the active read model. Root
  /// events are implicit active segments; tail events require their matching
  /// active cutover. Only replacement decisions are user-visible, and their
  /// original slot must remain inside the owning segment's current interval.
  static func isVisibleCanonicalEvent(
    _ db: Database, _ event: CalendarEventRow
  ) throws -> Bool {
    let index = try CalendarSeriesProjectionIndex(
      db, candidates: .init(events: [event]))
    return try isVisibleCanonicalEvent(db, event, index: index)
  }

  static func isVisibleCanonicalEvent(
    _ db: Database, _ event: CalendarEventRow,
    index: CalendarSeriesProjectionIndex
  ) throws -> Bool {
    guard event.seriesId != nil else {
      return index.ownership(
        segmentEventId: event.id, seriesCutoverId: event.seriesCutoverId)?.isActive == true
    }
    guard event.occurrenceState == .replacement else { return false }
    return try isCurrentSeriesOccurrence(
      db,
      seriesId: event.seriesId,
      recurrenceInstanceDate: event.recurrenceInstanceDate,
      recurrenceGeneration: event.recurrenceGeneration,
      index: index)
  }

  private static func isExportableCanonicalEvent(
    _ db: Database, _ event: CalendarEventRow,
    index: CalendarSeriesProjectionIndex
  ) throws -> Bool {
    guard event.seriesId != nil else {
      return index.ownership(
        segmentEventId: event.id, seriesCutoverId: event.seriesCutoverId)?.isActive == true
    }
    guard event.occurrenceState != nil else { return false }
    return try isCurrentSeriesOccurrence(
      db,
      seriesId: event.seriesId,
      recurrenceInstanceDate: event.recurrenceInstanceDate,
      recurrenceGeneration: event.recurrenceGeneration,
      index: index)
  }

  static func isVisibleCanonicalItem(
    _ db: Database, _ item: CalendarTimelineItem,
    index: CalendarSeriesProjectionIndex
  ) throws -> Bool {
    try isCurrentSeriesOccurrence(
      db,
      seriesId: item.seriesId,
      recurrenceInstanceDate: item.recurrenceInstanceDate,
      recurrenceGeneration: item.recurrenceGeneration,
      index: index)
  }

  private static func isCurrentSeriesOccurrence(
    _ db: Database,
    seriesId: String?,
    recurrenceInstanceDate: String?,
    recurrenceGeneration: String?,
    index: CalendarSeriesProjectionIndex
  ) throws -> Bool {
    guard let seriesId, let recurrenceInstanceDate, let recurrenceGeneration else {
      return false
    }
    guard
      let master = try Row.fetchOne(
        db,
        sql: """
          SELECT recurrence, start_date, recurrence_generation, series_cutover_id \
          FROM calendar_events \
          WHERE id = ? AND series_id IS NULL AND recurrence IS NOT NULL
          """,
        arguments: [seriesId]),
      let recurrence: String = master[0],
      let startDate: String = master[1],
      let activeGeneration: String = master[2],
      activeGeneration == recurrenceGeneration,
      let ownership = index.ownership(
        segmentEventId: seriesId, seriesCutoverId: master[3] as String?),
      ownership.owns(recurrenceInstanceDate: recurrenceInstanceDate)
    else {
      return false
    }
    do {
      return try CalendarRecurrence.recursOnDate(
        recurrenceJson: recurrence,
        baseDateYmd: startDate,
        targetDateYmd: recurrenceInstanceDate)
    } catch StoreError.validation, StoreError.serialization {
      return false
    }
  }

  /// Coarse range gate layered on the SQL date predicate. It prevents a root
  /// whose durable successor begins before `from` from leaking into list/ICS
  /// reads merely because its stored recurrence is intentionally untruncated.
  /// Non-recurring rows continue to use their displayed timing; a one-off tail
  /// can be moved across a boundary without changing its logical cutover slot.
  static func canonicalEventOverlapsEffectiveRange(
    event: CalendarEventRow, from: String?, to: String?,
    index: CalendarSeriesProjectionIndex
  ) -> Bool {
    guard event.seriesId == nil, event.recurrence != nil else { return true }
    guard
      let ownership = index.ownership(
        segmentEventId: event.id, seriesCutoverId: event.seriesCutoverId),
      ownership.isActive
    else {
      return false
    }
    if let to, let lower = ownership.lowerBoundCutoverDate, lower > to { return false }
    guard let upper = ownership.nextCutoverDate else { return true }
    if upper <= event.startDate.asString { return false }
    guard let from else { return true }
    let durationDays: Int64 = {
      guard let endDate = event.endDate,
        let start = try? CalendarRecurrence.parseYmd(event.startDate.asString),
        let end = try? CalendarRecurrence.parseYmd(endDate.asString)
      else { return 0 }
      return max(start.daysUntil(end), 0)
    }()
    guard let upperDate = try? CalendarRecurrence.parseYmd(upper),
      let latestOwnedEnd = upperDate.addingDays(durationDays - 1)
    else {
      return upper > from
    }
    return latestOwnedEnd.ymdString >= from
  }

  /// Row mapper for a full `calendar_events` projection (search / single
  /// fetch). Non-canonical `event_type` or an illegal temporal quintuple
  /// surface as a `DatabaseError(SQLITE_MISMATCH)`.
  static func calendarEventFromRow(_ row: Row) throws -> CalendarEventRow {
    let eventTypeRaw: String = row[13]
    guard let eventType = CanonicalCalendarEventType.parse(eventTypeRaw) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "calendar_events.event_type: non-canonical value '\(eventTypeRaw)'")
    }
    guard let startDate = parseDate(row[6]) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "calendar_events.start_date: invalid value")
    }
    let startTime = parseOptTime(row[7]) ?? nil
    let endDate = parseOptDate(row[8]) ?? nil
    let endTime = parseOptTime(row[9]) ?? nil
    let allDay: Bool = ((row[10] as Int64?) ?? 0) != 0
    let timingResult = CalendarEventTiming.fromFlatFields(
      startDate: startDate, startTime: startTime, endDate: endDate,
      endTime: endTime, allDay: allDay)
    let timing: CalendarEventTiming
    switch timingResult {
    case let .success(t): timing = t
    case let .failure(err):
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "calendar_events temporal fields: \(err.messageString)")
    }
    let occurrenceState: CalendarOccurrenceState?
    if let rawState: String = row[21] {
      guard let parsed = CalendarOccurrenceState(rawValue: rawState) else {
        throw DatabaseError(
          resultCode: .SQLITE_MISMATCH,
          message: "calendar_events.occurrence_state: non-canonical value '\(rawState)'")
      }
      occurrenceState = parsed
    } else {
      occurrenceState = nil
    }
    return CalendarEventRow(
      id: row[0], title: row[1], description: row[2], recurrence: row[3],
      recurrenceExceptions: row[4], timezone: row[5], timing: timing,
      location: row[11], color: row[12], eventType: eventType, personName: row[14],
      url: row[15], attendees: row[24], seriesCutoverId: row[26],
      seriesId: row[19], recurrenceInstanceDate: row[20],
      occurrenceState: occurrenceState, recurrenceGeneration: row[22],
      recurrenceTopologyVersion: row[23],
      contentVersion: row[25],
      createdAt: row[16], updatedAt: row[17], version: row[18])
  }

  // -- value parsers ------------------------------------------------------

  private static func parseDate(_ raw: String?) -> LorvexDate? {
    guard let raw, case let .success(d) = LorvexDate.parse(raw) else { return nil }
    return d
  }

  /// `nil` outer means parse failure; inner `.some(nil)` means the column was
  /// SQL NULL (a valid absent value).
  private static func parseOptDate(_ raw: String?) -> LorvexDate?? {
    guard let raw else { return .some(nil) }
    guard case let .success(d) = LorvexDate.parse(raw) else { return nil }
    return .some(d)
  }

  private static func parseOptTime(_ raw: String?) -> TimeOfDay?? {
    guard let raw else { return .some(nil) }
    guard case let .success(t) = TimeOfDay.parse(raw) else { return nil }
    return .some(t)
  }
}
