import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Habit completion logging over the pure-Swift core.
///
/// Completion mutations write the `habit_completions` table directly (the same
/// drop-to-SQL pattern habit CRUD uses) and funnel through `withWrite` for HLC +
/// changelog + local-change-seq. Every single-habit write resolves its habit
/// through `activeHabitRow`, which rejects an unknown or archived habit before
/// anything is written, and returns a fresh catalog snapshot after the
/// changelog row. `batchCompleteHabits` applies the same upsert across many
/// habits in one transaction and skips unknown and archived ids.
///
/// A day counts as "completed" when its `habit_completions.value >=
/// target_count`. A write that logs or raises a completion also removes the
/// habit's skip for that day (see `skipHabit(id:date:)`).
extension SwiftLorvexCoreService {

  // MARK: - Reads

  public func getHabitCompletions(
    id: LorvexHabit.ID, from: String?, to: String?, limit: Int
  ) async throws -> HabitCompletionsSnapshot {
    try read { db in
      try Self.habitCompletionsSnapshot(db, id: id, from: from, to: to, limit: limit)
    }
  }

  static func habitCompletionsSnapshot(
    _ db: Database, id: LorvexHabit.ID, from: String?, to: String?, limit: Int
  ) throws -> HabitCompletionsSnapshot {
    var sql = "SELECT habit_id, completed_date, value, note, created_at, updated_at "
      + "FROM habit_completions WHERE habit_id = ?"
    var args: [DatabaseValueConvertible] = [id]
    if let from { sql += " AND completed_date >= ?"; args.append(from) }
    if let to { sql += " AND completed_date <= ?"; args.append(to) }
    sql += " ORDER BY completed_date DESC LIMIT ?"
    args.append(max(0, limit))
    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    let entries = rows.map(SwiftLorvexHabitDeserializers.completion)
    return HabitCompletionsSnapshot(habitID: id, days: entries.count, completions: entries)
  }

  // MARK: - Writes

  public func completeHabit(id: LorvexHabit.ID, date: String) async throws -> HabitCatalogSnapshot {
    try Self.validateCompletionDate(date)
    return try withWrite { db, hlc, deviceId in
      let habitRow = try Self.activeHabitRow(db, id: id)
      let context = try Self.habitMilestoneContext(db, id: id, row: habitRow)
      let targetCount = Int(context.targetCount)
      let existing = try Row.fetchOne(
        db,
        sql: "SELECT value, version FROM habit_completions "
          + "WHERE habit_id = ? AND completed_date = ?",
        arguments: [id, date])
      let current: Int = existing?["value"] ?? 0
      let next = min(current + 1, targetCount)
      guard next != current else { return try Self.loadHabitsSnapshot(db, date: date) }

      // The milestone metric before the write, then after — a completion can only
      // cross a milestone by moving this reading upward.
      let totalBefore = try Self.habitTotalCompletions(db, id: id)
      let prevMetric = try Self.habitMilestoneMetricValue(
        db, habitId: id, metric: context.metric, cadence: context.cadence,
        targetCount: context.targetCount, totalCompletions: totalBefore, today: date)

      let existingVersion: String? = existing?["version"]
      let version = try VersionFloor.mint(
        hlc: hlc, existingVersion: existingVersion,
        entityType: EntityKind.habitCompletion.asString, entityId: "\(id):\(date)")
      let now = SyncTimestampFormat.syncTimestampNow()
      try db.execute(
        sql: """
          INSERT INTO habit_completions
            (habit_id, completed_date, value, version, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(habit_id, completed_date) DO UPDATE SET
            value = excluded.value, version = excluded.version, updated_at = excluded.updated_at
          """,
        arguments: [id, date, next, version, now, now])
      try self.enqueueHabitCompletionUpsert(
        db, hlc: hlc, deviceId: deviceId, habitId: id, completedDate: date)
      try self.removeHabitSkipInTx(db, hlc: hlc, deviceId: deviceId, habitId: id, date: date)

      let newMetric = try Self.habitMilestoneMetricValue(
        db, habitId: id, metric: context.metric, cadence: context.cadence,
        targetCount: context.targetCount, totalCompletions: totalBefore + (next - current),
        today: date)
      let reached = justReachedHabitMilestone(
        prev: prevMetric, new: newMetric, target: context.milestoneTarget, metric: context.metric)

      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "complete", entityType: EntityName.habit, entityId: id,
          summary: "Habit complete: \(id) on \(date)"),
        deviceId: deviceId)
      let snapshot = try Self.loadHabitsSnapshot(db, date: date)
      return Self.snapshot(snapshot, settingJustReached: reached, forHabit: id)
    }
  }

  public func uncompleteHabit(id: LorvexHabit.ID, date: String) async throws -> HabitCatalogSnapshot
  {
    try habitCompletionMutation(id: id, date: date, operation: "uncomplete") { db, hlc, deviceId in
      // Edge rows have no snapshot-reader route; build the pre-delete payload
      // from the live row before the DELETE removes it.
      let existing = try Row.fetchOne(
        db,
        sql: """
          SELECT habit_id, completed_date, value, note, created_at, updated_at, version
          FROM habit_completions WHERE habit_id = ? AND completed_date = ?
          """,
        arguments: [id, date]
      )
      let snapshot: JSONValue? = existing.map { row in
        PayloadLoaders.habitCompletionPayload(
          habitId: row["habit_id"], completedDate: row["completed_date"], value: row["value"],
          note: row["note"], version: row["version"], createdAt: row["created_at"],
          updatedAt: row["updated_at"])
      }
      try db.execute(
        sql: "DELETE FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
        arguments: [id, date])
      if db.changesCount > 0, let snapshot, let existing {
        let existingVersion: String = existing["version"]
        try self.enqueueHabitCompletionDelete(
          db, hlc: hlc, deviceId: deviceId, habitId: id, completedDate: date,
          existingVersion: existingVersion, payload: snapshot)
        return true
      }
      return false
    }
  }

  public func adjustHabitCompletion(id: LorvexHabit.ID, date: String, delta: Int) async throws
    -> HabitCatalogSnapshot
  {
    try Self.validateCompletionDate(date)
    return try withWrite { db, hlc, deviceId in
      let habitRow = try Self.activeHabitRow(db, id: id)
      let context = try Self.habitMilestoneContext(db, id: id, row: habitRow)
      let target = Int(context.targetCount)
      let existing = try Row.fetchOne(
        db,
        sql: "SELECT value, version FROM habit_completions "
          + "WHERE habit_id = ? AND completed_date = ?",
        arguments: [id, date])
      let current: Int = existing?["value"] ?? 0
      // The result is clamped to [0, target], so a delta beyond that span lands
      // where the clamp would put it; limiting it first keeps the sum from overflowing.
      let step = min(max(delta, -target), target)
      let next = delta == 0 ? (current >= target ? 0 : target) : min(max(current + step, 0), target)
      // A no-op adjustment leaves the row, sync outbox, and changelog untouched.
      guard next != current else { return try Self.loadHabitsSnapshot(db, date: date) }

      let now = SyncTimestampFormat.syncTimestampNow()
      var reached: Int? = nil
      if next > current {
        // The completion value increases here — the only branch that can cross a
        // milestone. Read the metric before and after the write (same before/after
        // pattern as `completeHabit`) and report the milestone it just crossed.
        let totalBefore = try Self.habitTotalCompletions(db, id: id)
        let prevMetric = try Self.habitMilestoneMetricValue(
          db, habitId: id, metric: context.metric, cadence: context.cadence,
          targetCount: context.targetCount, totalCompletions: totalBefore, today: date)
        let existingVersion: String? = existing?["version"]
        let version = try VersionFloor.mint(
          hlc: hlc, existingVersion: existingVersion,
          entityType: EntityKind.habitCompletion.asString, entityId: "\(id):\(date)")
        try db.execute(
          sql: """
            INSERT INTO habit_completions
              (habit_id, completed_date, value, version, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(habit_id, completed_date) DO UPDATE SET
              value = excluded.value, version = excluded.version, updated_at = excluded.updated_at
            """,
          arguments: [id, date, next, version, now, now])
        try self.enqueueHabitCompletionUpsert(
          db, hlc: hlc, deviceId: deviceId, habitId: id, completedDate: date)
        try self.removeHabitSkipInTx(db, hlc: hlc, deviceId: deviceId, habitId: id, date: date)
        let newMetric = try Self.habitMilestoneMetricValue(
          db, habitId: id, metric: context.metric, cadence: context.cadence,
          targetCount: context.targetCount, totalCompletions: totalBefore + (next - current),
          today: date)
        reached = justReachedHabitMilestone(
          prev: prevMetric, new: newMetric, target: context.milestoneTarget, metric: context.metric)
      } else if next > 0 {
        let existingVersion: String? = existing?["version"]
        let version = try VersionFloor.mint(
          hlc: hlc, existingVersion: existingVersion,
          entityType: EntityKind.habitCompletion.asString, entityId: "\(id):\(date)")
        try db.execute(
          sql: """
            UPDATE habit_completions
            SET value = ?, version = ?, updated_at = ?
            WHERE habit_id = ? AND completed_date = ?
            """,
          arguments: [next, version, now, id, date])
        try self.enqueueHabitCompletionUpsert(
          db, hlc: hlc, deviceId: deviceId, habitId: id, completedDate: date)
      } else {
        // Decremented to zero: drop the row, mirroring `uncompleteHabit`.
        let deleteRow = try Row.fetchOne(
          db,
          sql: """
            SELECT habit_id, completed_date, value, note, created_at, updated_at, version
            FROM habit_completions WHERE habit_id = ? AND completed_date = ?
            """,
          arguments: [id, date]
        )
        let snapshot: JSONValue? = deleteRow.map { row in
          PayloadLoaders.habitCompletionPayload(
            habitId: row["habit_id"], completedDate: row["completed_date"], value: row["value"],
            note: row["note"], version: row["version"], createdAt: row["created_at"],
            updatedAt: row["updated_at"])
        }
        try db.execute(
          sql: "DELETE FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
          arguments: [id, date])
        if db.changesCount > 0, let snapshot, let deleteRow {
          let existingVersion: String = deleteRow["version"]
          try self.enqueueHabitCompletionDelete(
            db, hlc: hlc, deviceId: deviceId, habitId: id, completedDate: date,
            existingVersion: existingVersion, payload: snapshot)
        }
      }
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "adjust", entityType: EntityName.habit, entityId: id,
          summary: "Habit adjust: \(id) on \(date) → \(next)"),
        deviceId: deviceId)
      let snapshot = try Self.loadHabitsSnapshot(db, date: date)
      return Self.snapshot(snapshot, settingJustReached: reached, forHabit: id)
    }
  }

  /// Rejects a non-canonical completion date before any write, so every surface
  /// (app, MCP, CLI) shares the guard daily reviews already apply. A malformed
  /// key like "2026-6-9" or "June 9" would otherwise miscount lexicographic
  /// streaks, coexist with the canonical row for the same day, and ship the bad
  /// key to peers as the sync edge id.
  static func validateCompletionDate(_ date: String) throws {
    if case .failure(let error) = IsoDate.parseIsoDate(date) {
      throw LorvexCoreError.validation(field: "date", message: error.description)
    }
  }

  /// The row of a habit whose check-ins or skipped days a write logs or edits.
  /// An unknown id is not-found. An archived habit is rejected before anything
  /// is written: it is hidden from every surface and absent from the catalog
  /// snapshot a completion or skip write returns, so a day recorded against it
  /// could not be shown back to the caller, and the caller would see an error
  /// for a write that had already committed.
  static func activeHabitRow(_ db: Database, id: LorvexHabit.ID) throws -> Row {
    guard let row = try habitColumnRow(db, id: id) else {
      throw LorvexCoreError.notFound(entity: .habit, id: id)
    }
    let archived: Int64 = row["archived"]
    guard archived == 0 else {
      let name: String = row["name"]
      throw LorvexCoreError.validation(
        field: "id",
        message: "Habit '\(name)' is archived. Restore it before changing its check-ins or skipped days.")
    }
    return row
  }

  public func batchCompleteHabits(ids: [LorvexHabit.ID], date: String) async throws
    -> HabitCatalogSnapshot
  {
    try batchCompleteHabitsWithReceipt(ids: ids, date: date).snapshot
  }

  public func batchCompleteHabitsForMcp(
    ids: [LorvexHabit.ID], date: String
  ) async throws -> McpHabitBatchCompletionReceipt {
    try batchCompleteHabitsWithReceipt(ids: ids, date: date)
  }

  private func batchCompleteHabitsWithReceipt(
    ids: [LorvexHabit.ID], date: String
  ) throws -> McpHabitBatchCompletionReceipt {
    try Self.validateCompletionDate(date)
    return try withWrite { db, hlc, deviceId in
      let now = SyncTimestampFormat.syncTimestampNow()
      var completedIds: [LorvexHabit.ID] = []
      var notFoundIds: [LorvexHabit.ID] = []
      var alreadyCompleteIds: [LorvexHabit.ID] = []
      var archivedIds: [LorvexHabit.ID] = []
      var reachedByID: [LorvexHabit.ID: Int] = [:]
      for id in ids {
        // An unknown or archived habit id is skipped, not written.
        // `batchCompleteHabits` is skip-and-report, like `batchCompleteTasks` /
        // `batchCancelTasks`: the receipt lists each skipped id under its reason.
        // Writing a completion row for a missing habit would violate the
        // `habit_id` foreign key and roll back the whole batch (dropping the
        // valid habits too), and a completion logged against an archived habit
        // would be invisible in the returned catalog, so the guard mirrors the
        // single-write `completeHabit` rejection and keeps the rest of the batch
        // intact.
        guard let habitRow = try Self.habitColumnRow(db, id: id) else {
          notFoundIds.append(id)
          continue
        }
        let archived: Int64 = habitRow["archived"]
        guard archived == 0 else {
          archivedIds.append(id)
          continue
        }
        let context = try Self.habitMilestoneContext(db, id: id, row: habitRow)
        let targetCount = Int(context.targetCount)
        let existing = try Row.fetchOne(
          db,
          sql: "SELECT value, version FROM habit_completions "
            + "WHERE habit_id = ? AND completed_date = ?",
          arguments: [id, date])
        let current: Int = existing?["value"] ?? 0
        let next = min(current + 1, targetCount)
        guard next != current else {
          alreadyCompleteIds.append(id)
          continue
        }

        let totalBefore = try Self.habitTotalCompletions(db, id: id)
        let prevMetric = try Self.habitMilestoneMetricValue(
          db, habitId: id, metric: context.metric, cadence: context.cadence,
          targetCount: context.targetCount, totalCompletions: totalBefore, today: date)

        let existingVersion: String? = existing?["version"]
        let version = try VersionFloor.mint(
          hlc: hlc, existingVersion: existingVersion,
          entityType: EntityKind.habitCompletion.asString, entityId: "\(id):\(date)")
        try db.execute(
          sql: """
            INSERT INTO habit_completions
              (habit_id, completed_date, value, version, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(habit_id, completed_date) DO UPDATE SET
              value = excluded.value, version = excluded.version, updated_at = excluded.updated_at
            """,
          arguments: [id, date, next, version, now, now])
        try self.enqueueHabitCompletionUpsert(
          db, hlc: hlc, deviceId: deviceId, habitId: id, completedDate: date)
        try self.removeHabitSkipInTx(db, hlc: hlc, deviceId: deviceId, habitId: id, date: date)
        completedIds.append(id)

        let newMetric = try Self.habitMilestoneMetricValue(
          db, habitId: id, metric: context.metric, cadence: context.cadence,
          targetCount: context.targetCount, totalCompletions: totalBefore + (next - current),
          today: date)
        if let reached = justReachedHabitMilestone(
          prev: prevMetric, new: newMetric, target: context.milestoneTarget, metric: context.metric)
        {
          reachedByID[id] = reached
        }
      }
      if !completedIds.isEmpty {
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: "batch_complete", entityType: EntityName.habit, entityId: completedIds.first,
            entityIds: completedIds,
            summary:
              "Completed \(completedIds.count) habit\(completedIds.count == 1 ? "" : "s") on \(date)"),
          deviceId: deviceId)
      }
      var snapshot = try Self.loadHabitsSnapshot(db, date: date)
      for (id, reached) in reachedByID {
        snapshot = Self.snapshot(snapshot, settingJustReached: reached, forHabit: id)
      }
      return McpHabitBatchCompletionReceipt(
        snapshot: snapshot, completedIDs: completedIds, notFoundIDs: notFoundIds,
        alreadyCompleteIDs: alreadyCompleteIds, archivedIDs: archivedIds)
    }
  }

  // MARK: - Shared funnel

  private func enqueueHabitCompletionDelete(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    habitId: String,
    completedDate: String,
    existingVersion: String,
    payload: JSONValue
  ) throws {
    let entityId = "\(habitId):\(completedDate)"
    let deleteVersion = try VersionFloor.mint(
      hlc: hlc, existingVersion: existingVersion,
      entityType: EntityKind.habitCompletion.asString, entityId: entityId)
    try OutboxEnqueue.enqueuePayloadDelete(
      db,
      entityType: EntityKind.habitCompletion.asString,
      entityId: entityId,
      payload: payload,
      context: OutboxWriteContext(version: deleteVersion, deviceId: deviceId))
  }

  private func habitCompletionMutation(
    id: LorvexHabit.ID,
    date: String,
    operation: String,
    _ mutate: (Database, HlcSession, String) throws -> Bool
  ) throws -> HabitCatalogSnapshot {
    try Self.validateCompletionDate(date)
    return try withWrite { db, hlc, deviceId in
      _ = try Self.activeHabitRow(db, id: id)
      let changed = try mutate(db, hlc, deviceId)
      guard changed else { return try Self.loadHabitsSnapshot(db, date: date) }
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: operation, entityType: EntityName.habit, entityId: id,
          summary: "Habit \(operation): \(id) on \(date)"),
        deviceId: deviceId)
      return try Self.loadHabitsSnapshot(db, date: date)
    }
  }
}
