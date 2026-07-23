import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Transactional native-import of the two multi-part record kinds — tasks and
/// habits — so a failure part-way through a record rolls the whole record, and
/// every sync-outbox envelope it enqueued, back cleanly. Each record runs in one
/// `withWrite` (`BEGIN IMMEDIATE`) transaction: on any throw the transaction
/// rolls back, so no partially-applied row and no orphaned outbox envelope
/// survive. All other export categories write a single row per record and are
/// already atomic through their own `withWrite`.
extension SwiftLorvexCoreService {
  public func importTaskRecordTransactionally(
    _ task: ExportTask, priority: LorvexTask.Priority, dueDate: Date?, plannedDate: Date?,
    availableFrom: Date?, dependenciesToApply: [LorvexTask.ID]
  ) async throws -> ImportedTaskRecordCreationWitness? {
    try withWrite { db, hlc, deviceId in
      let imported = try self.importTaskRecordInTx(
        db, hlc: hlc, deviceId: deviceId, task: task, priority: priority, dueDate: dueDate,
        plannedDate: plannedDate, availableFrom: availableFrom,
        dependenciesToApply: dependenciesToApply)
      guard imported,
        let version = try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id])
      else { return nil }
      return ImportedTaskRecordCreationWitness(taskID: task.id, rowVersion: version)
    }
  }

  public func finalizeImportedTaskRecordTransactionally(
    _ task: ExportTask,
    creationWitness: ImportedTaskRecordCreationWitness
  ) async throws -> ImportedTaskRecordFinalizeResult {
    guard creationWitness.taskID == task.id else {
      throw LorvexCoreError.validation(
        field: "task ID", message: "The deferred restore witness belongs to another task.")
    }
    guard let status = LorvexTask.Status(rawValue: task.status) else {
      throw LorvexCoreError.unsupportedOperation("Unknown status \"\(task.status)\".")
    }
    return try withWrite { db, hlc, deviceId in
      let currentVersion = try String.fetchOne(
        db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id])
      guard currentVersion == creationWitness.rowVersion else {
        return ImportedTaskRecordFinalizeResult(matchedCreationWitness: false)
      }

      var failures: [ImportedTaskRecordFinalizeFailure] = []
      func applyStep(
        _ step: ImportedTaskRecordFinalizeStep,
        _ body: (Database) throws -> Void
      ) throws {
        do {
          try StoreTransactions.withSavepoint(db, "import_task_\(step.rawValue)", body)
        } catch let error where Self.isImportWriteFunnelControlFlow(error) {
          throw error
        } catch {
          failures.append(
            ImportedTaskRecordFinalizeFailure(
              step: step, message: error.localizedDescription))
        }
      }

      if let dependencies = task.dependsOn, !dependencies.isEmpty {
        try applyStep(.dependencies) { db in
          _ = try self.performTaskUpdate(
            db, hlc: hlc, deviceId: deviceId,
            input: TaskUpdateInput(id: task.id, dependsOn: dependencies))
        }
      }
      if status == .cancelled {
        try applyStep(.lifecycle) { db in
          _ = try self.applyLifecycleTransition(
            db, hlc: hlc, deviceId: deviceId, id: task.id, operation: "cancel"
          ) { db, hlc, deviceId in
            try self.applyCancelMutation(
              db, hlc: hlc, deviceId: deviceId, id: task.id)
          }
        }
      }
      try applyStep(.metadata) { db in
        try self.restoreImportedTaskMetadataInTx(
          db, hlc: hlc, deviceId: deviceId, id: task.id,
          archivedAt: task.archivedAt, deferCount: task.deferCount,
          lastDeferReason: task.lastDeferReason, lastDeferredAt: task.lastDeferredAt,
          completedAt: task.completedAt, createdAt: task.createdAt,
          updatedAt: task.updatedAt)
      }
      if status == .inProgress {
        try applyStep(.lifecycle) { db in
          try self.restoreImportedTaskLifecycleStateInTx(
            db, hlc: hlc, deviceId: deviceId, id: task.id, status: .inProgress)
        }
      }
      return ImportedTaskRecordFinalizeResult(
        matchedCreationWitness: true, failures: failures)
    }
  }

  private static func isImportWriteFunnelControlFlow(_ error: any Error) -> Bool {
    switch error {
    case is StorageCutoverDuringWrite: return true
    case StoreError.staleVersion, StoreError.versionSuperseded: return true
    case EnqueueError.versionSuperseded: return true
    default: return false
    }
  }

  /// The complete task-record import inside an open write transaction, shared by
  /// the single-record public entry and the single-transaction batch record
  /// create. Same contract as ``importTaskRecordTransactionally``.
  func importTaskRecordInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, task: ExportTask,
    priority: LorvexTask.Priority, dueDate: Date?, plannedDate: Date?,
    availableFrom: Date?, dependenciesToApply: [LorvexTask.ID]
  ) throws -> Bool {
    try Self.requireCanonicalImportedUUID(task.id, field: "task ID")
    guard let status = LorvexTask.Status(rawValue: task.status) else {
      throw LorvexCoreError.unsupportedOperation("Unknown status \"\(task.status)\".")
    }
    let tags = task.tags ?? []
    // A non-destructive restore never overwrites a task a concurrent create
    // landed in the gap, and never resurrects one the user deleted after the
    // backup. A fresh import HLC would otherwise dominate the death version
    // and re-publish the row fleet-wide. Both checks share this write lock with
    // the insert, so the decision cannot race the write.
    if try Int.fetchOne(db, sql: "SELECT 1 FROM tasks WHERE id = ?", arguments: [task.id]) != nil {
      return false
    }
    if try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: task.id) {
      return false
    }
    try Self.preflightImportedTaskChildren(db, task: task)
    // Attach list membership only when the list row exists; a partial file may
    // omit its lists, and importing the task without a list is preferable to
    // failing the whole record on a foreign-key violation.
    let listId: LorvexList.ID? = try {
      guard let candidate = task.listID else { return nil }
      let exists =
        try Int.fetchOne(db, sql: "SELECT 1 FROM lists WHERE id = ?", arguments: [candidate])
        != nil
      return exists ? candidate : nil
    }()
    // A `.cancelled` or `.inProgress` export creates as `.open` (a plain create
    // expresses neither); the importer transitions it in a later pass.
    let createStatus: LorvexTask.Status =
      (status == .cancelled || status == .inProgress) ? .open : status
    _ = try self.createImportedTaskInTx(
      db, hlc: hlc, deviceId: deviceId, id: task.id, title: task.title, notes: task.notes ?? "",
      aiNotes: task.aiNotes, rawInput: task.rawInput, priority: priority, status: createStatus,
      estimatedMinutes: task.estimatedMinutes, dueDate: dueDate, plannedDate: plannedDate,
      availableFrom: availableFrom, tags: tags, dependsOn: dependenciesToApply, listId: listId)

    let now = SyncTimestampFormat.syncTimestampNow()
    try self.restoreImportedChecklistInTx(db, hlc: hlc, deviceId: deviceId, task: task, now: now)
    try self.restoreImportedRemindersInTx(db, hlc: hlc, deviceId: deviceId, task: task, now: now)
    try self.restoreImportedRecurrenceInTx(db, hlc: hlc, deviceId: deviceId, task: task)
    return true
  }

  public func importHabitRecordTransactionally(_ habit: ExportHabit) async throws -> Bool {
    try Self.requireCanonicalImportedUUID(habit.id, field: "habit ID")
    let milestone = try Self.normalizedMilestoneTarget(habit.milestoneTarget)
    return try withWrite { db, hlc, deviceId in
      // A non-destructive restore never overwrites a habit a concurrent create
      // landed in the gap, and never resurrects one the user deleted after the
      // backup — a fresh dominating import HLC would beat the death version and
      // re-propagate the habit fleet-wide. Both checks share this write lock, so
      // the decision cannot race the write. `importHabit` stays overwrite-on-
      // reimport (pinned by idempotency tests); the guard lives only here.
      if try Int.fetchOne(db, sql: "SELECT 1 FROM habits WHERE id = ?", arguments: [habit.id])
        != nil
      {
        return false
      }
      if try Tombstone.isTombstoned(db, entityType: EntityName.habit, entityId: habit.id) {
        return false
      }
      try Self.preflightImportedHabitChildren(db, habit: habit)
      _ = try self.upsertImportedHabitInTx(
        db, hlc: hlc, deviceId: deviceId, id: habit.id, name: habit.name, icon: habit.icon,
        color: habit.color, cue: habit.cue.isEmpty ? nil : habit.cue,
        frequencyType: habit.frequencyType, weekdays: habit.weekdays,
        perPeriodTarget: habit.perPeriodTarget, dayOfMonth: habit.dayOfMonth,
        targetCount: habit.targetCount, milestone: milestone, archived: habit.archived,
        position: habit.position)
      for completion in habit.completions {
        try Self.validateImportedHabitCompletion(habitID: habit.id, completion: completion)
        try self.upsertImportedHabitCompletionInTx(
          db, hlc: hlc, deviceId: deviceId, habitID: habit.id, completion: completion)
      }
      for policy in habit.reminderPolicies {
        try Self.validateImportedHabitReminderPolicy(habitID: habit.id, policy: policy)
        try self.upsertImportedHabitReminderPolicyInTx(
          db, hlc: hlc, deviceId: deviceId, habitID: habit.id, policy: policy)
      }
      return true
    }
  }

  private static func preflightImportedTaskChildren(
    _ db: Database, task: ExportTask
  ) throws {
    let checklist = task.checklist ?? []
    let providedChecklistIDs = checklist.compactMap(\.id)
    guard providedChecklistIDs.isEmpty || providedChecklistIDs.count == checklist.count else {
      throw LorvexCoreError.validation(
        field: "checklist ID",
        message: "The backup mixes identified and unidentified checklist items.")
    }
    try requireUniqueImportedValues(providedChecklistIDs, field: "checklist ID")
    for itemID in providedChecklistIDs {
      try requireCanonicalImportedUUID(itemID, field: "checklist ID")
      try assertImportedChildIdentityCanWrite(
        db, table: "task_checklist_items", ownerColumn: "task_id",
        expectedOwnerID: task.id, entityType: EntityName.taskChecklistItem,
        entityID: itemID, field: "checklist ID")
    }

    let reminderIDs = (task.reminders ?? []).map(\.id)
    try requireUniqueImportedValues(reminderIDs, field: "reminder ID")
    for reminderID in reminderIDs {
      try requireCanonicalImportedUUID(reminderID, field: "reminder ID")
      try assertImportedChildIdentityCanWrite(
        db, table: "task_reminders", ownerColumn: "task_id",
        expectedOwnerID: task.id, entityType: EntityName.taskReminder,
        entityID: reminderID, field: "reminder ID")
    }
  }

  private static func preflightImportedHabitChildren(
    _ db: Database, habit: ExportHabit
  ) throws {
    let completionDates = habit.completions.map(\.completedDate)
    try requireUniqueImportedValues(completionDates, field: "habit completion date")

    let policyIDs = habit.reminderPolicies.map(\.id)
    try requireUniqueImportedValues(policyIDs, field: "habit reminder policy ID")
    for policyID in policyIDs {
      try requireCanonicalImportedUUID(policyID, field: "habit reminder policy ID")
      try assertImportedChildIdentityCanWrite(
        db, table: "habit_reminder_policies", ownerColumn: "habit_id",
        expectedOwnerID: habit.id, entityType: EntityName.habitReminderPolicy,
        entityID: policyID, field: "habit reminder policy ID")
    }
  }

  /// Re-create the exported checklist rows inside the record transaction. When
  /// every item carries an id the export values (id, position, completed_at,
  /// timestamps) are preserved verbatim; otherwise fresh canonical ids are minted
  /// and a completed item is stamped `now`, matching the non-transactional
  /// add-then-toggle restore.
  private func restoreImportedChecklistInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, task: ExportTask, now: String
  ) throws {
    guard let checklist = task.checklist, !checklist.isEmpty else { return }
    let allHaveIds = checklist.allSatisfy { $0.id != nil }
    for (index, item) in checklist.enumerated() {
      let text = try Self.requiredTrimmed(item.text, field: "checklist text")
      let itemID: String
      let completedAt: String?
      if allHaveIds {
        itemID = try Self.requiredTrimmed(item.id, field: "checklist id")
        completedAt = item.completedAt
      } else {
        itemID = EntityID.newEntityIDString()
        completedAt = item.completed ? now : nil
      }
      try self.upsertImportedChecklistItemRow(
        db, hlc: hlc, deviceId: deviceId, taskID: task.id, itemID: itemID,
        position: max(0, item.position ?? index), text: text, completedAt: completedAt,
        createdAt: item.createdAt ?? now, updatedAt: item.updatedAt ?? now)
    }
  }

  /// Re-create the exported reminders inside the record transaction from the
  /// exact reminder rows. A task with no reminder rows restores no reminders.
  private func restoreImportedRemindersInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, task: ExportTask, now: String
  ) throws {
    if let reminders = task.reminders, !reminders.isEmpty {
      for reminder in reminders {
        let reminderID = try Self.requiredTrimmed(reminder.id, field: "reminder id")
        let reminderAt = try Self.requiredTrimmed(reminder.reminderAt, field: "reminderAt")
        try self.upsertImportedReminderRow(
          db, hlc: hlc, deviceId: deviceId, taskID: task.id, reminderID: reminderID,
          reminderAt: reminderAt, dismissedAt: reminder.dismissedAt,
          cancelledAt: reminder.cancelledAt, createdAt: reminder.createdAt ?? now,
          originalLocalTime: reminder.originalLocalTime, originalTz: reminder.originalTz)
      }
    }
  }

  /// Re-apply the exported recurrence rule and its skipped-occurrence dates inside
  /// the record transaction. An unknown frequency (no parsed rule) throws, rolling
  /// the whole record back.
  private func restoreImportedRecurrenceInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, task: ExportTask
  ) throws {
    guard let exported = task.recurrence else { return }
    guard let rule = exported.rule else {
      throw LorvexCoreError.unsupportedOperation(
        "Restored without recurrence: unknown frequency \"\(exported.freq)\".")
    }
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
        taskId: TaskId(trusted: task.id), rule: ruleInput))
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: result.taskId)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: "set_recurrence", entityId: result.taskId, summary: result.summary,
        before: result.beforeTask, after: result.afterTask),
      deviceId: deviceId)

    guard let exceptions = task.recurrenceExceptions, !exceptions.isEmpty else { return }
    let dates = Array(Set(exceptions)).sorted()
    let version = hlc.nextVersionString()
    try TaskRepo.Recurrence.replaceTaskRecurrenceExceptionsInTx(
      db, taskId: TaskId(trusted: task.id), dates: dates,
      version: version, now: SyncTimestampFormat.syncTimestampNow())
    try self.enqueueUpsert(
      db, deviceId: deviceId, kind: .task, entityId: task.id, version: version,
      registerIntent: .task(.schedule))
  }
}
