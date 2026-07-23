import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  // MARK: - Recurrence

  public func setTaskRecurrence(taskID: LorvexTask.ID, rule: TaskRecurrenceRule) async throws
    -> LorvexTask
  {
    try withWrite { db, hlc, deviceId in
      let ruleInput = TaskRecurrence.RuleInput(
        freq: rule.freq.rawValue,
        interval: rule.interval.map { UInt32(clamping: max(0, $0)) },
        byday: rule.byDay,
        bymonth: rule.byMonth?.map { Int64($0) },
        bymonthday: rule.byMonthDay?.map { Int64($0) } ?? [],
        bysetpos: rule.bySetPos?.map { Int64($0) },
        wkst: rule.wkst,
        until: rule.until,
        count: rule.count.map { UInt32(clamping: max(0, $0)) },
        anchor: rule.anchor == .completion ? rule.anchor.rawValue : nil)
      let result = try TaskRecurrence.setTaskRecurrence(
        db, hlc: hlc,
        input: TaskRecurrence.SetTaskRecurrenceInput(
          taskId: TaskId(trusted: taskID), rule: ruleInput))
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: result.taskId)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "set_recurrence", entityId: result.taskId, summary: result.summary,
          before: result.beforeTask, after: result.afterTask),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(result.afterTask)
    }
  }

  public func removeTaskRecurrence(taskID: LorvexTask.ID) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      let beforeSync = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: taskID)
      let now = SyncTimestampFormat.syncTimestampNow()
      let today = try WorkflowTimezone.todayYmdForConn(db)
      let version = hlc.nextVersionString()
      let result = try RecurrenceConfig.applyRecurrenceChangeWithEffectsInTx(
        db, taskId: TaskId(trusted: taskID), recurrencePatch: .clear,
        dueDatePatch: .unset, today: today,
        version: version, now: now)
      let afterSync = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: taskID)
      let primaryIntent = try TaskRegisterIntent.authoredRegisters(
        between: beforeSync, and: afterSync)
      try self.enqueueUpsert(
        db, deviceId: deviceId, kind: .task, entityId: taskID, version: version,
        registerIntent: .task(primaryIntent))
      try self.flushRecurrenceDisableEffects(
        db, hlc: hlc, deviceId: deviceId, effects: result.disableEffects)
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "remove_recurrence", entityId: taskID,
          summary: "Removed recurrence from '\(TaskResponse.taskTitle(after))'",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  public func addTaskRecurrenceException(taskID: LorvexTask.ID, exceptionDate: String) async throws
    -> LorvexTask
  {
    // Reject a non-canonical date before it lands as an EXDATE: a key like
    // "2026-6-9" would never match an occurrence and would ship as a bad edge id.
    if case .failure(let error) = IsoDate.parseIsoDate(exceptionDate) {
      throw LorvexCoreError.validation(field: "exception_date", message: error.description)
    }
    return try mutateRecurrenceExceptions(
      taskID: taskID, operation: "add_recurrence_exception",
      summaryVerb: "Added recurrence exception to", requireRecurring: true
    ) { current in
      var set = Set(current)
      set.insert(exceptionDate)
      return set.sorted()
    }
  }

  public func removeTaskRecurrenceException(taskID: LorvexTask.ID, exceptionDate: String)
    async throws -> LorvexTask
  {
    try mutateRecurrenceExceptions(
      taskID: taskID, operation: "remove_recurrence_exception",
      summaryVerb: "Removed recurrence exception from"
    ) { current in
      current.filter { $0 != exceptionDate }.sorted()
    }
  }

  private func mutateRecurrenceExceptions(
    taskID: LorvexTask.ID,
    operation: String,
    summaryVerb: String,
    requireRecurring: Bool = false,
    _ transform: ([String]) -> [String]
  ) throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      guard try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: taskID)) != nil else {
        throw LorvexCoreError.taskNotFound
      }
      // An EXDATE is only meaningful on a recurring task; reject adding one to a
      // non-recurring task (matches the in-memory backend).
      if requireRecurring,
        try String.fetchOne(
          db, sql: "SELECT recurrence FROM tasks WHERE id = ?", arguments: [taskID]) == nil
      {
        throw LorvexCoreError.unsupportedOperation(
          "Task '\(taskID)' has no recurrence rule; set one before adding exceptions.")
      }
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      let now = SyncTimestampFormat.syncTimestampNow()
      let current = try RecurrenceExceptionsRepo.loadTaskExceptionDates(db, taskId: taskID)
      let updated = transform(current)
      // No change to the EXDATE set (a duplicate-add of an already-present date, or
      // a remove of an absent one) is a true no-op: skip the parent-task version
      // bump, the sync enqueue, AND the changelog row. Bumping the version for an
      // unchanged set could LWW-win over a concurrent legitimate remote edit.
      // Both `current` and `updated` are ascending-sorted, so equality is exact.
      guard updated != current else {
        return try SwiftLorvexTaskDeserializers.task(before)
      }
      let version = hlc.nextVersionString()
      try TaskRepo.Recurrence.replaceTaskRecurrenceExceptionsInTx(
        db, taskId: TaskId(trusted: taskID), dates: updated,
        version: version, now: now)
      try self.enqueueUpsert(
        db, deviceId: deviceId, kind: .task, entityId: taskID, version: version,
        registerIntent: .task(.schedule))
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: operation, entityId: taskID,
          summary: "\(summaryVerb) '\(TaskResponse.taskTitle(after))'",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }
}
