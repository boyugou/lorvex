import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  func removeTaskFromFocusReferences(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    taskID: String
  ) throws {
    let currentDates = try String.fetchAll(
      db, sql: "SELECT DISTINCT date FROM current_focus_items WHERE task_id = ?", arguments: [taskID])
    for date in currentDates {
      let priorPayload = try priorPayloadForTombstone(
        db, entityType: EntityName.currentFocus, entityId: date)
      try db.execute(
        sql: "DELETE FROM current_focus_items WHERE date = ? AND task_id = ?",
        arguments: [date, taskID])
      let remaining = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE date = ?", arguments: [date]) ?? 0
      if remaining == 0 {
        try CurrentFocusItemsRepo.deleteCurrentFocus(db, date: date)
        if let priorPayload {
          try enqueueDelete(
            db, hlc: hlc, deviceId: deviceId, kind: .currentFocus, entityId: date,
            payload: priorPayload)
        }
      } else {
        try enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .currentFocus, entityId: date)
      }
    }

    let blockDates = try String.fetchAll(
      db,
      sql: "SELECT DISTINCT date FROM focus_schedule_blocks WHERE task_id = ?",
      arguments: [taskID])
    for date in blockDates {
      try removeFocusScheduleBlocks(
        db, hlc: hlc, deviceId: deviceId, date: date,
        whereSQL: "date = ? AND task_id = ?",
        arguments: [date, taskID])
    }
  }

  func removeCalendarEventFromFocusSchedules(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    calendarEventID: String
  ) throws {
    let dates = try String.fetchAll(
      db,
      sql: "SELECT DISTINCT date FROM focus_schedule_blocks WHERE calendar_event_id = ?",
      arguments: [calendarEventID])
    for date in dates {
      try removeFocusScheduleBlocks(
        db, hlc: hlc, deviceId: deviceId, date: date,
        whereSQL: "date = ? AND calendar_event_id = ?",
        arguments: [date, calendarEventID])
    }
  }

  private func removeFocusScheduleBlocks(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    date: String,
    whereSQL: String,
    arguments: StatementArguments
  ) throws {
    let priorPayload = try priorPayloadForTombstone(
      db, entityType: EntityName.focusSchedule, entityId: date)
    try db.execute(sql: "DELETE FROM focus_schedule_blocks WHERE \(whereSQL)", arguments: arguments)
    let remaining = try Int.fetchOne(
      db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
      arguments: [date]) ?? 0
    if remaining == 0 {
      try db.execute(sql: "DELETE FROM focus_schedule WHERE date = ?", arguments: [date])
      if let priorPayload {
        try enqueueDelete(
          db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule, entityId: date,
          payload: priorPayload)
      }
    } else {
      try enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule, entityId: date)
    }
  }

  /// Reads the prior payload snapshot for a delete tombstone. A genuinely-absent
  /// entity is "nothing to tombstone" (returns nil); real store / serialization
  /// errors propagate so the surrounding write rolls back rather than silently
  /// dropping the delete from the sync outbox (which would leave peers diverged).
  private func priorPayloadForTombstone(
    _ db: Database, entityType: String, entityId: String
  ) throws -> JSONValue? {
    do {
      return try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: entityType, entityId: entityId)
    } catch EnqueueError.entityNotFound {
      return nil
    }
  }
}
