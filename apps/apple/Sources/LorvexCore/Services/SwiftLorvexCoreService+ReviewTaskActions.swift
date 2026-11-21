import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

public enum ReviewTaskDestination: Sendable {
  case day(String)
  case someday
}

/// An in-memory undo record. Only the fields touched by the review action
/// participate, so an unrelated edit to a title or a note survives undo.
public struct ReviewTaskChange: Sendable {
  public let id: String
  fileprivate struct State: Equatable, Sendable {
    let status: TaskStatus
    let plan: TaskDeferral.DeferralSnapshot

    init(_ row: TaskRow) throws {
      status = try LifecycleStatus.parsePersistedTaskStatus(taskId: TaskId(trusted: row.core.id), raw: row.core.status)
      let s = row.scheduling
      plan = .init(plannedDate: s.plannedDate?.asString, plannedTime: s.plannedTime,
        deferCount: s.deferCount, lastDeferredAt: s.lastDeferredAt, lastDeferReason: s.lastDeferReason)
    }
  }
  fileprivate let before: State
  fileprivate let after: State
  fileprivate struct Reminder: Sendable {
    let id: String
    let before: String
    let after: String
  }
  fileprivate let reminders: [Reminder]
}

extension SwiftLorvexCoreService {
  public func planUnscheduledTask(id: String, on day: String) async throws -> ReviewTaskChange? {
    _ = try LorvexDate.parse(day).get()
    return try withWrite { db, hlc, deviceId -> ReviewTaskChange? in
      let taskID = TaskId(trusted: id)
      guard let row = try TaskRepo.Read.getTask(db, taskId: taskID),
        row.lifecycle.archivedAt == nil, row.scheduling.plannedDate == nil else { return nil }
      let before = try ReviewTaskChange.State(row)
      guard before.status.isActionable else { return nil }
      let visible = TaskReadBuckets.availableVisibilityPredicate(taskAlias: "tasks", datePlaceholder: "?")
      guard try Bool.fetchOne(db, sql: "SELECT \(visible) FROM tasks WHERE id = ?", arguments: [day, day, id]) == true
      else { return nil }

      _ = try self.performTaskUpdate(db, hlc: hlc, deviceId: deviceId,
        input: TaskUpdateInput(id: id, plannedDate: .set(day)))
      guard let updated = try TaskRepo.Read.getTask(db, taskId: taskID) else {
        throw StoreError.notFound(entity: EntityName.task, id: id)
      }
      return ReviewTaskChange(id: id, before: before, after: try .init(updated), reminders: [])
    }
  }

  public func arrangeReviewTasks(_ tasks: [ReviewTaskSummary], reviewedOn day: String,
    destination: ReviewTaskDestination) async throws -> [ReviewTaskChange] {
    let source = try LorvexDate.parse(day).get()
    if case .day(let key) = destination { _ = try LorvexDate.parse(key).get() }
    return try withWrite { db, hlc, deviceId in
      var seen = Set<String>()
      var changes: [ReviewTaskChange] = []
      for task in tasks where seen.insert(task.id).inserted {
        let id = TaskId(trusted: task.id)
        guard let row = try TaskRepo.Read.getTask(db, taskId: id), row.lifecycle.archivedAt == nil,
          row.scheduling.plannedDate == source || row.scheduling.dueDate == source,
          row.scheduling.plannedDate?.asString == task.plannedDate
        else { continue }
        let before = try ReviewTaskChange.State(row)
        guard before.status.isActionable else { continue }
        var reminders: [ReviewTaskChange.Reminder] = []
        switch destination {
        case .day(let key):
          guard before.plan.plannedDate != key else { continue }
          let original = try Self.pendingReviewReminders(db, id: task.id)
          _ = try self.applyLifecycleTransition(db, hlc: hlc, deviceId: deviceId, id: task.id,
            operation: "defer") { db, hlc, deviceId in
            let result = try self.deferTaskInTransaction(db, hlc: hlc, deviceId: deviceId, id: task.id,
              plannedDay: key, reason: nil)
            guard result.updated else { return false }
            if !result.shiftedReminderIds.isEmpty {
              let shifted = try Self.pendingReviewReminders(db, id: task.id)
              for rid in result.shiftedReminderIds {
                if let old = original[rid], let new = shifted[rid] {
                  reminders.append(.init(id: rid, before: old, after: new))
                }
              }
            }
            return true
          }
        case .someday:
          _ = try self.markTaskSomedayInTx(db, hlc: hlc, deviceId: deviceId, id: task.id)
        }
        guard let updated = try TaskRepo.Read.getTask(db, taskId: id) else { continue }
        let after = try ReviewTaskChange.State(updated)
        if before != after {
          changes.append(.init(id: task.id, before: before, after: after, reminders: reminders))
        }
      }
      return changes
    }
  }

  public func restoreReviewTasks(_ changes: [ReviewTaskChange], undo: Bool) async throws {
    try withWrite { db, hlc, deviceId in
      for change in changes {
        let id = TaskId(trusted: change.id)
        let expected = undo ? change.after : change.before
        let target = undo ? change.before : change.after
        guard let row = try TaskRepo.Read.getTask(db, taskId: id), row.lifecycle.archivedAt == nil,
          try ReviewTaskChange.State(row) == expected else { continue }
        _ = try self.applyLifecycleTransition(db, hlc: hlc, deviceId: deviceId, id: change.id,
          operation: undo ? "undo_review_plan" : "redo_review_plan") { db, hlc, deviceId in
          let now = SyncTimestampFormat.syncTimestampNow()
          if target.status != expected.status {
            let result = try LifecycleTransitions.applyLifecycleTransition(db, taskId: id,
              oldStatus: expected.status, newStatus: target.status, now: now,
              reminderVersion: hlc.nextVersionString())
            try self.flushLifecyclePlan(db, hlc: hlc, deviceId: deviceId,
              plan: LifecycleSyncPlan.from(transition: result))
          }
          // Returning from Someday to Open resets the plan in the normal lifecycle.
          // Undo restores the original day, time and deferral history in this same transaction.
          _ = try TaskDeferral.restoreTaskDeferral(db, taskId: id, snapshot: target.plan,
            version: hlc.nextVersionString(), now: now)
          try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: change.id)
          for reminder in change.reminders {
            let version = hlc.nextVersionString()
            try db.execute(sql: """
              UPDATE task_reminders SET reminder_at = ?, version = ?
              WHERE id = ? AND task_id = ? AND reminder_at = ? AND dismissed_at IS NULL
                AND cancelled_at IS NULL AND version < ?
              """, arguments: [undo ? reminder.before : reminder.after, version, reminder.id,
                change.id, undo ? reminder.after : reminder.before, version])
            if db.changesCount > 0 {
              try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityId: reminder.id)
            }
          }
          return true
        }
      }
    }
  }

  private static func pendingReviewReminders(_ db: Database, id: String) throws -> [String: String] {
    let rows = try Row.fetchAll(db, sql: """
      SELECT id, reminder_at FROM task_reminders
      WHERE task_id = ? AND dismissed_at IS NULL AND cancelled_at IS NULL
      """, arguments: [id])
    return Dictionary(uniqueKeysWithValues: rows.map { ($0[0] as String, $0[1] as String) })
  }
}
