import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func loadTasksForDataExport() async throws -> [ExportTask] {
    try read { db in try Self.portableTasksForDataExport(db) }
  }

  static func portableTasksForDataExport(_ db: Database) throws -> [ExportTask] {
    var collected: [ExportTask] = []
    var offset = 0
    while true {
      let ids = try String.fetchAll(
        db,
        sql: "SELECT id FROM tasks ORDER BY id ASC LIMIT ? OFFSET ?",
        arguments: [LorvexDataExportWindow.taskPageSize, offset])
      if ids.isEmpty { break }
      let taskJSON = try TaskResponse.loadEnrichedTasksJSON(db, taskIds: ids)
      let remindersByTaskID = try PayloadLoaders.loadTaskRemindersForTasks(db, taskIds: ids)
      collected.append(
        contentsOf: try SwiftLorvexTaskDeserializers.tasks(taskJSON).map { task in
          var exported = ExportTask(from: task)
          if let reminders = remindersByTaskID[task.id] {
            exported.reminders = reminders.map { Self.exportTaskReminder(from: $0.1) }
              .sorted { lhs, rhs in
                if lhs.reminderAt == rhs.reminderAt { return lhs.id < rhs.id }
                return lhs.reminderAt < rhs.reminderAt
              }
          }
          return exported
        })
      if ids.count < LorvexDataExportWindow.taskPageSize { break }
      let next = offset + LorvexDataExportWindow.taskPageSize
      guard next > offset else { break }
      offset = next
    }
    return collected
  }

  private static func exportTaskReminder(from payload: JSONValue) -> ExportTaskReminder {
    let object = SwiftLorvexTaskDeserializers.lowerObject(payload)
    return ExportTaskReminder(
      id: object["id"] as? String ?? "",
      reminderAt: object["reminder_at"] as? String ?? "",
      dismissedAt: object["dismissed_at"] as? String,
      cancelledAt: object["cancelled_at"] as? String,
      createdAt: object["created_at"] as? String,
      originalLocalTime: object["original_local_time"] as? String,
      originalTz: object["original_tz"] as? String)
  }

  public func loadCalendarEventsForDataExport() async throws -> [ExportCalendarEvent] {
    try await loadCalendarBundleForDataExport().events
  }

  public func loadCalendarBundleForDataExport() async throws -> ExportCalendarBundle {
    try read { db in
      let cutovers = try Self.calendarSeriesCutoversForDataExport(db)
      Self.afterCalendarCutoverExportReadForTesting?()
      let events = try Self.calendarEventsForDataExport(db)
      try Self.validateCalendarBundleForDataExport(
        db, cutovers: cutovers, events: events)
      return ExportCalendarBundle(cutovers: cutovers, events: events)
    }
  }

  /// Fail rather than emit an archive that the native importer cannot restore.
  /// Boundary-first CloudKit apply may expose an active cutover before its
  /// segment event arrives; callers can retry once that transient gap closes.
  /// Deleted boundaries deliberately need no event row.
  static func validateCalendarBundleForDataExport(
    _ db: Database,
    cutovers: [ExportCalendarSeriesCutover],
    events: [ExportCalendarEvent]
  ) throws {
    let orphanedSegmentMarker = try Int.fetchOne(
      db,
      sql: """
        SELECT 1
        FROM calendar_events event
        LEFT JOIN calendar_series_cutovers cutover
          ON cutover.id = event.series_cutover_id
        WHERE event.series_cutover_id IS NOT NULL AND cutover.id IS NULL
        LIMIT 1
        """) != nil
    guard !orphanedSegmentMarker else {
      throw LorvexCoreError.validation(
        field: "calendarEvents",
        message: "Calendar sync is still applying a recurring-series boundary. Retry the export after sync finishes.")
    }

    let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
    for cutover in cutovers where cutover.state == CalendarSeriesCutoverState.active.rawValue {
      guard let segment = eventsByID[cutover.id],
        segment.id == cutover.id,
        segment.seriesCutoverId == cutover.id,
        segment.seriesId == nil,
        segment.recurrenceInstanceDate == nil,
        segment.occurrenceState == nil
      else {
        throw LorvexCoreError.validation(
          field: "calendarEvents",
          message: "Calendar sync is still applying a recurring-series segment. Retry the export after sync finishes.")
      }
    }
  }

  static func calendarEventsForDataExport(
    _ db: Database
  ) throws -> [ExportCalendarEvent] {
    var collected: [ExportCalendarEvent] = []
    var offset: UInt32 = 0
    while true {
      let rows = try CalendarTimelineQueries.listCalendarEventRowsForNativeExport(
        db,
        limit: LorvexDataExportWindow.calendarPageSize,
        offset: offset)
      if rows.isEmpty { break }
      collected.append(
        contentsOf: rows.map { row in
          ExportCalendarEvent(
            from: row,
            attendees: SwiftLorvexCalendarDeserializers.attendees(fromJSONString: row.attendees))
        })
      if rows.count < Int(LorvexDataExportWindow.calendarPageSize) { break }
      let next = offset + LorvexDataExportWindow.calendarPageSize
      guard next > offset else { break }
      offset = next
    }
    return collected
  }

  static func calendarSeriesCutoversForDataExport(
    _ db: Database
  ) throws -> [ExportCalendarSeriesCutover] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, lineage_root_id, cutover_date, state
        FROM calendar_series_cutovers
        ORDER BY lineage_root_id ASC, cutover_date ASC, id ASC
        """)
    return rows.map { row in
      ExportCalendarSeriesCutover(
        id: row["id"], lineageRootId: row["lineage_root_id"],
        cutoverDate: row["cutover_date"], state: row["state"])
    }
  }

  public func loadTagsForDataExport() async throws -> [ExportTag] {
    try read { db in try Self.tagsForDataExport(db) }
  }

  public func loadCurrentFocusForDataExport() async throws -> [ExportCurrentFocus] {
    try read { db in try Self.currentFocusForDataExport(db) }
  }

  public func loadFocusSchedulesForDataExport() async throws -> [ExportFocusSchedule] {
    try read { db in try Self.focusSchedulesForDataExport(db, includeProviderBlocks: true) }
  }

  public func loadFocusSchedulesForAIDataExport() async throws -> [ExportFocusSchedule] {
    try read { db in
      // Read the tier and the schedule aggregate in one transaction. A
      // concurrent downgrade therefore cannot leave this export with a tier
      // sampled before the blocks it governs.
      let accessMode = try DeviceStateRepo.readCalendarAiAccessMode(db)
      return try Self.focusSchedulesForDataExport(
        db, includeProviderBlocks: accessMode.includesProvider)
    }
  }

  public func loadTaskCalendarEventLinksForDataExport() async throws -> [ExportTaskCalendarEventLink] {
    try read { db in try Self.taskCalendarEventLinksForDataExport(db) }
  }

  public func loadMemoryForDataExport() async throws -> [ExportMemoryEntry] {
    try read { db in try Self.memoryForDataExport(db) }
  }

  static func tagsForDataExport(_ db: Database) throws -> [ExportTag] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, display_name, color, created_at, updated_at
        FROM tags
        ORDER BY lookup_key ASC, id ASC
        """)
    return rows.map { row in
      ExportTag(
        id: row[0], displayName: row[1], color: row[2],
        createdAt: row[3], updatedAt: row[4])
    }
  }

  static func currentFocusForDataExport(_ db: Database) throws -> [ExportCurrentFocus] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT date, briefing, timezone, created_at, updated_at
        FROM current_focus
        ORDER BY date ASC
        """)
    let taskIDsByDate = try currentFocusTaskIDsByDate(db)
    return rows.map { row in
      let date: String = row[0]
      return ExportCurrentFocus(
        date: date, briefing: row[1], timezone: row[2],
        taskIDs: taskIDsByDate[date] ?? [], createdAt: row[3], updatedAt: row[4])
    }
  }

  static func taskCalendarEventLinksForDataExport(
    _ db: Database
  ) throws -> [ExportTaskCalendarEventLink] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT task_id, calendar_event_id, created_at, updated_at
        FROM task_calendar_event_links
        ORDER BY task_id ASC, calendar_event_id ASC
        """)
    return rows.map { row in
      ExportTaskCalendarEventLink(
        taskID: row[0], calendarEventID: row[1], createdAt: row[2], updatedAt: row[3])
    }
  }

  static func memoryForDataExport(_ db: Database) throws -> [ExportMemoryEntry] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, key, content, updated_at
        FROM memories
        ORDER BY key ASC
        """)
    return rows.map { row in
      ExportMemoryEntry(id: row[0], key: row[1], content: row[2], updatedAt: row[3])
    }
  }

  private static func currentFocusTaskIDsByDate(_ db: Database) throws -> [String: [String]] {
    let rows = try Row.fetchAll(
      db,
      sql: "SELECT date, task_id FROM current_focus_items ORDER BY date ASC, position ASC")
    var out: [String: [String]] = [:]
    for row in rows {
      let date: String = row[0]
      let taskID: String = row[1]
      out[date, default: []].append(taskID)
    }
    return out
  }

  static func focusSchedulesForDataExport(
    _ db: Database, includeProviderBlocks: Bool
  ) throws -> [ExportFocusSchedule] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT date, rationale, timezone, created_at, updated_at
        FROM focus_schedule
        ORDER BY date ASC
        """)
    let blocksByDate = try focusScheduleBlocksByDate(
      db, includeProviderBlocks: includeProviderBlocks)
    return rows.map { row in
      let date: String = row[0]
      return ExportFocusSchedule(
        date: date,
        rationale: row[1],
        timezone: row[2],
        blocks: blocksByDate[date] ?? [],
        createdAt: row[3],
        updatedAt: row[4])
    }
  }

  private static func focusScheduleBlocksByDate(
    _ db: Database, includeProviderBlocks: Bool
  ) throws
    -> [String: [ExportFocusScheduleBlock]]
  {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT date, position, block_type, start_minutes, end_minutes, task_id, calendar_event_id, event_source, title
        FROM focus_schedule_blocks
        ORDER BY date ASC, position ASC
        """)
    var out: [String: [ExportFocusScheduleBlock]] = [:]
    for row in rows {
      let date: String = row[0]
      let position: Int64 = row[1]
      let start: Int64 = row[3]
      let end: Int64 = row[4]
      let calendarEventID: String? = row[6]
      let eventSource = (row[7] as String?).flatMap(FocusScheduleEventSource.parse)
      guard includeProviderBlocks || eventSource != .provider else { continue }
      let normalized = FocusScheduleSnapshot.normalizeBlockForExternalTransfer(
        eventSource: eventSource, calendarEventId: calendarEventID, title: row[8])
      // Filtering a provider block can leave gaps in the persisted positions.
      // AI export remains valid strict-import input by compacting the retained
      // order to zero-based contiguous positions.
      let exportedPosition = includeProviderBlocks ? Int(position) : (out[date]?.count ?? 0)
      out[date, default: []].append(
        ExportFocusScheduleBlock(
          position: exportedPosition,
          blockType: row[2],
          startMinutes: Int(start),
          endMinutes: Int(end),
          taskID: row[5],
          calendarEventID: normalized.calendarEventId,
          eventSource: eventSource,
          title: normalized.title))
    }
    return out
  }

}
