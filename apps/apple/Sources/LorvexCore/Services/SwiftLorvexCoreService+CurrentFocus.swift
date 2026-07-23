import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func loadCurrentFocus(date: String) async throws -> CurrentFocusPlan? {
    try read { db in
      guard let header = try Self.currentFocusHeader(db, date: date) else { return nil }
      let storedIDs = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
      let taskIDs = try Self.filterExistingNonArchivedTaskIDs(db, ids: storedIDs)
      return SwiftLorvexFocusDeserializers.currentFocusPlan(
        date: date, taskIDs: taskIDs, briefing: header.briefing,
        timezone: header.timezone, localChangeSequence: Int(try LocalChangeSeq.read(db)))
    }
  }

  public func setCurrentFocus(
    date: String,
    taskIDs: [LorvexTask.ID],
    briefing: String?,
    timezone: String
  ) async throws -> CurrentFocusPlan {
    try withWrite { db, hlc, deviceId in
      let resolvedTimezone = try Self.resolveFocusTimezone(db, timezone)
      return try Self.writeCurrentFocus(
        db, hlc: hlc, deviceId: deviceId, service: self, date: date,
        taskIDs: taskIDs, validateTaskIDs: taskIDs, briefing: briefing,
        timezone: resolvedTimezone)
    }
  }

  public func setCurrentFocusForMcp(
    date: String, taskIDs: [LorvexTask.ID], briefing: String?, timezone: String
  ) async throws -> McpCurrentFocusProjection {
    try withWrite { db, hlc, deviceId in
      let resolvedTimezone = try Self.resolveFocusTimezone(db, timezone)
      let plan = try Self.writeCurrentFocus(
        db, hlc: hlc, deviceId: deviceId, service: self, date: date,
        taskIDs: taskIDs, validateTaskIDs: taskIDs, briefing: briefing,
        timezone: resolvedTimezone)
      return try Self.mcpCurrentFocusProjection(db, plan: plan)
    }
  }

  public func addToCurrentFocus(
    date: String,
    taskIDs: [LorvexTask.ID],
    briefing: String?,
    timezone: String
  ) async throws -> CurrentFocusPlan {
    try withWrite { db, hlc, deviceId in
      let resolvedTimezone = try Self.resolveFocusTimezone(db, timezone)
      let existing = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
      var merged = existing
      var seen = Set(existing)
      for id in taskIDs where seen.insert(id).inserted {
        merged.append(id)
      }
      let header = try Self.currentFocusHeader(db, date: date)
      let resolvedBriefing = briefing ?? header?.briefing
      return try Self.writeCurrentFocus(
        db, hlc: hlc, deviceId: deviceId, service: self, date: date,
        taskIDs: merged, validateTaskIDs: taskIDs, briefing: resolvedBriefing,
        timezone: resolvedTimezone)
    }
  }

  public func addToCurrentFocusForMcp(
    date: String, taskIDs: [LorvexTask.ID], briefing: String?, timezone: String
  ) async throws -> McpCurrentFocusProjection {
    try withWrite { db, hlc, deviceId in
      let resolvedTimezone = try Self.resolveFocusTimezone(db, timezone)
      let existing = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
      var merged = existing
      var seen = Set(existing)
      for id in taskIDs where seen.insert(id).inserted {
        merged.append(id)
      }
      let header = try Self.currentFocusHeader(db, date: date)
      let plan = try Self.writeCurrentFocus(
        db, hlc: hlc, deviceId: deviceId, service: self, date: date,
        taskIDs: merged, validateTaskIDs: taskIDs, briefing: briefing ?? header?.briefing,
        timezone: resolvedTimezone)
      return try Self.mcpCurrentFocusProjection(db, plan: plan)
    }
  }

  /// Resolve the timezone stamped on a focus plan. A caller-supplied non-empty
  /// IANA name is honoured; an empty/whitespace value resolves to the user's
  /// anchored timezone (DB `timezone` preference, falling back to the system
  /// zone) so an absent client argument never silently stamps a wrong zone.
  private static func resolveFocusTimezone(_ db: Database, _ timezone: String) throws -> String {
    try timezone.trimmedNilIfEmpty ?? WorkflowTimezone.anchoredTimezoneName(db)
  }

  public func removeFromCurrentFocus(date: String, taskID: LorvexTask.ID) async throws
    -> CurrentFocusPlan?
  {
    // A Watch command's no-op decision and terminal receipt must share the same
    // BEGIN IMMEDIATE transaction. Otherwise another writer can add the task
    // after this pre-read but before the receipt, producing an applied ACK for a
    // removal that never happened.
    // A keyed MCP call likewise must reach the write transaction even when the
    // removal is a no-op: the host finalizes every keyed non-error result
    // against the durable claim `withWrite` commits, and the consumed key must
    // conflict on reuse with different arguments. The in-write recheck handles
    // the no-op without emitting a changelog or outbox row.
    if Self.currentWatchCommand != nil || Self.currentMCPIdempotency != nil {
      return try removeFromCurrentFocusInWrite(date: date, taskID: taskID).current.plan
    }

    // Keyless surfaces short-circuit a no-op BEFORE opening a write
    // transaction: removing a task that isn't in the stored plan (or when no
    // plan exists) changes nothing, so it must bump no local_change_seq,
    // broadcast no DB-change, and write no changelog row. `withWrite` commits
    // unconditionally, so the guard has to happen outside it.
    let stored = try read { db -> [String]? in
      guard try Self.currentFocusHeader(db, date: date) != nil else { return nil }
      return try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
    }
    guard let stored else { return nil }
    guard stored.contains(taskID) else { return try await loadCurrentFocus(date: date) }
    return try removeFromCurrentFocusInWrite(date: date, taskID: taskID).current.plan
  }

  public func removeFromCurrentFocusForMcp(
    date: String, taskID: LorvexTask.ID
  ) async throws -> McpCurrentFocusRemovalReceipt {
    try removeFromCurrentFocusInWrite(date: date, taskID: taskID)
  }

  /// Rechecks membership under the write lock. On the Watch path, even a true
  /// no-op commits the local terminal receipt in this transaction; it emits no
  /// domain changelog or outbox row unless the task is actually present.
  private func removeFromCurrentFocusInWrite(
    date: String,
    taskID: LorvexTask.ID
  ) throws -> McpCurrentFocusRemovalReceipt {
    try withWrite { db, hlc, deviceId in
      guard let header = try Self.currentFocusHeader(db, date: date) else {
        return McpCurrentFocusRemovalReceipt(
          current: McpCurrentFocusProjection(plan: nil, tasks: []), removed: false)
      }
      let stored = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
      guard stored.contains(taskID) else {
        let visible = try Self.filterExistingNonArchivedTaskIDs(db, ids: stored)
        let plan = SwiftLorvexFocusDeserializers.currentFocusPlan(
          date: date, taskIDs: visible, briefing: header.briefing,
          timezone: header.timezone,
          localChangeSequence: Int(try LocalChangeSeq.read(db)))
        return McpCurrentFocusRemovalReceipt(
          current: try Self.mcpCurrentFocusProjection(db, plan: plan), removed: false)
      }
      let remaining = stored.filter { $0 != taskID }
      if remaining.isEmpty {
        let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.currentFocus, entityId: date)
        try CurrentFocusItemsRepo.deleteCurrentFocus(db, date: date)
        try self.enqueueDelete(
          db, hlc: hlc, deviceId: deviceId, kind: .currentFocus, entityId: date, payload: payload)
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opDelete, entityType: EntityName.currentFocus,
            entityId: date, summary: "Cleared current focus for \(date)"),
          deviceId: deviceId)
        return McpCurrentFocusRemovalReceipt(
          current: McpCurrentFocusProjection(plan: nil, tasks: []), removed: true)
      }
      let plan = try Self.writeCurrentFocus(
        db, hlc: hlc, deviceId: deviceId, service: self, date: date,
        taskIDs: remaining, validateTaskIDs: [], briefing: header.briefing,
        timezone: header.timezone ?? TimeZone.current.identifier)
      return McpCurrentFocusRemovalReceipt(
        current: try Self.mcpCurrentFocusProjection(db, plan: plan), removed: true)
    }
  }

  public func clearCurrentFocus(date: String) async throws -> CurrentFocusPlan? {
    // Keyless surfaces short-circuit clearing a day that has no plan BEFORE
    // opening a write transaction: there is nothing to delete, so a no-op must
    // bump no local_change_seq, broadcast no DB-change, and write no changelog
    // row. A keyed MCP call skips the short-circuit — the host finalizes every
    // keyed non-error result against the durable claim `withWrite` commits, and
    // the transaction body below already no-ops safely when no plan exists.
    if Self.currentMCPIdempotency == nil {
      let hasPlan = try read { db in try Self.currentFocusHeader(db, date: date) != nil }
      guard hasPlan else { return nil }
    }
    _ = try clearCurrentFocusInWrite(date: date)
    return nil
  }

  public func clearCurrentFocusForMcp(date: String) async throws -> McpCurrentFocusClearReceipt {
    try clearCurrentFocusInWrite(date: date)
  }

  private func clearCurrentFocusInWrite(date: String) throws -> McpCurrentFocusClearReceipt {
    try withWrite { db, hlc, deviceId in
      let previous: McpCurrentFocusProjection
      if let header = try Self.currentFocusHeader(db, date: date) {
        let stored = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
        let visible = try Self.filterExistingNonArchivedTaskIDs(db, ids: stored)
        let plan = SwiftLorvexFocusDeserializers.currentFocusPlan(
          date: date, taskIDs: visible, briefing: header.briefing, timezone: header.timezone,
          localChangeSequence: Int(try LocalChangeSeq.read(db)))
        previous = try Self.mcpCurrentFocusProjection(db, plan: plan)
      } else {
        previous = McpCurrentFocusProjection(plan: nil, tasks: [])
      }
      let priorPayload: JSONValue?
      do {
        priorPayload = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.currentFocus, entityId: date)
      } catch EnqueueError.entityNotFound {
        // clearCurrentFocus legitimately runs when there is no plan for the date;
        // entityNotFound is benign here (nothing to tombstone).
        priorPayload = nil
      }
      // Any other error propagates and rolls back the whole withWrite transaction,
      // so we never permanently delete the row without emitting its sync tombstone.
      let deleted = try CurrentFocusItemsRepo.deleteCurrentFocus(db, date: date)
      if deleted {
        if let priorPayload {
          try self.enqueueDelete(
            db, hlc: hlc, deviceId: deviceId, kind: .currentFocus, entityId: date,
            payload: priorPayload)
        }
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opDelete, entityType: EntityName.currentFocus,
            entityId: date, summary: "Cleared current focus for \(date)"),
          deviceId: deviceId)
      }
      return McpCurrentFocusClearReceipt(
        previous: previous, cleared: deleted && !(previous.plan?.taskIDs.isEmpty ?? true))
    }
  }

  static func mcpCurrentFocusProjection(
    _ db: Database, plan: CurrentFocusPlan?
  ) throws -> McpCurrentFocusProjection {
    guard let plan else { return McpCurrentFocusProjection(plan: nil, tasks: []) }
    return McpCurrentFocusProjection(
      plan: plan, tasks: try plan.taskIDs.map { try loadTaskMapped(db, id: $0) })
  }

  /// Upsert the `current_focus` header and rebuild its child items in one
  /// mutation, stamping both at a single HLC version (header strict `>`, child
  /// rebuild `>=`), then record the changelog row and return the projected plan.
  static func writeCurrentFocus(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    service: SwiftLorvexCoreService,
    date: String,
    taskIDs: [String],
    validateTaskIDs: [String],
    briefing: String?,
    timezone: String
  ) throws -> CurrentFocusPlan {
    try validateCurrentFocusTaskIDs(db, taskIDs: validateTaskIDs)
    let version = hlc.nextVersionString()
    let now = SyncTimestampFormat.syncTimestampNow()
    _ = try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
      db, date: date, briefing: briefing, timezone: timezone, version: version, now: now)
    try CurrentFocusItemsRepo.materializeFocusItemsWithHeaderBump(
      db, date: date, taskIds: taskIDs, version: version, now: now)
    let storedTaskIDs = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
    let header = try currentFocusHeader(db, date: date)
    try service.enqueueUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .currentFocus, entityId: date)
    try service.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert, entityType: EntityName.currentFocus,
        entityId: date, summary: "Set current focus for \(date) (\(storedTaskIDs.count) task(s))"),
      deviceId: deviceId)
    return SwiftLorvexFocusDeserializers.currentFocusPlan(
      date: date, taskIDs: storedTaskIDs, briefing: header?.briefing,
      timezone: header?.timezone ?? timezone, localChangeSequence: Int(try LocalChangeSeq.read(db)))
  }

  static func validateCurrentFocusTaskIDs(_ db: Database, taskIDs: [String]) throws {
    let unique = Array(Set(taskIDs))
    guard !unique.isEmpty else { return }
    let placeholders = unique.map { _ in "?" }.joined(separator: ", ")
    let live = Set(
      try String.fetchAll(
        db,
        sql: """
          SELECT id FROM tasks
          WHERE id IN (\(placeholders))
            AND archived_at IS NULL
            AND status IN (\(StatusName.activeStatusSqlList))
          """,
        arguments: StatementArguments(unique)))
    if let missing = unique.first(where: { !live.contains($0) }) {
      throw LorvexCoreError.unsupportedOperation(
        "Current focus task_id '\(missing)' does not reference an active task.")
    }
  }

  /// Drops focus task ids that no longer exist or are in the Trash, preserving
  /// stored order. `current_focus_items.task_id` is a soft reference (no FK), so
  /// a peer's task delete can leave an orphan row; an archived (trashed) task
  /// must not surface on the focus read. Completed/cancelled tasks are kept — a
  /// finished focus item still belongs to the day's focus. This makes the read
  /// robust regardless of whether the sync-apply delete cleaned the child rows.
  static func filterExistingNonArchivedTaskIDs(_ db: Database, ids: [String]) throws -> [String] {
    guard !ids.isEmpty else { return [] }
    let unique = Array(Set(ids))
    let placeholders = unique.map { _ in "?" }.joined(separator: ", ")
    let live = Set(
      try String.fetchAll(
        db,
        sql: "SELECT id FROM tasks WHERE id IN (\(placeholders)) AND archived_at IS NULL",
        arguments: StatementArguments(unique)))
    return ids.filter { live.contains($0) }
  }

  static func currentFocusHeader(
    _ db: Database, date: String
  ) throws -> (briefing: String?, timezone: String?)? {
    guard
      let row = try Row.fetchOne(
        db, sql: "SELECT briefing, timezone FROM current_focus WHERE date = ?", arguments: [date])
    else { return nil }
    return (row[0], row[1])
  }
}
