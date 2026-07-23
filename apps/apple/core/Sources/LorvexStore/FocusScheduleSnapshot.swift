import Foundation
import GRDB
import LorvexDomain

/// Shared focus-schedule block normalization for sync / export payloads.
///
/// Provenance is carried by each block, so serialization is independent of
/// calendar-row arrival order. Provider titles are device-local calendar data
/// and are replaced with `"Event"` before sync or export; canonical and
/// freeform block titles are preserved.
public enum FocusScheduleSnapshot {
  /// Neutral label substituted for a provider-derived event block's title.
  static let neutralEventTitle = "Event"

  /// Apply the external-transfer privacy rule to a single block. Provider
  /// blocks never carry identity and always use the neutral title.
  public static func normalizeBlockForExternalTransfer(
    eventSource: FocusScheduleEventSource?, calendarEventId: String?, title: String?
  ) -> (calendarEventId: String?, title: String?) {
    guard eventSource == .provider else { return (calendarEventId, title) }
    return (nil, neutralEventTitle)
  }

  /// Serialize the `focus_schedule_blocks` rows for `date` into the
  /// canonical JSON array embedded in a `focus_schedule` sync envelope.
  /// Position-ordered; each block carries `block_type`, `start_minutes`,
  /// `end_minutes` (integer minute offsets), `task_id`, `calendar_event_id`,
  /// `event_source`, `title`, after the provider-block normalization above.
  public static func serializeBlocksForSync(
    _ db: Database, date: String
  ) throws -> [JSONValue] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT block_type, start_minutes, end_minutes, task_id, calendar_event_id, event_source, title \
        FROM focus_schedule_blocks \
        WHERE date = ? ORDER BY position ASC
        """,
      arguments: [date])

    var blocks: [JSONValue] = []
    blocks.reserveCapacity(rows.count)
    for row in rows {
      let blockType: String = row["block_type"]
      let startMinutes: Int64 = row["start_minutes"]
      let endMinutes: Int64 = row["end_minutes"]
      let taskId: String? = row["task_id"]
      let calendarEventId: String? = row["calendar_event_id"]
      let eventSourceRaw: String? = row["event_source"]
      let title: String? = row["title"]
      let eventSource = eventSourceRaw.flatMap(FocusScheduleEventSource.parse)

      let (syncedCalendarEventId, syncedTitle) = normalizeBlockForExternalTransfer(
        eventSource: eventSource, calendarEventId: calendarEventId, title: title)

      blocks.append(
        .object([
          "block_type": .string(blockType),
          "start_minutes": .int(startMinutes),
          "end_minutes": .int(endMinutes),
          "task_id": taskId.map(JSONValue.string) ?? .null,
          "calendar_event_id": syncedCalendarEventId.map(JSONValue.string) ?? .null,
          "event_source": eventSourceRaw.map(JSONValue.string) ?? .null,
          "title": syncedTitle.map(JSONValue.string) ?? .null,
        ]))
    }
    return blocks
  }
}
