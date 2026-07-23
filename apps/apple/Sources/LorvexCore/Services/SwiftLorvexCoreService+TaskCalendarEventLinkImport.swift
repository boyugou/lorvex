import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  /// Create the canonical (synced) task↔calendar-event link, id-preserving.
  ///
  /// The link is a pure existence edge keyed by `(task_id, calendar_event_id)`
  /// with no mutable state, so re-linking an already-linked pair is a true
  /// no-op: it mints no version, writes no `ai_changelog` row, and enqueues no
  /// sync envelope — the only-changed-rows discipline the reorder op uses. Only
  /// a genuine first link version-stamps the edge, records the changelog, and
  /// enqueues the upsert envelope.
  ///
  /// The changelog row carries no explicit initiator, so it inherits the ambient
  /// ``currentInitiator`` — `assistant` under the MCP host's `link_task_to_event`
  /// and `import` under ``LorvexDataImporter`` — instead of always attributing a
  /// live assistant link to a restore.
  ///
  /// Returns `true` when a link exists after the call (a fresh link was created,
  /// or the pair was already linked). Returns `false` only under an import-context
  /// restore (`import` initiator) that refuses to resurrect a link the user
  /// deleted after the backup: a fresh dominating import HLC would otherwise beat
  /// the unlink tombstone and re-propagate the edge fleet-wide. An explicit
  /// assistant relink (`assistant` initiator) falls through the tombstone and
  /// re-creates the edge — resurrection there is the intended action.
  @discardableResult
  public func importTaskCalendarEventLink(_ link: ExportTaskCalendarEventLink) async throws -> Bool {
    let taskID = try Self.requiredTaskCalendarEventLinkText(link.taskID, field: "task id")
    let requestedEventID = try Self.requiredTaskCalendarEventLinkText(
      link.calendarEventID, field: "calendar event id")
    return try linkTaskCalendarEventInWrite(
      taskID: taskID, requestedEventID: requestedEventID,
      createdAt: link.createdAt, updatedAt: link.updatedAt).existsAfter
  }

  public func linkTaskToCalendarEventForMcp(
    taskID: LorvexTask.ID, calendarEventID: CalendarTimelineEvent.ID
  ) async throws -> McpTaskCalendarEventLinkReceipt {
    let taskID = try Self.requiredTaskCalendarEventLinkText(taskID, field: "task id")
    let requestedEventID = try Self.requiredTaskCalendarEventLinkText(
      calendarEventID, field: "calendar event id")
    return try linkTaskCalendarEventInWrite(
      taskID: taskID, requestedEventID: requestedEventID,
      createdAt: nil, updatedAt: nil).receipt
  }

  private func linkTaskCalendarEventInWrite(
    taskID: String, requestedEventID: String, createdAt: String?, updatedAt: String?
  ) throws -> (receipt: McpTaskCalendarEventLinkReceipt, existsAfter: Bool) {
    let now = SyncTimestampFormat.syncTimestampNow()
    return try withWrite { db, hlc, deviceId in
      guard try Self.taskExists(db, taskID: taskID) else {
        throw LorvexCoreError.taskNotFound
      }
      let eventID = try Self.canonicalCalendarLinkTargetID(db, eventID: requestedEventID)
      let alreadyLinked =
        try Int.fetchOne(
          db,
          sql: """
            SELECT 1 FROM task_calendar_event_links
            WHERE task_id = ? AND calendar_event_id = ?
            """,
          arguments: [taskID, eventID]) != nil
      guard !alreadyLinked else {
        return (
          McpTaskCalendarEventLinkReceipt(calendarEventID: eventID, changed: false), true)
      }
      // Under an import-context restore, refuse to resurrect a link the user
      // unlinked after the backup (its `{taskID}:{eventID}` edge is tombstoned).
      // An explicit assistant relink is not import-context and falls through.
      if Self.currentInitiator == ChangelogInitiator.importAttribution,
        try Tombstone.isTombstoned(
          db, entityType: EdgeName.taskCalendarEventLink, entityId: "\(taskID):\(eventID)")
      {
        return (
          McpTaskCalendarEventLinkReceipt(calendarEventID: eventID, changed: false), false)
      }
      try db.execute(
        sql: """
          INSERT INTO task_calendar_event_links (
            task_id, calendar_event_id, version, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          taskID, eventID, hlc.nextVersionString(),
          try Self.canonicalImportTimestamp(
            createdAt, field: "task-calendar link createdAt", fallback: now),
          try Self.canonicalImportTimestamp(
            updatedAt, field: "task-calendar link updatedAt", fallback: now),
        ])
      try self.enqueueTaskCalendarEventLinkUpsert(
        db, hlc: hlc, deviceId: deviceId, taskId: taskID, calendarEventId: eventID)
      // Every synced mutation records an `ai_changelog` row (Core Design Rule 2),
      // matching the id-preserving importers for tasks, lists, habits, and events.
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opUpsert, entityType: EntityName.task, entityId: taskID,
          summary: "Linked task \(taskID) to calendar event \(eventID)."),
        deviceId: deviceId)
      return (McpTaskCalendarEventLinkReceipt(calendarEventID: eventID, changed: true), true)
    }
  }

  /// Remove the canonical (synced) task↔calendar-event link, the symmetric
  /// counterpart to ``importTaskCalendarEventLink(_:)``.
  ///
  /// Returns whether a link row was actually removed. An absent link is a
  /// truthful no-op (`false`) that writes no `ai_changelog` row and enqueues no
  /// tombstone — mirroring ``unlinkTaskFromProviderEvent(taskID:providerEventID:)``.
  /// When a link is removed the deletion propagates as a SYNCED delete rather
  /// than a bare local delete a peer would re-hydrate: the row is snapshotted
  /// BEFORE the DELETE and enqueued as a Delete envelope (so a peer that missed
  /// the upsert drops the edge and can reconstruct it for restore-from-trash),
  /// and a delete `ai_changelog` row is recorded. The changelog row inherits the
  /// ambient ``currentInitiator`` (`assistant` under the MCP host's
  /// `unlink_task_from_event`).
  @discardableResult
  public func unlinkTaskCalendarEventLink(taskID: String, calendarEventID: String) async throws
    -> Bool
  {
    let taskID = try Self.requiredTaskCalendarEventLinkText(taskID, field: "task id")
    let requestedEventID = try Self.requiredTaskCalendarEventLinkText(
      calendarEventID, field: "calendar event id")
    return try unlinkTaskCalendarEventInWrite(
      taskID: taskID, requestedEventID: requestedEventID).changed
  }

  public func unlinkTaskFromCalendarEventForMcp(
    taskID: LorvexTask.ID, calendarEventID: CalendarTimelineEvent.ID
  ) async throws -> McpTaskCalendarEventLinkReceipt {
    let taskID = try Self.requiredTaskCalendarEventLinkText(taskID, field: "task id")
    let requestedEventID = try Self.requiredTaskCalendarEventLinkText(
      calendarEventID, field: "calendar event id")
    return try unlinkTaskCalendarEventInWrite(
      taskID: taskID, requestedEventID: requestedEventID)
  }

  private func unlinkTaskCalendarEventInWrite(
    taskID: String, requestedEventID: String
  ) throws -> McpTaskCalendarEventLinkReceipt {
    return try withWrite { db, hlc, deviceId in
      let eventID = try Self.canonicalCalendarLinkTargetID(db, eventID: requestedEventID)
      // Snapshot the row BEFORE the DELETE so the tombstone envelope carries the
      // full pre-delete payload; a missing row is an honest no-op the caller
      // reports as `deleted:false`, writing no changelog and no envelope.
      guard
        let payload = try PayloadLoaders.loadTaskCalendarEventLinkSyncPayload(
          db, taskId: taskID, calendarEventId: eventID)
      else {
        return McpTaskCalendarEventLinkReceipt(calendarEventID: eventID, changed: false)
      }
      try db.execute(
        sql: """
          DELETE FROM task_calendar_event_links
          WHERE task_id = ? AND calendar_event_id = ?
          """,
        arguments: [taskID, eventID])
      try self.enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskCalendarEventLink,
        entityId: "\(taskID):\(eventID)", payload: payload)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opDelete, entityType: EntityName.task, entityId: taskID,
          summary: "Unlinked task \(taskID) from calendar event \(eventID)."),
        deviceId: deviceId)
      return McpTaskCalendarEventLinkReceipt(calendarEventID: eventID, changed: true)
    }
  }

  /// Resolve the canonical edge endpoint for a user-facing link operation.
  /// Exposed through the native-import seam so the MCP adapter can return the
  /// same normalized id the database stores.
  public func resolveTaskCalendarEventLinkTarget(calendarEventID: String) async throws -> String {
    let eventID = try Self.requiredTaskCalendarEventLinkText(
      calendarEventID, field: "calendar event id")
    return try read { db in
      try Self.canonicalCalendarLinkTargetID(db, eventID: eventID)
    }
  }

  private static func requiredTaskCalendarEventLinkText(_ raw: String, field: String) throws
    -> String
  {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A \(field) is required.")
    }
    return trimmed
  }
}
