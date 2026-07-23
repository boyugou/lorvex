import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// `LorvexFocusPlanningServicing` over the pure-Swift core.
///
/// Current-focus reads project the `current_focus` header (briefing/timezone)
/// plus its position-ordered `current_focus_items` task ids. Writes orchestrate
/// `CurrentFocusItemsRepo` directly through the `+WriteSurface` adapter: one
/// HLC version per top-level mutation stamps both the header upsert (strict
/// `>` LWW) and the child rebuild (`>=`, a benign re-stamp).
///
/// Schedule reads/proposals run through `FocusScheduleProposal`; saves
/// materialize `focus_schedule_blocks` after upserting the `focus_schedule`
/// header. Mapping reuses `SwiftLorvexFocusDeserializers`.
extension SwiftLorvexCoreService {
  public func loadFocusSchedule(date: String) async throws -> FocusSchedule? {
    try read { db in try Self.focusScheduleFromStore(db, date: date) }
  }

  public func loadFocusScheduleForAI(date: String) async throws -> FocusSchedule? {
    try read { db in
      guard let schedule = try Self.focusScheduleFromStore(db, date: date) else { return nil }
      let accessMode = try DeviceStateRepo.readCalendarAiAccessMode(db)
      return Self.focusScheduleForAI(schedule, accessMode: accessMode)
    }
  }

  public func proposeFocusSchedule(date: String) async throws -> FocusSchedule {
    try await proposeFocusSchedule(
      date: date, workingHoursStart: nil, workingHoursEnd: nil, includeCalendarEvents: nil)
  }

  public func proposeFocusSchedule(
    date: String,
    workingHoursStart: String?,
    workingHoursEnd: String?,
    includeCalendarEvents: Bool?
  ) async throws -> FocusSchedule {
    try read { db in
      let anchorTimezone =
        try WorkflowTimezone.activeTimezoneName(db) ?? TimeZone.current.identifier
      // Honor the effective calendar AI-access tier so a busy/off proposal
      // redacts provider detail even if a full-detail row somehow survives at
      // rest — defense in depth behind ingest-time redaction + downgrade purge.
      // Read inside the same transaction; a malformed persisted tier fails the
      // read (fail closed) rather than leaking full detail.
      let accessMode = try DeviceStateRepo.readCalendarAiAccessMode(db)
      let proposal = try FocusScheduleProposal.proposeFocusSchedule(
        db, date: date, anchorTimezone: anchorTimezone, accessMode: accessMode,
        workingHoursStart: workingHoursStart, workingHoursEnd: workingHoursEnd,
        includeCalendarEvents: includeCalendarEvents ?? true)
      return SwiftLorvexFocusDeserializers.schedule(proposal, timezone: anchorTimezone)
    }
  }

  public func saveFocusSchedule(date: String, blocks: [FocusScheduleBlock], rationale: String?)
    async throws -> FocusSchedule
  {
    try saveFocusScheduleWithReceipt(date: date, blocks: blocks, rationale: rationale).schedule
  }

  public func saveFocusScheduleForMcp(
    date: String, blocks: [FocusScheduleBlock], rationale: String?
  ) async throws -> McpFocusScheduleSaveReceipt {
    try saveFocusScheduleWithReceipt(date: date, blocks: blocks, rationale: rationale)
  }

  private func saveFocusScheduleWithReceipt(
    date: String, blocks: [FocusScheduleBlock], rationale: String?
  ) throws -> McpFocusScheduleSaveReceipt {
    try withWrite { db, hlc, deviceId in
      try Self.validateLocalScheduleBlockBudgets(count: blocks.count, titles: blocks.map(\.title))
      let timezone =
        try WorkflowTimezone.activeTimezoneName(db) ?? TimeZone.current.identifier
      let version = hlc.nextVersionString()
      let now = SyncTimestampFormat.syncTimestampNow()
      try FocusScheduleBlocksRepo.upsertFocusScheduleHeader(
        db, date: date, rationale: rationale, timezone: timezone, version: version, now: now)
      let entries = try blocks.map { block -> FocusScheduleBlocksRepo.ScheduleBlockEntry in
        let validated = try Self.validatedScheduleBlock(block)
        let startMinutes = try Self.minutesOfDay(block.startTime)
        let endMinutes = try Self.minutesOfDay(block.endTime)
        // Reject inverted/zero-length spans at the boundary rather than letting
        // the repo silently clamp end up to start (a 0-minute block).
        guard endMinutes > startMinutes else {
          throw LorvexCoreError.validation(
            field: "end_time",
            message:
              "Focus schedule block end '\(block.endTime)' must be after its start '\(block.startTime)'.")
        }
        return FocusScheduleBlocksRepo.ScheduleBlockEntry(
          blockType: validated.blockType,
          startMinutes: Int64(startMinutes),
          endMinutes: Int64(endMinutes),
          taskId: validated.taskId, calendarEventId: validated.calendarEventId,
          eventSource: validated.eventSource, title: block.title)
      }
      if let missing = try Self.missingLiveScheduleBlockReference(db, entries: entries) {
        throw LorvexCoreError.unsupportedOperation(
          "Focus schedule block references unavailable \(missing).")
      }
      try FocusScheduleBlocksRepo.materializeScheduleBlocks(
        db, date: date, blocks: entries)
      try self.enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule, entityId: date)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opUpsert, entityType: EntityName.focusSchedule,
          entityId: date, summary: "Saved focus schedule for \(date)"),
        deviceId: deviceId)
      let focusTaskIDs = Self.uniqueTaskIDs(from: entries)
      let currentPlan: CurrentFocusPlan?
      if !focusTaskIDs.isEmpty {
        let existing = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
        currentPlan = try Self.writeCurrentFocus(
          db,
          hlc: hlc,
          deviceId: deviceId,
          service: self,
          date: date,
          taskIDs: Self.mergedTaskIDs(existing: existing, adding: focusTaskIDs),
          validateTaskIDs: focusTaskIDs,
          briefing: rationale,
          timezone: timezone)
      } else if let header = try Self.currentFocusHeader(db, date: date) {
        let stored = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
        let visible = try Self.filterExistingNonArchivedTaskIDs(db, ids: stored)
        currentPlan = SwiftLorvexFocusDeserializers.currentFocusPlan(
          date: date, taskIDs: visible, briefing: header.briefing, timezone: header.timezone,
          localChangeSequence: Int(try LocalChangeSeq.read(db)))
      } else {
        currentPlan = nil
      }
      let storedBlocks = try Self.focusScheduleBlockRows(db, date: date)
      let schedule = SwiftLorvexFocusDeserializers.schedule(
        date: date, rationale: rationale, timezone: timezone, blocks: storedBlocks)
      return McpFocusScheduleSaveReceipt(
        schedule: schedule,
        currentFocus: try Self.mcpCurrentFocusProjection(db, plan: currentPlan))
    }
  }

  public func clearFocusSchedule(date: String) async throws {
    try withWrite { db, hlc, deviceId in
      let priorPayload: JSONValue?
      do {
        priorPayload = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.focusSchedule, entityId: date)
      } catch EnqueueError.entityNotFound {
        // No schedule for the date — nothing to tombstone; the DELETE below is a
        // no-op and we emit no sync envelope or changelog row.
        priorPayload = nil
      }
      // Deleting the focus_schedule header cascades its focus_schedule_blocks
      // (FK ON DELETE CASCADE), so the aggregate is fully removed in one step.
      try db.execute(sql: "DELETE FROM focus_schedule WHERE date = ?", arguments: [date])
      if db.changesCount > 0 {
        if let priorPayload {
          try self.enqueueDelete(
            db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule, entityId: date,
            payload: priorPayload)
        }
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opDelete, entityType: EntityName.focusSchedule,
            entityId: date, summary: "Cleared focus schedule for \(date)"),
          deviceId: deviceId)
      }
    }
  }

  private static func focusScheduleHeader(
    _ db: Database, date: String
  ) throws -> (rationale: String?, timezone: String?)? {
    guard
      let row = try Row.fetchOne(
        db, sql: "SELECT rationale, timezone FROM focus_schedule WHERE date = ?", arguments: [date])
    else { return nil }
    return (row[0], row[1])
  }

  private static func focusScheduleFromStore(
    _ db: Database, date: String
  ) throws -> FocusSchedule? {
    guard let header = try focusScheduleHeader(db, date: date) else { return nil }
    let blocks = try focusScheduleBlockRows(db, date: date)
    return SwiftLorvexFocusDeserializers.schedule(
      date: date, rationale: header.rationale, timezone: header.timezone, blocks: blocks)
  }

  /// Project a persisted schedule onto the calendar AI-access contract without
  /// mutating storage. Human-facing reads retain every block; only this copy is
  /// filtered, so an AI read can never become a lossy UI load/save cycle.
  private static func focusScheduleForAI(
    _ schedule: FocusSchedule, accessMode: CalendarAiAccessMode
  ) -> FocusSchedule {
    guard accessMode != .fullDetails else { return schedule }
    var projected = schedule
    projected.blocks = schedule.blocks.compactMap { block in
      guard block.eventSource == .provider else { return block }
      guard accessMode == .busyOnly else { return nil }
      var occupancy = block
      occupancy.calendarEventID = nil
      occupancy.title = "Event"
      return occupancy
    }
    return projected
  }

  private static func focusScheduleBlockRows(
    _ db: Database, date: String
  ) throws -> [FocusScheduleBlock] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT block_type, start_minutes, end_minutes, task_id, calendar_event_id, event_source, title \
        FROM focus_schedule_blocks
        WHERE date = ?
        ORDER BY position ASC
        """,
      arguments: [date])
    return rows.map { row in
      let startMinutes: Int64 = row[1]
      let endMinutes: Int64 = row[2]
      return FocusScheduleBlock(
        blockType: row[0],
        startTime: TimeOfDay.fromMinutesSaturating(Int(startMinutes)).asString,
        endTime: TimeOfDay.fromMinutesSaturating(Int(endMinutes)).asString,
        taskID: row[3], calendarEventID: row[4],
        eventSource: (row[5] as String?).flatMap(FocusScheduleEventSource.parse),
        title: row[6])
    }
  }

  /// Validate one save-time focus block against the schema's
  /// `(block_type, task_id, calendar_event_id, event_source)` contract and normalize empty
  /// ids to nil,
  /// turning what would otherwise be an opaque SQLite CHECK failure (or a stored
  /// dangling reference) into a precise error. `task` requires a non-empty
  /// `task_id` and no event fields; `event` has explicit provenance and only a
  /// canonical event may carry `calendar_event_id`; `buffer` carries neither.
  /// Local-write budgets for a focus schedule's block set: the block count and
  /// each freeform title are byte-budgeted (``PayloadByteBudget``) so a
  /// locally-authored `focus_schedule` payload provably fits the sync byte cap.
  /// Shared by ``saveFocusSchedule(date:blocks:rationale:)`` and the backup
  /// import path; the sync applier deliberately bypasses it (inbound size is
  /// bounded by the wire cap, and a peer's legal payload must never wedge).
  static func validateLocalScheduleBlockBudgets(count: Int, titles: [String?]) throws {
    guard count <= PayloadByteBudget.maxScheduleBlocks else {
      throw LorvexCoreError.validation(
        field: "blocks",
        message: "A focus schedule holds at most \(PayloadByteBudget.maxScheduleBlocks) "
          + "blocks (got \(count)).")
    }
    for title in titles {
      guard let title else { continue }
      if case .failure = PayloadByteBudget.validateEscapedBudget(
        title, field: "title", budget: PayloadByteBudget.scheduleBlockTitleEscapedBytes)
      {
        throw LorvexCoreError.validation(
          field: "title",
          message: "A focus schedule block title exceeds the maximum stored size of "
            + "\(PayloadByteBudget.scheduleBlockTitleEscapedBytes) bytes.")
      }
    }
  }

  private static func validatedScheduleBlock(
    _ block: FocusScheduleBlock
  ) throws -> (
    blockType: String, taskId: String?, calendarEventId: String?,
    eventSource: FocusScheduleEventSource?
  ) {
    let blockType = block.blockType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let taskId = block.taskID.trimmedNilIfEmpty
    let calendarEventId = block.calendarEventID.trimmedNilIfEmpty
    switch blockType {
    case "task":
      guard let taskId, SyncEntityId.isCanonicalUuid(taskId) else {
        throw LorvexCoreError.validation(
          field: "task_id",
          message: "Focus schedule 'task' block requires a canonical task UUID.")
      }
      guard calendarEventId == nil else {
        throw LorvexCoreError.validation(
          field: "event_id",
          message: "Focus schedule 'task' block must not set event_id.")
      }
      guard block.eventSource == nil else {
        throw LorvexCoreError.validation(
          field: "event_source",
          message: "Focus schedule 'task' block must not set event_source.")
      }
      return ("task", taskId, nil, nil)
    case "event":
      guard taskId == nil else {
        throw LorvexCoreError.validation(
          field: "task_id",
          message: "Focus schedule 'event' block must not set task_id.")
      }
      guard let eventSource = block.eventSource else {
        throw LorvexCoreError.validation(
          field: "event_source",
          message:
            "Focus schedule 'event' block requires event_source: canonical, provider, or freeform.")
      }
      switch eventSource {
      case .canonical:
        guard let calendarEventId, SyncEntityId.isCanonicalUuid(calendarEventId) else {
          throw LorvexCoreError.validation(
            field: "event_id",
            message: "Canonical focus event block requires a canonical calendar-event UUID.")
        }
      case .provider, .freeform:
        guard calendarEventId == nil else {
          throw LorvexCoreError.validation(
            field: "event_id",
            message: "Provider and freeform focus event blocks must not set event_id.")
        }
      }
      return ("event", nil, calendarEventId, eventSource)
    case "buffer":
      guard taskId == nil, calendarEventId == nil else {
        throw LorvexCoreError.validation(
          field: nil,
          message: "Focus schedule 'buffer' block must not set task_id or event_id.")
      }
      guard block.eventSource == nil else {
        throw LorvexCoreError.validation(
          field: "event_source",
          message: "Focus schedule 'buffer' block must not set event_source.")
      }
      return ("buffer", nil, nil, nil)
    default:
      throw LorvexCoreError.validation(
        field: "block_type",
        message: "Focus schedule block_type '\(block.blockType)' is invalid. Use task, buffer, or event.")
    }
  }

  /// Return the first unavailable canonical endpoint referenced by a locally
  /// authored/imported schedule. Task and canonical-event ids are soft in the
  /// aggregate schema because CloudKit may deliver the schedule first, but a
  /// local write has a complete transactional view and must not deliberately
  /// materialize a dangling reference. Archived tasks are unavailable just like
  /// missing tasks: Trash is an absorbing eligibility boundary for day plans.
  /// Provider/freeform event blocks carry no canonical endpoint and are
  /// therefore preserved.
  static func missingLiveScheduleBlockReference(
    _ db: Database, entries: [FocusScheduleBlocksRepo.ScheduleBlockEntry]
  ) throws -> String? {
    let taskIds = Set(entries.compactMap { $0.blockType == "task" ? $0.taskId : nil })
    if let missing = try firstUnavailableScheduleTaskReference(db, ids: taskIds) {
      return "task '\(missing)'"
    }
    let eventIds = Set(
      entries.compactMap {
        $0.blockType == "event" && $0.eventSource == .canonical ? $0.calendarEventId : nil
      })
    if let missing = try firstMissingScheduleReference(
      db, ids: eventIds, table: "calendar_events")
    {
      return "calendar event '\(missing)'"
    }
    return nil
  }

  private static func firstUnavailableScheduleTaskReference(
    _ db: Database, ids: Set<String>
  ) throws -> String? {
    guard !ids.isEmpty else { return nil }
    let sorted = ids.sorted()
    let placeholders = sorted.map { _ in "?" }.joined(separator: ", ")
    let live = Set(
      try String.fetchAll(
        db,
        sql:
          "SELECT id FROM tasks WHERE archived_at IS NULL AND id IN (\(placeholders))",
        arguments: StatementArguments(sorted)))
    return sorted.first(where: { !live.contains($0) })
  }

  private static func firstMissingScheduleReference(
    _ db: Database, ids: Set<String>, table: String
  ) throws -> String? {
    guard !ids.isEmpty else { return nil }
    ValidationSQL.assertSafeSQLIdentifier(table)
    let sorted = ids.sorted()
    let placeholders = sorted.map { _ in "?" }.joined(separator: ", ")
    let found = Set(
      try String.fetchAll(
        db, sql: "SELECT id FROM \(table) WHERE id IN (\(placeholders))",
        arguments: StatementArguments(sorted)))
    return sorted.first(where: { !found.contains($0) })
  }

  private static func uniqueTaskIDs(
    from entries: [FocusScheduleBlocksRepo.ScheduleBlockEntry]
  ) -> [String] {
    var seen = Set<String>()
    var ids: [String] = []
    for id in entries.compactMap(\.taskId) where seen.insert(id).inserted {
      ids.append(id)
    }
    return ids
  }

  private static func mergedTaskIDs(existing: [String], adding additions: [String]) -> [String] {
    var seen = Set<String>()
    var ids: [String] = []
    for id in existing + additions where seen.insert(id).inserted {
      ids.append(id)
    }
    return ids
  }

  /// Parse an `HH:MM` block boundary to a minute-of-day integer, rejecting
  /// malformed input with a precise validation error.
  private static func minutesOfDay(_ raw: String) throws -> Int {
    switch TimeOfDay.parse(raw) {
    case .success(let value): return value.minutesOfDay
    case .failure:
      throw LorvexCoreError.validation(
        field: nil,
        message: "Focus schedule block time '\(raw)' is not a valid HH:MM value.")
    }
  }
}
