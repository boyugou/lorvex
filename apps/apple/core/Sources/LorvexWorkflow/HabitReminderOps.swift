import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Habit reminder policy CRUD — the canonical implementations every write
/// surface (MCP, app, CLI) delegates to instead of maintaining independent SQL.
public enum HabitReminderOps {
  /// A fully loaded habit reminder policy row, joined with the habit name.
  ///
  /// `version` is carried so callers that route through the canonical
  /// `habit_reminder_policy` payload builder emit the 7-field wire shape.
  public struct HabitReminderPolicyRow: Sendable, Equatable {
    public let id: String
    public let habitId: String
    public let habitName: String
    public let reminderTime: String
    public let enabled: Bool
    public let createdAt: String
    public let updatedAt: String
    public let version: String
  }

  private static let policySelect =
    "SELECT p.id, p.habit_id, h.name, p.reminder_time, p.enabled, p.created_at, p.updated_at, "
    + "p.version "
    + "FROM habit_reminder_policies p JOIN habits h ON h.id = p.habit_id"

  private static func rowFromQuery(_ row: Row) -> HabitReminderPolicyRow {
    HabitReminderPolicyRow(
      id: row[0], habitId: row[1], habitName: row[2], reminderTime: row[3],
      enabled: (row[4] as Int64) != 0, createdAt: row[5], updatedAt: row[6], version: row[7])
  }

  /// Load a single habit reminder policy by ID. Returns `nil` when the row
  /// does not exist; reserves a thrown error for genuine query failures.
  public static func loadPolicyById(_ db: Database, policyId: String) throws
    -> HabitReminderPolicyRow?
  {
    guard
      let row = try Row.fetchOne(
        db, sql: "\(policySelect) WHERE p.id = ?", arguments: [policyId])
    else { return nil }
    return rowFromQuery(row)
  }

  /// Load all habit reminder policies, ordered by habit name (case-insensitive)
  /// then reminder time.
  public static func listAllPolicies(_ db: Database) throws -> [HabitReminderPolicyRow] {
    let rows = try Row.fetchAll(
      db, sql: "\(policySelect) ORDER BY h.name COLLATE NOCASE ASC, p.reminder_time ASC")
    return rows.map(rowFromQuery)
  }

  /// Load the reminder policies for one habit, ordered by reminder time. Filters
  /// in SQL rather than loading every habit's policies and discarding the rest.
  public static func listPolicies(_ db: Database, habitId: String) throws
    -> [HabitReminderPolicyRow]
  {
    let rows = try Row.fetchAll(
      db, sql: "\(policySelect) WHERE p.habit_id = ? ORDER BY p.reminder_time ASC",
      arguments: [habitId])
    return rows.map(rowFromQuery)
  }

  /// ID of an existing policy that would conflict (same habit + same time),
  /// optionally excluding a specific policy ID (for updates).
  private static func loadConflictingSlotId(
    _ db: Database, habitId: String, reminderTime: String, excludingId: String?
  ) throws -> String? {
    if let excludingId = excludingId {
      return try String.fetchOne(
        db,
        sql: "SELECT id FROM habit_reminder_policies "
          + "WHERE habit_id = ? AND reminder_time = ? AND id != ?",
        arguments: [habitId, reminderTime, excludingId])
    }
    return try String.fetchOne(
      db,
      sql: "SELECT id FROM habit_reminder_policies WHERE habit_id = ? AND reminder_time = ?",
      arguments: [habitId, reminderTime])
  }

  /// Parameters for upserting a habit reminder policy. `policyId` `nil` or
  /// blank means create new; the caller supplies `version` and `now`.
  public struct UpsertParams: Sendable {
    public let policyId: String?
    public let habitId: String
    public let reminderTime: String
    public let enabled: Bool
    public let version: String
    public let now: String

    public init(
      policyId: String?, habitId: String, reminderTime: String, enabled: Bool,
      version: String, now: String
    ) {
      self.policyId = policyId
      self.habitId = habitId
      self.reminderTime = reminderTime
      self.enabled = enabled
      self.version = version
      self.now = now
    }
  }

  /// Create or update a habit reminder policy.
  ///
  /// Validates that `habit_id` is non-empty and references an existing habit,
  /// `reminder_time` is valid `HH:MM`, no other slot exists at the same time
  /// for the same habit, and (on update) the slot belongs to the named habit.
  /// Returns the fully loaded policy row.
  public static func upsertHabitReminderPolicy(_ db: Database, params: UpsertParams) throws
    -> HabitReminderPolicyRow
  {
    let habitId = params.habitId.trimmingCharacters(in: .whitespaces)
    if habitId.isEmpty {
      throw StoreError.validation("habit_id must not be empty")
    }

    if case .failure(let e) = ValidationFormat.validateTimeFormat(params.reminderTime) {
      throw StoreError.validation(
        "invalid reminder_time '\(params.reminderTime)': \(e.description)")
    }

    let habitExists = try String.fetchOne(
      db, sql: "SELECT id FROM habits WHERE id = ?", arguments: [habitId])
    if habitExists == nil {
      throw StoreError.notFound(entity: "habit", id: habitId)
    }

    let enabledVal: Int64 = params.enabled ? 1 : 0

    let resolvedPolicyId: String
    let trimmedPolicyId = params.policyId?.trimmingCharacters(in: .whitespaces)
    if let id = trimmedPolicyId, !id.isEmpty {
      // UPDATE path.
      guard
        let existing = try Row.fetchOne(
          db,
          sql: "SELECT habit_id FROM habit_reminder_policies WHERE id = ?",
          arguments: [id])
      else {
        throw StoreError.notFound(entity: "habit_reminder_policy", id: id)
      }
      let existingHabitId: String = existing["habit_id"]
      if existingHabitId != habitId {
        throw StoreError.validation(
          "habit reminder slot '\(id)' belongs to a different habit")
      }
      if try loadConflictingSlotId(
        db, habitId: habitId, reminderTime: params.reminderTime, excludingId: id) != nil
      {
        throw StoreError.validation(
          "habit '\(habitId)' already has a reminder slot at \(params.reminderTime)")
      }
      try db.execute(
        sql: "UPDATE habit_reminder_policies "
          + "SET reminder_time = ?, enabled = ?, version = ?, updated_at = ? "
          + "WHERE id = ? AND version < ?",
        arguments: [
          params.reminderTime, enabledVal, params.version, params.now, id, params.version,
        ])
      if db.changesCount == 0 {
        let observed = try String.fetchOne(
          db, sql: "SELECT version FROM habit_reminder_policies WHERE id = ?", arguments: [id])
        guard let observed else {
          throw StoreError.notFound(entity: EntityName.habitReminderPolicy, id: id)
        }
        throw StoreError.versionSuperseded(
          entityType: EntityName.habitReminderPolicy, entityId: id,
          attemptedVersion: params.version,
          existingVersion: observed)
      }
      resolvedPolicyId = id
    } else {
      // INSERT path.
      if try loadConflictingSlotId(
        db, habitId: habitId, reminderTime: params.reminderTime, excludingId: nil) != nil
      {
        throw StoreError.validation(
          "habit '\(habitId)' already has a reminder slot at \(params.reminderTime)")
      }
      let id = EntityID.newEntityIDString()
      try db.execute(
        sql: "INSERT INTO habit_reminder_policies "
          + "(id, habit_id, reminder_time, enabled, version, created_at, updated_at) "
          + "VALUES (?, ?, ?, ?, ?, ?, ?)",
        arguments: [
          id, habitId, params.reminderTime, enabledVal, params.version, params.now, params.now,
        ])
      resolvedPolicyId = id
    }

    guard let row = try loadPolicyById(db, policyId: resolvedPolicyId) else {
      throw StoreError.validation(
        "habit reminder policy '\(resolvedPolicyId)' not found after upsert")
    }
    return row
  }

  /// Result of deleting a habit reminder policy.
  public struct DeleteResult: Sendable, Equatable {
    public let deleted: Bool
  }

  /// Delete a habit reminder policy by ID. Returns whether a row was removed.
  public static func deleteHabitReminderPolicy(_ db: Database, policyId: String) throws
    -> DeleteResult
  {
    try db.execute(
      sql: "DELETE FROM habit_reminder_policies WHERE id = ?", arguments: [policyId])
    return DeleteResult(deleted: db.changesCount > 0)
  }

  /// Stamp `habit_reminder_delivery_state.last_delivered_at` for `policyId` so the
  /// occurrence planner debounces same-period re-nudges. Device-local (never
  /// synced). `deliveredAt` is the instant the most recent in-period occurrence
  /// elapsed; `now` is the write timestamp. The deterministic device-local
  /// analog of an OS delivery callback (Apple pre-schedules notifications the
  /// system fires without a reliable callback). Callers gate this on the
  /// policy's `last_armed_at`: only an occurrence this device actually armed
  /// with the OS can be recorded as delivered.
  public static func markHabitReminderDelivered(
    _ db: Database, policyId: String, deliveredAt: String, now: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO habit_reminder_delivery_state \
            (policy_id, last_delivered_at, updated_at) \
        VALUES (?1, ?2, ?3) \
        ON CONFLICT(policy_id) DO UPDATE SET \
          last_delivered_at = excluded.last_delivered_at, \
          updated_at = excluded.updated_at
        """,
      arguments: [policyId, deliveredAt, now])
  }

  /// Replace the device's armed-occurrence record with exactly the occurrences
  /// the habit notification scheduler reported as accepted this pass.
  ///
  /// `armedThroughByPolicy` maps a policy id to the latest occurrence fire
  /// time (sync-timestamp string) the OS accepted a request for; the armed set
  /// per policy is the contiguous earliest prefix of its occurrences, so one
  /// "armed through" instant fully describes it. Two writes keep
  /// `last_armed_at` a mirror of the currently pending
  /// `UNUserNotificationCenter` request set, which every replace pass rebuilds
  /// from scratch:
  /// - each mapped policy is stamped with its armed-through instant;
  /// - every other policy's `last_armed_at` is cleared back to NULL, because
  ///   the replace pass just removed its OS requests (budgeted out, permission
  ///   denied, or add failed).
  ///
  /// The delivered reconciler only records occurrences at or before
  /// `last_armed_at`, so clearing keeps a dropped nudge visible as due instead
  /// of letting a stale armed stamp record a phantom delivery.
  public static func replaceHabitRemindersArmed(
    _ db: Database, armedThroughByPolicy: [String: String], now: String
  ) throws {
    let armedPolicyIds = Array(armedThroughByPolicy.keys).sorted()
    let placeholders = Array(
      repeating: "?", count: armedPolicyIds.count
    ).joined(separator: ", ")
    let notInClause =
      armedPolicyIds.isEmpty ? "" : "AND policy_id NOT IN (\(placeholders)) "
    try db.execute(
      sql: """
        UPDATE habit_reminder_delivery_state SET \
          last_armed_at = NULL, \
          updated_at = ?1 \
        WHERE last_armed_at IS NOT NULL \
          \(notInClause)
        """,
      arguments: StatementArguments([now] + armedPolicyIds))
    for policyId in armedPolicyIds {
      guard let armedThrough = armedThroughByPolicy[policyId] else { continue }
      try db.execute(
        sql: """
          INSERT INTO habit_reminder_delivery_state \
              (policy_id, last_armed_at, updated_at) \
          VALUES (?1, ?2, ?3) \
          ON CONFLICT(policy_id) DO UPDATE SET \
            last_armed_at = excluded.last_armed_at, \
            updated_at = excluded.updated_at
          """,
        arguments: [policyId, armedThrough, now])
    }
  }
}
