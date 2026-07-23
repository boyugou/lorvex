import Foundation
import GRDB
import LorvexDomain

extension CalendarTimelineQueries {

  /// Text search of canonical calendar events over title, description, and
  /// location. Latin-script queries use the `calendar_events_fts` FTS5 table;
  /// CJK queries fall back to multi-column LIKE substring matching. Optional
  /// `from`/`to` narrows the date range. Sorted by `(start_date ASC,
  /// start_time ASC, id ASC)`.
  public static func searchCalendarEvents(
    _ db: Database, predicate: CalendarSearchPredicate, limit: UInt32
  ) throws -> [CalendarEventRow] {
    if Fts.containsCjk(predicate.query) {
      let pattern = "%\(Parsing.escapeLike(predicate.query))%"
      return try runCalendarSearch(
        db,
        seedCondition: """
          (ce.title LIKE ?1 ESCAPE '\\' \
            OR ce.description LIKE ?1 ESCAPE '\\' \
            OR ce.location LIKE ?1 ESCAPE '\\')
          """,
        seedParam: pattern, predicate: predicate, limit: limit)
    }

    let ftsQuery = Fts.sanitizeFtsQuery(predicate.query)
    if ftsQuery.isEmpty {
      return []
    }

    return try runCalendarSearch(
      db,
      seedCondition:
        "ce.rowid IN (SELECT rowid FROM calendar_events_fts WHERE calendar_events_fts MATCH ?1)",
      seedParam: ftsQuery, predicate: predicate, limit: limit)
  }

  /// Shared body for the FTS and LIKE branches. Both seeds bind exactly one
  /// parameter at `?1`, so the date predicates start at `?2`.
  private static func runCalendarSearch(
    _ db: Database, seedCondition: String, seedParam: String,
    predicate: CalendarSearchPredicate, limit: UInt32
  ) throws -> [CalendarEventRow] {
    var conditions = [
      seedCondition,
      "(ce.series_id IS NULL OR ce.occurrence_state = 'replacement')",
    ]
    var params: [DatabaseValueConvertible] = [seedParam]

    if let from = predicate.from {
      params.append(from)
      conditions.append(
        "((ce.recurrence IS NOT NULL "
          + "AND (ce.recurrence_end_date IS NULL OR ce.recurrence_end_date >= ?\(params.count))) "
          + "OR (ce.recurrence IS NULL AND COALESCE(ce.end_date, ce.start_date) >= ?\(params.count)))"
      )
    }
    if let to = predicate.to {
      params.append(to)
      conditions.append("ce.start_date <= ?\(params.count)")
    }

    if limit == 0 { return [] }
    let batchSize = max(Int(limit) * 2, 64)
    let limitIdx = params.count + 1
    let offsetIdx = params.count + 2
    var rawOffset = 0
    var visible: [CalendarEventRow] = []
    var index = CalendarSeriesProjectionIndex()
    while visible.count < Int(limit) {
      var batchParams = params
      batchParams.append(Int64(batchSize))
      batchParams.append(Int64(rawOffset))
      let sql = """
        SELECT \(calendarEventReadProjection("ce")) \
        FROM calendar_events ce \
        WHERE \(conditions.joined(separator: " AND ")) \
        ORDER BY ce.start_date ASC, ce.start_time ASC, ce.id ASC \
        LIMIT ?\(limitIdx) OFFSET ?\(offsetIdx)
        """
      let rows = try Row.fetchAll(
        db, sql: sql, arguments: StatementArguments(batchParams))
      if rows.isEmpty { break }
      rawOffset += rows.count
      let events = try rows.map(calendarEventFromRow)
      try index.load(db, candidates: .init(events: events))
      for event in events {
        if try isVisibleCanonicalEvent(db, event, index: index),
          canonicalEventOverlapsEffectiveRange(
            event: event, from: predicate.from, to: predicate.to, index: index)
        {
          visible.append(event)
          if visible.count == Int(limit) { break }
        }
      }
      if rows.count < batchSize { break }
    }
    return visible
  }

  /// Title / location / organizer-email substring search over the provider
  /// (EventKit) mirror, gated to enabled + refreshed scopes — the same access
  /// gate the timeline applies. Provider rows have no FTS index, so this is a
  /// LIKE scan. Returns base (un-expanded) occurrence items carrying their
  /// recurrence rule, matching how canonical search returns event definitions
  /// rather than per-occurrence expansions. Optional `from`/`to` narrows the
  /// range; sorted by `(start_date ASC, start_time ASC, provider_event_key ASC)`.
  public static func searchProviderCalendarEvents(
    _ db: Database, predicate: CalendarSearchPredicate, limit: UInt32
  ) throws -> [CalendarTimelineItem] {
    let pattern = "%\(Parsing.escapeLike(predicate.query))%"
    var conditions = [
      """
      (pce.title LIKE ?1 ESCAPE '\\' \
        OR pce.location LIKE ?1 ESCAPE '\\' \
        OR pce.organizer_email LIKE ?1 ESCAPE '\\')
      """,
      providerScopeEnabledExistsClause,
    ]
    var params: [DatabaseValueConvertible] = [pattern]

    if let from = predicate.from {
      params.append(from)
      conditions.append("COALESCE(pce.end_date, pce.start_date) >= ?\(params.count)")
    }
    if let to = predicate.to {
      params.append(to)
      conditions.append("pce.start_date <= ?\(params.count)")
    }

    params.append(Int64(limit))
    let limitIdx = params.count

    let sql = """
      SELECT \(providerTimelineColumns) \
      FROM provider_calendar_events pce \
      WHERE \(conditions.joined(separator: " AND ")) \
      ORDER BY pce.start_date ASC, pce.start_time ASC, pce.provider_event_key ASC \
      LIMIT ?\(limitIdx)
      """
    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(params))
    return rows.compactMap { parseProviderRow($0)?.item }
  }
}
