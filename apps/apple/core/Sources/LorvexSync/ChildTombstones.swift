import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension OutboxEnqueue {

  /// Pre-delete snapshot of a `task_calendar_event_links` edge row. Carries the
  /// full canonical row so a peer that missed the upsert can reconstruct the
  /// edge for restore-from-trash.
  public struct DeletedTaskCalendarEventLinkSnapshot: Sendable, Equatable {
    public var taskId: String
    public var calendarEventId: String
    public var createdAt: String
    public var updatedAt: String
    public var version: String

    /// Composite-PK `entity_id`: `{task_id}:{calendar_event_id}`.
    public var entityId: String { "\(taskId):\(calendarEventId)" }

    public func payload() -> JSONValue {
      PayloadLoaders.taskCalendarEventLinkPayload(
        taskId: taskId, calendarEventId: calendarEventId, version: version,
        createdAt: createdAt, updatedAt: updatedAt)
    }
  }

  // MARK: - calendar_event link cascade

  /// Enqueue a DELETE envelope (and the matching tombstone via
  /// ``enqueuePayloadDelete(_:entityType:entityId:payload:context:)``) for every
  /// `task_calendar_event_links` edge attached to `eventId`. Returns the
  /// pre-delete snapshots whose rows were enqueued.
  ///
  /// MUST run BEFORE the `DELETE FROM calendar_events` so the cascade has not
  /// yet wiped the link rows. Each edge tombstone gets a freshly-minted HLC
  /// (via `mintVersion`): reusing one `version` across N tombstones would break
  /// the strictly-monotonic-version-per-envelope invariant, so peers would drop
  /// every tombstone after the first.
  @discardableResult
  public static func enqueueEdgeTombstonesForCalendarEventDelete(
    _ db: Database,
    eventId: String,
    deviceId: String,
    mintVersion: () throws -> String
  ) throws -> [DeletedTaskCalendarEventLinkSnapshot] {
    let snapshots = try collectCalendarEventLinkSnapshots(db, eventId: eventId)
    if snapshots.isEmpty {
      return snapshots
    }
    for snapshot in snapshots {
      let version = try mintVersion()
      try enqueuePayloadDelete(
        db, entityType: EdgeName.taskCalendarEventLink, entityId: snapshot.entityId,
        payload: snapshot.payload(),
        context: OutboxWriteContext(
          version: version, deviceId: deviceId))
    }
    return snapshots
  }

  private static func collectCalendarEventLinkSnapshots(
    _ db: Database, eventId: String
  ) throws -> [DeletedTaskCalendarEventLinkSnapshot] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT task_id, calendar_event_id, created_at, updated_at, version
        FROM task_calendar_event_links
        WHERE calendar_event_id = ?
        ORDER BY created_at, task_id
        """,
      arguments: [eventId])
    return rows.map { row in
      DeletedTaskCalendarEventLinkSnapshot(
        taskId: row["task_id"], calendarEventId: row["calendar_event_id"],
        createdAt: row["created_at"], updatedAt: row["updated_at"], version: row["version"])
    }
  }
}
