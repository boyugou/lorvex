import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-entity apply handlers for the independent child entities — rows that
/// reference a parent aggregate root via FK but are synced as standalone
/// envelopes (each has its own `id` PK and `version` column).
///
/// Three children: `task_reminder`, `task_checklist_item`,
/// `habit_reminder_policy`. Each upsert runs the shared LWW-gated
/// `LwwUpsertSpec`; each delete routes through ``ApplyLww/lwwGatedDelete`` so
/// the in-row LWW guard parses the typed HLC.
///
/// Parent-existence gating + FK-deferral happens upstream in
/// ``ApplyFk/checkFkDependencies(_:entityType:entityId:payload:)`` (the
/// dispatcher parks the envelope in `sync_pending_inbox` when a parent is
/// missing), so these handlers assume the parent FK is satisfied.
enum ApplyChild {

  // MARK: - task_reminder

  /// Canonicalize an RFC 3339 instant for delivery-state change detection; falls
  /// back to the raw string when canonicalization fails.
  private static func reminderInstantKey(_ value: String) -> String {
    SyncTimestampFormat.canonicalizeRfc3339Instant(value) ?? value
  }

  @discardableResult
  static func applyTaskReminderUpsert(
    _ db: Database, entityId: String, payload: String, version: String,
    tieBreak: LwwTieBreak, applyTs: String = SyncTimestamp.now().asString
  ) throws -> TaskGraphRepairTarget? {
    let val = try ApplyJSON.parseObject(payload)

    let taskId = try ApplyJSON.requiredStr(val, "task_id", entity: "task_reminder")
    let reminderAtRaw = try ApplyJSON.requiredStr(val, "reminder_at", entity: "task_reminder")
    guard let reminderAt = SyncTimestampFormat.canonicalizeRfc3339Instant(reminderAtRaw) else {
      throw ApplyError.invalidPayload(
        "task_reminder payload.reminder_at must be a valid RFC 3339 datetime, got "
          + "'\(reminderAtRaw)'")
    }
    let dismissedAt = try ApplyJSON.optionalStr(val, "dismissed_at", entity: "task_reminder")
    let cancelledAt = try ApplyJSON.optionalStr(val, "cancelled_at", entity: "task_reminder")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "task_reminder")
    let originalLocalTime = try ApplyJSON.optionalStr(
      val, "original_local_time", entity: "task_reminder")
    let originalTz = try ApplyJSON.optionalStr(val, "original_tz", entity: "task_reminder")

    let previousReminderAt = try fetchReminderAt(db, id: entityId)

    let sql = LwwUpsertSpec(
      table: "task_reminders",
      columns: SyncEntityDescriptor.require(.taskReminder).plainColumns,
      conflict: ["id"], tieBreak: tieBreak
    ).buildSQL()
    do {
      try db.execute(
        sql: sql,
        arguments: [
          "id": entityId, "task_id": taskId, "reminder_at": reminderAt,
          "dismissed_at": dismissedAt, "cancelled_at": cancelledAt, "created_at": createdAt,
          "original_local_time": originalLocalTime, "original_tz": originalTz, "version": version,
        ])
    } catch { throw ApplyError.lift(error) }

    let storedReminderAt = try fetchReminderAt(db, id: entityId)
    let timeChanged: Bool
    if let prev = previousReminderAt, let curr = storedReminderAt {
      timeChanged = reminderInstantKey(prev) != reminderInstantKey(curr)
    } else {
      timeChanged = false
    }
    if timeChanged {
      do {
        try db.execute(
          sql: "DELETE FROM task_reminder_delivery_state WHERE reminder_id = ?",
          arguments: [entityId])
      } catch { throw ApplyError.lift(error) }
    }
    return try TaskGraphReconciliation.normalizeReminderForTerminalTask(
      db, reminderId: entityId, taskId: taskId, applyTs: applyTs)
  }

  private static func fetchReminderAt(_ db: Database, id: String) throws -> String? {
    do {
      return try String.fetchOne(
        db, sql: "SELECT reminder_at FROM task_reminders WHERE id = ?", arguments: [id])
    } catch { throw ApplyError.lift(error) }
  }

  static func applyTaskReminderDelete(_ db: Database, entityId: String, version: String) throws {
    try ApplyLww.lwwGatedDelete(
      db, table: "task_reminders", pkColumns: ["id"], pkValues: [entityId],
      incomingVersion: version)
  }

  // MARK: - task_checklist_item

  static func applyTaskChecklistItemUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws {
    let val = try ApplyJSON.parseObject(payload)

    let taskId = try ApplyJSON.requiredStr(val, "task_id", entity: "task_checklist_item")
    let position = try ApplyJSON.requiredInt64(val, "position", entity: "task_checklist_item")
    let text = ApplyAggregate.scrub(
      try ApplyJSON.requiredStr(val, "text", entity: "task_checklist_item"))
    let completedAt = try ApplyJSON.optionalStr(val, "completed_at", entity: "task_checklist_item")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "task_checklist_item")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "task_checklist_item")

    let sql = LwwUpsertSpec(
      table: "task_checklist_items",
      columns: SyncEntityDescriptor.require(.taskChecklistItem).plainColumns,
      conflict: ["id"], tieBreak: tieBreak
    ).buildSQL()
    do {
      try db.execute(
        sql: sql,
        arguments: [
          "id": entityId, "task_id": taskId, "position": position, "text": text,
          "completed_at": completedAt, "created_at": createdAt, "updated_at": updatedAt,
          "version": version,
        ])
    } catch { throw ApplyError.lift(error) }
  }

  static func applyTaskChecklistItemDelete(_ db: Database, entityId: String, version: String) throws
  {
    try ApplyLww.lwwGatedDelete(
      db, table: "task_checklist_items", pkColumns: ["id"], pkValues: [entityId],
      incomingVersion: version)
  }

  // MARK: - habit_reminder_policy

  static func applyHabitReminderPolicyUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak,
    applyTs: String
  ) throws {
    let val = try ApplyJSON.parseObject(payload)

    let habitId = try ApplyJSON.requiredStr(val, "habit_id", entity: "habit_reminder_policy")
    let reminderTime = try ApplyJSON.requiredStr(
      val, "reminder_time", entity: "habit_reminder_policy")
    // Every first-party reminder-policy writer in both apps stores `reminder_time`
    // as a strict 5-byte `HH:MM` (24h) via the shared HH:MM validator; the
    // scheduler parses it back the same way. This relay binds the peer's value
    // verbatim, so pre-validate the shape here: a malformed value (`9:5`,
    // `09:00:00`, empty, AM/PM) drops as a typed InvalidPayload skip with a clear
    // reason rather than landing a row the reminder scheduler cannot parse. (The
    // collision-merge staging value is applied separately below and is never a
    // payload field, so it is not subject to this gate.)
    if Parsing.parseHhmmToMinutes(reminderTime) == nil {
      throw ApplyError.invalidPayload(
        "habit_reminder_policy payload.reminder_time must be HH:MM (00:00-23:59), got "
          + "'\(reminderTime)'")
    }
    let enabled = try ApplyJSON.requiredBoolAsInt64(val, "enabled", entity: "habit_reminder_policy")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "habit_reminder_policy")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "habit_reminder_policy")

    let sql = LwwUpsertSpec(
      table: "habit_reminder_policies",
      columns: SyncEntityDescriptor.require(.habitReminderPolicy).plainColumns,
      conflict: ["id"], tieBreak: tieBreak, createdAtFloor: true
    ).buildSQL()

    func runUpsert(_ db: Database, reminderTime: String) throws {
      try db.execute(
        sql: sql,
        arguments: [
          "id": entityId, "habit_id": habitId, "reminder_time": reminderTime, "enabled": enabled,
          "created_at": createdAt, "updated_at": updatedAt, "version": version,
        ])
    }

    let outcome: CollisionMergeOutcome
    do {
      try runUpsert(db, reminderTime: reminderTime)
      outcome = CollisionMergeOutcome(
        incomingSurvived: db.changesCount > 0, mergeRan: false)
    } catch let dbError as DatabaseError
      where dbError.isUniqueConstraintViolation
    {
      // Sync-wedge fix (W-1): two devices added a reminder for the SAME habit at
      // the SAME time offline with distinct policy ids, so the second trips
      // `UNIQUE(habit_id, reminder_time)`. Converge it (min id wins, loser
      // tombstoned with redirect) rather than letting the constraint escape as the
      // batch-fatal `ApplyError.db` that wedges the inbound page. Stage the incoming
      // with a synthetic non-colliding reminder_time so it lands beside the existing
      // claimant; the merge collapses the duplicates and restores the real time to
      // the winner.
      outcome = try ApplyHabitReminderPolicyMerge.insertPolicyByMergingCollision(
        db, entityId: entityId, habitId: habitId, reminderTime: reminderTime, version: version,
        applyTs: applyTs, originalError: dbError
      ) { db in
        try runUpsert(
          db, reminderTime: ApplyHabitReminderPolicyMerge.stagingReminderTime(for: entityId))
      }
    } catch { throw ApplyError.lift(error) }

    // Version-rejected payloads still lower the creation floor (min-register;
    // see ApplyLww.foldCreatedAtFloor). After a collision merge this id may be
    // a deleted loser — the guarded UPDATE then matches no row, and the merge
    // itself already folded every participant's floor into the winner.
    try ApplyLww.foldCreatedAtFloor(
      db, table: "habit_reminder_policies", pkValue: entityId, incomingCreatedAt: createdAt)

    // Post-upsert dedup tail: only when the upsert landed and the collision path
    // did not already merge. Defensive convergence pass mirroring
    // the aggregate merge engine.
    if outcome.incomingSurvived && !outcome.mergeRan {
      try ApplyHabitReminderPolicyMerge.mergeDuplicatePolicies(
        db, justUpsertedId: entityId, habitId: habitId, reminderTime: reminderTime,
        version: version, applyTs: applyTs)
    }
  }

  static func applyHabitReminderPolicyDelete(_ db: Database, entityId: String, version: String)
    throws
  {
    try ApplyLww.lwwGatedDelete(
      db, table: "habit_reminder_policies", pkColumns: ["id"], pkValues: [entityId],
      incomingVersion: version)
  }

}

// MARK: - EntityApplier conformances

public struct TaskReminderApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityKind.taskReminder.asString] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    let repair = try ApplyChild.applyTaskReminderUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak, applyTs: applyTs)
    if let repair {
      return .repairRequired(
        .propagateTaskRollover(
          targets: [repair], additionalFloor: envelope.version))
    }
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyChild.applyTaskReminderDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

public struct TaskChecklistItemApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityKind.taskChecklistItem.asString] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyChild.applyTaskChecklistItemUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyChild.applyTaskChecklistItemDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

public struct HabitReminderPolicyApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityKind.habitReminderPolicy.asString] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyChild.applyHabitReminderPolicyUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak, applyTs: applyTs)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyChild.applyHabitReminderPolicyDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}
