import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// `LorvexHabitServicing` habit CRUD, reminder policies, and shared row mapping
/// over the pure-Swift core.
///
/// The core ships rich habit domain logic (`LorvexDomain.Habits`: cadence,
/// streaks, progress) and `HabitReminderOps` for reminder policies, but no
/// habit CRUD/completion store repo. Habit create/update/delete and the
/// completion aggregates are therefore implemented with direct SQL over the
/// `habits` / `habit_completions` tables (the same drop-to-SQL pattern the task
/// reminders and list-health paths use), funneled through the `+WriteSurface`
/// adapter for HLC + changelog + local-change-seq. Validation routes through
/// `validateHabitCreateDraft` / `validateHabitUpdateDraft` so the `lookup_key`
/// dedup and field-hygiene invariants are inherited. Reminder-policy methods
/// delegate to `HabitReminderOps`. Mapping reuses `SwiftLorvexHabitDeserializers`.
///
/// Completion logging lives in `+HabitCompletion`; streak/rate statistics live
/// in `+HabitStats`. The shared row-mapping helpers here (`mapHabitRow`,
/// `habitColumnRow`, `loadHabitsSnapshot`, `habitValueOnDate`) are used across
/// all three.
///
/// A day counts as "completed" when its `habit_completions.value >=
/// target_count` (matching `Overview.loadHabitSummary`).
extension SwiftLorvexCoreService {

  public func createHabit(
    name: String, cue: String?, icon: String?, color: String?, targetCount: Int,
    cadence: HabitCadenceInput, milestoneTarget: Int?
  ) async throws -> LorvexHabit {
    try await createHabit(
      name: name, cue: cue, icon: icon, color: color, targetCount: targetCount,
      cadence: cadence, milestoneTarget: milestoneTarget, reminderTimes: [])
  }

  public func createHabit(
    name: String, cue: String?, icon: String?, color: String?, targetCount: Int,
    cadence: HabitCadenceInput, milestoneTarget: Int?, reminderTimes: [String]
  ) async throws -> LorvexHabit {
    let milestone = try Self.normalizedMilestoneTarget(milestoneTarget)
    return try withWrite { db, hlc, deviceId in
      let domainCadence = try SwiftLorvexHabitDeserializers.cadence(from: cadence)
      let validated = try validateHabitCreateDraft(
        HabitCreateDraft(
          name: name, icon: icon, color: color, cue: cue, frequency: domainCadence,
          targetCount: Int64(targetCount)))
      let fields = validated.frequency.toFields()
      let id = EntityID.newEntityIDString()
      let version = hlc.nextVersionString()
      let now = SyncTimestampFormat.syncTimestampNow()
      try db.execute(
        sql: """
          INSERT INTO habits
            (id, name, icon, color, cue, frequency_type, per_period_target, day_of_month,
             target_count, milestone_target, archived, lookup_key, version, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)
          """,
        arguments: [
          id, validated.name, validated.icon, validated.color, validated.cue,
          fields.frequencyType, fields.perPeriodTarget, fields.dayOfMonth.map { Int64($0) },
          validated.targetCount, milestone.map { Int64($0) }, validated.lookupKey, version, now,
          now,
        ])
      try Self.replaceHabitWeekdays(db, habitId: id, weekdays: fields.weekdays ?? [])
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .habit, entityId: id)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opUpsert, entityType: EntityName.habit, entityId: id,
          summary: "Created habit '\(validated.name)'"),
        deviceId: deviceId)
      // Deduplicate while preserving the user's order. Validation or any later
      // policy write failure rolls this whole transaction back, including the
      // parent habit, so the create sheet can safely remain retryable.
      var seenReminderTimes = Set<String>()
      for time in reminderTimes where seenReminderTimes.insert(time).inserted {
        _ = try self.upsertHabitReminderPolicyInTx(
          db, hlc: hlc, deviceId: deviceId, habitID: id,
          policy: HabitReminderPolicy(
            id: "", habitID: id, habitName: validated.name, reminderTime: time,
            enabled: true, createdAt: "", updatedAt: ""))
      }
      guard let row = try Self.habitColumnRow(db, id: id) else {
        throw LorvexCoreError.unsupportedOperation("Habit '\(id)' missing after insert.")
      }
      // `completionsToday` keys off `habit_completions.completed_date`, a YMD in
      // the workflow timezone — pass that day, not the full `now` timestamp.
      let today = try WorkflowTimezone.todayYmdForConn(db)
      return try Self.mapHabitRow(db, row: row, date: today)
    }
  }

  public func importHabit(
    id: LorvexHabit.ID,
    name: String,
    icon: String?,
    color: String?,
    cue: String?,
    frequencyType: String,
    weekdays: [Int],
    perPeriodTarget: Int?,
    dayOfMonth: Int?,
    targetCount: Int,
    milestoneTarget: Int?,
    archived: Bool,
    position: Int64
  ) async throws -> LorvexHabit {
    let milestone = try Self.normalizedMilestoneTarget(milestoneTarget)
    return try withWrite { db, hlc, deviceId in
      try self.upsertImportedHabitInTx(
        db, hlc: hlc, deviceId: deviceId, id: id, name: name, icon: icon, color: color, cue: cue,
        frequencyType: frequencyType, weekdays: weekdays, perPeriodTarget: perPeriodTarget,
        dayOfMonth: dayOfMonth, targetCount: targetCount, milestone: milestone, archived: archived,
        position: position)
    }
  }

  /// Upsert one imported habit row (identity, cadence, weekdays) and enqueue its
  /// sync envelope + changelog, inside the caller's transaction. `milestone` is
  /// the already-normalized target. Shared by
  /// ``importHabit(id:name:icon:color:cue:frequencyType:weekdays:perPeriodTarget:dayOfMonth:targetCount:milestoneTarget:archived:position:)``
  /// and the transactional habit-record importer so a habit upsert commits
  /// atomically with its completions and reminder policies.
  func upsertImportedHabitInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexHabit.ID, name: String,
    icon: String?, color: String?, cue: String?, frequencyType: String, weekdays: [Int],
    perPeriodTarget: Int?, dayOfMonth: Int?, targetCount: Int, milestone: Int?, archived: Bool,
    position: Int64
  ) throws -> LorvexHabit {
    let importedCadence = try ExportHabit.cadence(
      frequencyType: frequencyType, weekdays: weekdays, perPeriodTarget: perPeriodTarget,
      dayOfMonth: dayOfMonth)
    let validated = try validateHabitCreateDraft(
      HabitCreateDraft(
        name: name, icon: icon, color: color, cue: cue, frequency: importedCadence,
        targetCount: Int64(targetCount)))
    let fields = validated.frequency.toFields()
    let existingVersion = try String.fetchOne(
      db, sql: "SELECT version FROM habits WHERE id = ?", arguments: [id])
    let version = try VersionFloor.mint(
      hlc: hlc, existingVersion: existingVersion,
      entityType: EntityName.habit, entityId: id)
    let now = SyncTimestampFormat.syncTimestampNow()
    // `created_at` is preserved on conflict (the original creation instant
    // survives re-import). Restore is authoritative, so an existing row is
    // replaced at a freshly minted version that dominates its current floor.
    // `milestone_target` is COALESCEd so a nil import (no milestone in the
    // payload) keeps any value already on the row — e.g. one that arrived via
    // sync — rather than nulling it.
    try db.execute(
      sql: """
        INSERT INTO habits
          (id, name, icon, color, cue, frequency_type, per_period_target, day_of_month,
           target_count, milestone_target, archived, lookup_key, position, version, created_at,
           updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name, icon = excluded.icon, color = excluded.color,
          cue = excluded.cue, frequency_type = excluded.frequency_type,
          per_period_target = excluded.per_period_target, day_of_month = excluded.day_of_month,
          target_count = excluded.target_count,
          milestone_target = COALESCE(excluded.milestone_target, milestone_target),
          archived = excluded.archived, lookup_key = excluded.lookup_key,
          position = excluded.position, version = excluded.version,
          updated_at = excluded.updated_at
        WHERE excluded.version > habits.version
        """,
      arguments: [
        id, validated.name, validated.icon, validated.color, validated.cue,
        fields.frequencyType, fields.perPeriodTarget, fields.dayOfMonth.map { Int64($0) },
        validated.targetCount, milestone.map { Int64($0) }, archived ? 1 : 0,
        validated.lookupKey, position, version, now, now,
      ])
    if db.changesCount == 0 {
      let observed = try String.fetchOne(
        db, sql: "SELECT version FROM habits WHERE id = ?", arguments: [id])
      guard let observed else {
        throw StoreError.invariant("habit '\(id)' vanished during import")
      }
      throw StoreError.versionSuperseded(
        entityType: EntityName.habit, entityId: id,
        attemptedVersion: version, existingVersion: observed)
    }
    try Self.replaceHabitWeekdays(db, habitId: id, weekdays: fields.weekdays ?? [])
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .habit, entityId: id)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert, entityType: EntityName.habit, entityId: id,
        summary: "Imported habit '\(validated.name)'"),
      deviceId: deviceId)
    guard let row = try Self.habitColumnRow(db, id: id) else {
      throw LorvexCoreError.unsupportedOperation("Habit '\(id)' missing after import.")
    }
    let today = try WorkflowTimezone.todayYmdForConn(db)
    return try Self.mapHabitRow(db, row: row, date: today)
  }

  public func updateHabit(
    id: LorvexHabit.ID,
    name: String?,
    cue: String?,
    color: String?,
    icon: String?,
    targetCount: Int?,
    archived: Bool?,
    cadence: HabitCadenceInput?,
    milestoneTarget: Patch<Int>
  ) async throws -> LorvexHabit {
    // Validate a `.set` milestone before opening the write transaction so an
    // invalid value fails fast without a partial mutation.
    if case .set(let value) = milestoneTarget {
      _ = try Self.normalizedMilestoneTarget(value)
    }
    return try withWrite { db, hlc, deviceId in
      let domainCadence = try cadence.map {
        try SwiftLorvexHabitDeserializers.cadence(from: $0)
      }
      let validated = try validateHabitUpdateDraft(
        HabitUpdateDraft(
          name: name,
          icon: icon.map { Patch.set($0) } ?? .unset,
          color: color.map { Patch.set($0) } ?? .unset,
          cue: cue.map { Patch.set($0) } ?? .unset,
          frequency: domainCadence,
          targetCount: targetCount.map { Int64($0) },
          archived: ArchiveAction.fromOptionalBool(archived)))

      var setClauses: [String] = []
      var args: [DatabaseValueConvertible?] = []
      if let name = validated.name {
        setClauses.append("name = ?")
        args.append(name)
        setClauses.append("lookup_key = ?")
        args.append(validated.lookupKey)
      }
      Self.appendPatch(&setClauses, &args, column: "icon", patch: validated.icon)
      Self.appendPatch(&setClauses, &args, column: "color", patch: validated.color)
      Self.appendPatch(&setClauses, &args, column: "cue", patch: validated.cue)
      if let target = validated.targetCount {
        setClauses.append("target_count = ?")
        args.append(target)
      }
      if let archivedValue = validated.archived.targetValue {
        setClauses.append("archived = ?")
        args.append(archivedValue ? 1 : 0)
      }
      // A supplied cadence replaces the whole rhythm atomically: rewrite every
      // cadence column so switching e.g. weekly → monthly clears the stale
      // per_period_target, and rebuild `habit_weekdays` (empty for a non-weekly
      // cadence, so the child ends up correctly cleared).
      if let frequency = validated.frequency {
        let fields = frequency.toFields()
        setClauses.append("frequency_type = ?")
        args.append(fields.frequencyType)
        setClauses.append("per_period_target = ?")
        args.append(fields.perPeriodTarget)
        setClauses.append("day_of_month = ?")
        args.append(fields.dayOfMonth.map { Int64($0) })
      }
      // Three-state milestone patch: `.unset` skips, `.clear` writes SQL NULL,
      // `.set` writes the (already validated) positive goal.
      switch milestoneTarget {
      case .unset:
        break
      case .clear:
        setClauses.append("milestone_target = ?")
        args.append(nil as Int64?)
      case .set(let value):
        setClauses.append("milestone_target = ?")
        args.append(Int64(value))
      }
      guard !setClauses.isEmpty else {
        guard let row = try Self.habitColumnRow(db, id: id) else {
          throw LorvexCoreError.notFound(entity: .habit, id: id)
        }
        let today = try WorkflowTimezone.todayYmdForConn(db)
        return try Self.mapHabitRow(db, row: row, date: today)
      }

      let version = hlc.nextVersionString()
      let now = SyncTimestampFormat.syncTimestampNow()
      setClauses.append("version = ?")
      args.append(version)
      setClauses.append("updated_at = ?")
      args.append(now)
      args.append(id)
      args.append(version)
      try db.execute(
        sql: "UPDATE habits SET \(setClauses.joined(separator: ", ")) WHERE id = ? AND ? > version",
        arguments: StatementArguments(args))
      // Rebuild the weekday materialization when the cadence changed. Local
      // mutations always win the LWW gate above, so the rebuild tracks the new
      // cadence; a non-weekly cadence yields an empty set that clears the child.
      if let frequency = validated.frequency {
        try Self.replaceHabitWeekdays(
          db, habitId: id, weekdays: frequency.toFields().weekdays ?? [])
      }

      guard let row = try Self.habitColumnRow(db, id: id) else {
        throw LorvexCoreError.notFound(entity: .habit, id: id)
      }
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .habit, entityId: id)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "update", entityType: EntityName.habit, entityId: id,
          summary: "Updated habit '\(row["name"] as String)'"),
        deviceId: deviceId)
      let today = try WorkflowTimezone.todayYmdForConn(db)
      return try Self.mapHabitRow(db, row: row, date: today)
    }
  }

  /// Validate a caller-supplied milestone goal: nil passes through, a positive
  /// value passes through, and a non-positive value is rejected (matching the
  /// `habits.milestone_target > 0` schema CHECK).
  static func normalizedMilestoneTarget(_ value: Int?) throws -> Int? {
    guard let value else { return nil }
    guard value > 0 else {
      throw LorvexCoreError.validation(
        field: "milestone_target", message: "milestone_target must be a positive number.")
    }
    return value
  }

  public func deleteHabit(id: LorvexHabit.ID) async throws -> HabitCatalogSnapshot {
    try deleteHabitWithReceipt(id: id).snapshot
  }

  public func deleteHabitForMcp(id: LorvexHabit.ID) async throws
    -> McpDeletionReceipt<LorvexHabit>
  {
    try deleteHabitWithReceipt(id: id).receipt
  }

  private func deleteHabitWithReceipt(id: LorvexHabit.ID) throws
    -> (snapshot: HabitCatalogSnapshot, receipt: McpDeletionReceipt<LorvexHabit>)
  {
    try withWrite { db, hlc, deviceId in
      let today = try WorkflowTimezone.todayYmdForConn(db)
      let previous = try Self.habitColumnRow(db, id: id).map { row in
        try Self.mapHabitRow(db, row: row, date: today)
      }
      let snapshot: JSONValue?
      do {
        snapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.habit, entityId: id)
      } catch EnqueueError.entityNotFound {
        // Nothing to tombstone — the row is already gone; the delete below is a no-op.
        snapshot = nil
      }
      // Any other error propagates and rolls back the whole withWrite transaction,
      // so we never permanently delete the row without emitting its sync tombstone.
      // Stamp DELETE envelopes for completions + reminder policies BEFORE the
      // habits DELETE fires its ON DELETE CASCADE on those child tables.
      try self.enqueueHabitDeleteCascade(db, hlc: hlc, deviceId: deviceId, habitId: id)
      try db.execute(sql: "DELETE FROM habits WHERE id = ?", arguments: [id])
      let deleted = db.changesCount > 0
      // Only emit the tombstone + changelog when a row was actually deleted, the
      // same way deleteList guards both; a no-op delete of a missing habit must
      // not log a spurious "Deleted habit" changelog row.
      if deleted {
        if let snapshot {
          try self.enqueueDelete(
            db, hlc: hlc, deviceId: deviceId, kind: .habit, entityId: id, payload: snapshot)
        }
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opDelete, entityType: EntityName.habit, entityId: id,
            summary: "Deleted habit '\(id)'"),
          deviceId: deviceId)
      }
      return (
        try Self.loadHabitsSnapshot(db, date: today),
        McpDeletionReceipt(previous: deleted ? previous : nil)
      )
    }
  }

}
