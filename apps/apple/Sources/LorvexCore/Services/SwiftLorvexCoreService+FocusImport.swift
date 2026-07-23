import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  public func importCurrentFocus(_ focus: ExportCurrentFocus) async throws {
    let date = try Self.requiredFocusDate(focus.date, field: "focus date")
    let now = SyncTimestampFormat.syncTimestampNow()
    try withWrite { db, hlc, deviceId in
      try self.writeImportedCurrentFocusInTx(
        db, hlc: hlc, deviceId: deviceId, date: date, focus: focus, now: now)
    }
  }

  public func importCurrentFocusIfAbsent(_ focus: ExportCurrentFocus) async throws -> Bool {
    let date = try Self.requiredFocusDate(focus.date, field: "focus date")
    let now = SyncTimestampFormat.syncTimestampNow()
    return try withWrite { db, hlc, deviceId in
      // A current-focus plan is a singleton per date. A non-destructive restore
      // skips a date a concurrent write already holds (no overwrite) and one the
      // user cleared after the backup (no resurrection at a fresh dominating
      // import HLC). Both checks share this write lock with the write.
      if try Int.fetchOne(db, sql: "SELECT 1 FROM current_focus WHERE date = ?", arguments: [date])
        != nil
      {
        return false
      }
      if try Tombstone.isTombstoned(db, entityType: EntityName.currentFocus, entityId: date) {
        return false
      }
      let taskIDs = try Self.canonicalImportedEntityIDs(
        focus.taskIDs, kind: .task, field: "current focus taskIDs")
      // Root task records restore first. A newer task tombstone can still win,
      // leaving this stale aggregate without one of its endpoints; skip the
      // entire plan rather than publish a dangling soft reference at a fresh HLC.
      guard try Self.missingImportedCurrentFocusTask(db, taskIDs: taskIDs) == nil else {
        return false
      }
      try self.writeImportedCurrentFocusInTx(
        db, hlc: hlc, deviceId: deviceId, date: date, focus: focus, now: now)
      return true
    }
  }

  /// Upsert one imported current-focus header and rebuild its child items, then
  /// enqueue its sync envelope, inside the caller's transaction. Shared by
  /// ``importCurrentFocus(_:)`` (overwrite-on-reimport) and
  /// ``importCurrentFocusIfAbsent(_:)`` (skip-if-present/tombstoned); the latter
  /// guards the date before calling, so its upsert path only ever inserts.
  func writeImportedCurrentFocusInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, date: String, focus: ExportCurrentFocus,
    now: String
  ) throws {
    let taskIDs = try Self.canonicalImportedEntityIDs(
      focus.taskIDs, kind: .task, field: "current focus taskIDs")
    // Import is local authoring: the same PayloadByteBudget bounds the
    // interactive write funnel enforces apply here, so a restored plan can
    // never exceed what the app itself could have written.
    guard taskIDs.count <= PayloadByteBudget.maxFocusTasks else {
      throw LorvexCoreError.validation(
        field: "taskIDs",
        message: "A focus plan holds at most \(PayloadByteBudget.maxFocusTasks) tasks "
          + "(got \(taskIDs.count)).")
    }
    if let missing = try Self.missingImportedCurrentFocusTask(db, taskIDs: taskIDs) {
      throw LorvexCoreError.unsupportedOperation(
        "Current focus references unknown or archived task '\(missing)'.")
    }
    if let briefing = focus.briefing,
      case .failure = PayloadByteBudget.validateEscapedBudget(
        briefing, field: "briefing", budget: PayloadByteBudget.dayPlanTextEscapedBytes)
    {
      throw LorvexCoreError.validation(
        field: "briefing",
        message: "The focus briefing exceeds the maximum stored size of "
          + "\(PayloadByteBudget.dayPlanTextEscapedBytes) bytes.")
    }
    let createdAt = try Self.canonicalImportTimestamp(
      focus.createdAt, field: "current focus createdAt", fallback: now)
    let updatedAt = try Self.canonicalImportTimestamp(
      focus.updatedAt, field: "current focus updatedAt", fallback: now)
    // LWW-gate on `version` so an import never REGRESSES a future-stamped peer
    // row; on a refused conflict `staleVersion` routes through the
    // `runWriteAttempt` retry so the import wins at a dominating version. The
    // check runs BEFORE the child-item rewrite so a refused import leaves the
    // peer's focus items intact. See `importCalendarEvent` for full rationale.
    try db.execute(
        sql: """
          INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(date) DO UPDATE SET
            briefing = excluded.briefing,
            timezone = excluded.timezone,
            version = excluded.version,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at
          WHERE excluded.version > current_focus.version
          """,
        arguments: [
          date, focus.briefing, focus.timezone, hlc.nextVersionString(),
          createdAt, updatedAt,
        ])
      if db.changesCount == 0 {
        throw StoreError.staleVersion(entity: EntityName.currentFocus, id: date)
      }
      try db.execute(sql: "DELETE FROM current_focus_items WHERE date = ?", arguments: [date])
      for (position, taskID) in taskIDs.enumerated() {
        try db.execute(
          sql: "INSERT INTO current_focus_items (date, position, task_id) VALUES (?, ?, ?)",
          arguments: [date, position, taskID])
      }
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .currentFocus, entityId: date)
  }

  /// Completed/cancelled tasks remain valid historical focus members; only a
  /// missing or archived (Trash) endpoint makes an imported aggregate dangling.
  private static func missingImportedCurrentFocusTask(
    _ db: Database, taskIDs: [String]
  ) throws -> String? {
    let existing = Set(try filterExistingNonArchivedTaskIDs(db, ids: taskIDs))
    return taskIDs.first { !existing.contains($0) }
  }

  public func importFocusSchedule(_ schedule: ExportFocusSchedule) async throws {
    let date = try Self.requiredFocusDate(schedule.date, field: "schedule date")
    let now = SyncTimestampFormat.syncTimestampNow()
    try withWrite { db, hlc, deviceId in
      let blocks = try Self.importedFocusScheduleBlocks(schedule)
      if let missing = try Self.missingLiveScheduleBlockReference(db, entries: blocks) {
        throw LorvexCoreError.unsupportedOperation(
          "Focus schedule block references unavailable \(missing).")
      }
      try self.writeImportedFocusScheduleInTx(
        db, hlc: hlc, deviceId: deviceId, date: date, schedule: schedule,
        blocks: blocks, now: now)
    }
  }

  public func importFocusScheduleIfAbsent(_ schedule: ExportFocusSchedule) async throws -> Bool {
    let date = try Self.requiredFocusDate(schedule.date, field: "schedule date")
    let now = SyncTimestampFormat.syncTimestampNow()
    return try withWrite { db, hlc, deviceId in
      // A focus schedule is a singleton per date. A non-destructive restore skips
      // a date a concurrent write already holds (no overwrite) and one the user
      // cleared after the backup (no resurrection at a fresh dominating import
      // HLC). Both checks share this write lock with the write.
      if try Int.fetchOne(db, sql: "SELECT 1 FROM focus_schedule WHERE date = ?", arguments: [date])
        != nil
      {
        return false
      }
      if try Tombstone.isTombstoned(db, entityType: EntityName.focusSchedule, entityId: date) {
        return false
      }
      let blocks = try Self.importedFocusScheduleBlocks(schedule)
      // Tasks/calendar events are restored before schedules, under the same
      // app-level import gate. If an endpoint is still absent, a local tombstone
      // or concurrent delete won and the stale schedule must be skipped as one
      // semantic unit — never materialized with a copied title and dangling id.
      guard try Self.missingLiveScheduleBlockReference(db, entries: blocks) == nil else {
        return false
      }
      try self.writeImportedFocusScheduleInTx(
        db, hlc: hlc, deviceId: deviceId, date: date, schedule: schedule,
        blocks: blocks, now: now)
      return true
    }
  }

  /// Upsert one imported focus-schedule header and rebuild its blocks, then
  /// enqueue its sync envelope, inside the caller's transaction. Shared by
  /// ``importFocusSchedule(_:)`` (overwrite-on-reimport) and
  /// ``importFocusScheduleIfAbsent(_:)`` (skip-if-present/tombstoned); the latter
  /// guards the date before calling, so its upsert path only ever inserts.
  func writeImportedFocusScheduleInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, date: String,
    schedule: ExportFocusSchedule,
    blocks: [FocusScheduleBlocksRepo.ScheduleBlockEntry], now: String
  ) throws {
    if let rationale = schedule.rationale,
      case .failure = PayloadByteBudget.validateEscapedBudget(
        rationale, field: "rationale", budget: PayloadByteBudget.dayPlanTextEscapedBytes)
    {
      throw LorvexCoreError.validation(
        field: "rationale",
        message: "The focus schedule rationale exceeds the maximum stored size of "
          + "\(PayloadByteBudget.dayPlanTextEscapedBytes) bytes.")
    }
    let createdAt = try Self.canonicalImportTimestamp(
      schedule.createdAt, field: "focus schedule createdAt", fallback: now)
    let updatedAt = try Self.canonicalImportTimestamp(
      schedule.updatedAt, field: "focus schedule updatedAt", fallback: now)
    // LWW-gate on `version` (see `importCurrentFocus`): a refused import must
    // not regress a future-stamped peer schedule nor wipe its blocks.
    try db.execute(
        sql: """
          INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(date) DO UPDATE SET
            rationale = excluded.rationale,
            timezone = excluded.timezone,
            version = excluded.version,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at
          WHERE excluded.version > focus_schedule.version
          """,
        arguments: [
          date, schedule.rationale, schedule.timezone, hlc.nextVersionString(),
          createdAt, updatedAt,
        ])
      if db.changesCount == 0 {
        throw StoreError.staleVersion(entity: EntityName.focusSchedule, id: date)
      }
      try Self.validateLocalScheduleBlockBudgets(
        count: blocks.count, titles: blocks.map(\.title))
      try FocusScheduleBlocksRepo.materializeScheduleBlocks(
        db, date: date, blocks: blocks)
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule, entityId: date)
  }

  private static func importedFocusScheduleBlocks(
    _ schedule: ExportFocusSchedule
  ) throws -> [FocusScheduleBlocksRepo.ScheduleBlockEntry] {
    let sortedBlocks = schedule.blocks.sorted(by: { $0.position < $1.position })
    for (expectedPosition, block) in sortedBlocks.enumerated()
    where block.position != expectedPosition {
      throw LorvexCoreError.unsupportedOperation(
        "Focus schedule block positions must be unique and contiguous from zero.")
    }
    return try sortedBlocks.map { block in
      let eventSource = try validateFocusBlock(block)
      let normalized = FocusScheduleSnapshot.normalizeBlockForExternalTransfer(
        eventSource: eventSource, calendarEventId: block.calendarEventID, title: block.title)
      return FocusScheduleBlocksRepo.ScheduleBlockEntry(
        blockType: block.blockType,
        startMinutes: Int64(block.startMinutes),
        endMinutes: Int64(block.endMinutes),
        taskId: block.taskID,
        calendarEventId: normalized.calendarEventId,
        eventSource: eventSource,
        title: normalized.title)
    }
  }

  private static func requiredFocusText(_ raw: String, field: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A \(field) is required.")
    }
    return trimmed
  }

  private static func requiredFocusDate(_ raw: String, field: String) throws -> String {
    let value = try requiredFocusText(raw, field: field)
    guard case .success(let date) = IsoDate.parseIsoDate(value) else {
      throw LorvexCoreError.unsupportedOperation("\(field) must be a valid YYYY-MM-DD date.")
    }
    return date.canonicalString
  }

  private static func validateFocusBlock(_ block: ExportFocusScheduleBlock) throws
    -> FocusScheduleEventSource?
  {
    guard block.startMinutes >= 0, block.endMinutes > block.startMinutes, block.endMinutes <= 1440
    else {
      throw LorvexCoreError.unsupportedOperation("Focus block minutes are outside the allowed range.")
    }
    switch block.blockType {
    case "task":
      guard let taskID = block.taskID, SyncEntityId.isCanonicalUuid(taskID),
        block.calendarEventID == nil, block.eventSource == nil
      else {
        throw LorvexCoreError.unsupportedOperation(
          "Task focus block requires a canonical taskID and no event identity/source.")
      }
      return nil
    case "event":
      guard block.taskID == nil else {
        throw LorvexCoreError.unsupportedOperation("Event focus block must not set taskID.")
      }
      guard let source = block.eventSource else {
        throw LorvexCoreError.unsupportedOperation("Event focus block requires eventSource.")
      }
      switch source {
      case .canonical:
        guard let calendarEventID = block.calendarEventID,
          SyncEntityId.isCanonicalUuid(calendarEventID)
        else {
          throw LorvexCoreError.unsupportedOperation(
            "Canonical focus event block requires a canonical calendarEventID.")
        }
      case .provider, .freeform:
        guard block.calendarEventID == nil else {
          throw LorvexCoreError.unsupportedOperation(
            "Provider and freeform focus event blocks must not set calendarEventID.")
        }
      }
      return source
    case "buffer":
      guard block.taskID == nil, block.calendarEventID == nil, block.eventSource == nil else {
        throw LorvexCoreError.unsupportedOperation(
          "Buffer focus block must not set taskID, calendarEventID, or eventSource.")
      }
      return nil
    default:
      throw LorvexCoreError.unsupportedOperation("Unknown focus block type '\(block.blockType)'.")
    }
  }
}
