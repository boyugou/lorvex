import GRDB
import LorvexDomain

extension CalendarTimelineQueries {
  /// Linked provider identities share the timeline/search decoder, including
  /// exact observed instants. A series returns its first cached occurrence as
  /// a representative under the stable source id, not an expanded timeline.
  public static func linkedProviderEvents(
    _ db: Database, taskId: String, accessMode: CalendarAiAccessMode
  ) throws -> [CalendarTimelineItem] {
    guard accessMode.includesProvider else { return [] }
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT \(providerTimelineColumns)
        FROM task_provider_event_links tpl
        JOIN provider_calendar_events pce
          ON tpl.provider_kind = pce.provider_kind
         AND tpl.provider_scope = pce.provider_scope
         AND tpl.provider_event_key = pce.provider_event_key
        WHERE tpl.task_id = ? AND \(providerScopeEnabledExistsClause)
        ORDER BY pce.start_date ASC, pce.start_time ASC NULLS LAST,
                 pce.title ASC, pce.provider_event_key ASC
        """,
      arguments: [taskId])
    return rows.compactMap { row in
      guard var item = parseProviderRow(row)?.item else { return nil }
      // Linked rows retain their existing limited-detail contract; the full
      // timeline is the surface for notes, attendees, organizer, and links.
      item.description = nil
      item.attendeesJson = nil
      item.personName = nil
      item.url = nil
      if !accessMode.includesDetails { redactProviderDetails(&item) }
      return item
    }
  }
}
