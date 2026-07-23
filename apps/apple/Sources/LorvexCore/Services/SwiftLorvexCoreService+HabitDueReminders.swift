import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// "Due habit reminders over a horizon" query over the pure-Swift core.
///
/// Loads each enabled `habit_reminder_policies` row with its habit's cadence,
/// target, and `habit_reminder_delivery_state.last_delivered_at`, then hands the set
/// to ``HabitReminderOccurrencePlanner`` — the shared expansion that walks the
/// rolling horizon and applies the scheduled-day / period-progress / future /
/// same-period-debounce filters across the horizon rather than at a single
/// "due now" tick. The only backend-specific work here is the SQL: the cadence
/// join, the period progress sum over a `[start, end]` day range, and the
/// delivery-state read.
///
/// Both functions take `deviceZone` rather than reading the DB-anchored
/// `PREF_TIMEZONE` value (unlike the other timezone-consuming call sites in
/// this core, which correctly use the synced, multi-master `PREF_TIMEZONE` for
/// cross-device day-boundary consistency). A habit reminder's fire moment is a
/// device-local alarm-clock concept, not shared data, so it is always
/// interpreted in the device's own current timezone.
extension SwiftLorvexCoreService {

  public func getDueHabitReminderOccurrences(
    now: Date, horizonDays: Int, deviceZone: TimeZone
  ) async throws -> [DueHabitReminderOccurrence] {
    try read { db in
      let zone = deviceZone
      let policyRows = try HabitReminderOps.listAllPolicies(db).filter(\.enabled)
      guard !policyRows.isEmpty, horizonDays > 0 else { return [] }

      var inputs: [HabitReminderOccurrencePlanner.PolicyInput] = []
      for row in policyRows {
        guard let habit = try Self.habitCadenceRow(db, id: row.habitId) else { continue }
        let cadence = try habit.cadence()
        let lastDelivered = try Self.lastDeliveredAt(db, policyId: row.id)
        inputs.append(
          HabitReminderOccurrencePlanner.PolicyInput(
            policy: SwiftLorvexHabitDeserializers.reminderPolicy(row),
            cadence: cadence,
            targetCount: habit.targetCount,
            lastDeliveredAt: lastDelivered))
      }

      // Cache the per-habit period sums keyed by (habit, range) so a multi-time
      // policy on the same day does not re-run the aggregate per slot.
      var progressCache: [String: Int64] = [:]
      return try HabitReminderOccurrencePlanner.plan(
        inputs: inputs, now: now, horizonDays: horizonDays, zone: zone
      ) { habitID, startDay, endDay in
        let key = "\(habitID)\u{1}\(startDay)\u{1}\(endDay)"
        if let cached = progressCache[key] { return cached }
        // A failed progress read must propagate, not silently read as 0 — a
        // zero would make an already-completed period look incomplete and fire
        // a false reminder.
        let sum = try Self.periodProgressSum(
          db, habitId: habitID, startDay: startDay, endDay: endDay)
        progressCache[key] = sum
        return sum
      }
    }
  }

  /// Stamp `last_delivered_at` for each enabled policy whose most recent
  /// armed in-period occurrence has already elapsed while the period is still
  /// below target — the deterministic device-local "the OS has shown this"
  /// stamp that activates the planner's same-period debounce. Run on the
  /// reschedule cadence BEFORE ``getDueHabitReminderOccurrences`` so the
  /// planner reads the fresh stamp. Writes to the local-only
  /// `habit_reminder_delivery_state` (not synced).
  ///
  /// The armed gate: a policy with no `last_armed_at` never had an OS request
  /// accepted (permission denied, budgeted out, add failed), so nothing was
  /// shown and nothing is recorded — its occurrences keep surfacing as due.
  /// When the armed stamp is older than the newest elapsed occurrence, the
  /// scan is clamped to the armed instant so only occurrences the OS actually
  /// held a request for can be recorded; a newer never-armed occurrence stays
  /// undebounced and due.
  public func reconcileDeliveredHabitReminders(asOf now: Date, deviceZone: TimeZone) async throws {
    try write { db in
      let zone = deviceZone
      let policyRows = try HabitReminderOps.listAllPolicies(db).filter(\.enabled)
      guard !policyRows.isEmpty else { return }
      let writeTs = SyncTimestampFormat.formatSyncTimestamp(now)
      var progressCache: [String: Int64] = [:]
      for row in policyRows {
        guard let armedThrough = try Self.lastArmedAt(db, policyId: row.id) else { continue }
        guard let habit = try Self.habitCadenceRow(db, id: row.habitId) else { continue }
        let cadence = try habit.cadence()
        let stored = try Self.lastDeliveredAt(db, policyId: row.id)
        let input = HabitReminderOccurrencePlanner.PolicyInput(
          policy: SwiftLorvexHabitDeserializers.reminderPolicy(row),
          cadence: cadence,
          targetCount: habit.targetCount,
          lastDeliveredAt: stored)
        let delivered = try HabitReminderOccurrencePlanner.mostRecentDeliveredOccurrence(
          input: input, now: min(now, armedThrough), zone: zone
        ) { habitID, startDay, endDay in
          let key = "\(habitID)\u{1}\(startDay)\u{1}\(endDay)"
          if let cached = progressCache[key] { return cached }
          let sum = try Self.periodProgressSum(
            db, habitId: habitID, startDay: startDay, endDay: endDay)
          progressCache[key] = sum
          return sum
        }
        guard let delivered else { continue }
        if let stored, delivered <= stored { continue }
        try HabitReminderOps.markHabitReminderDelivered(
          db, policyId: row.id, deliveredAt: SyncTimestampFormat.formatSyncTimestamp(delivered),
          now: writeTs)
      }
    }
  }

  /// A habit's cadence-relevant columns + `habit_weekdays` set. `nil` when the
  /// habit row is gone (a dangling policy whose habit was deleted out from under
  /// it).
  private struct HabitCadenceFields {
    let frequencyType: String
    let weekdays: [Int]
    let perPeriodTarget: Int64
    let dayOfMonth: Int?
    let targetCount: Int64

    func cadence() throws -> HabitCadence {
      try SwiftLorvexHabitDeserializers.cadence(
        frequencyType: frequencyType, weekdays: weekdays, perPeriodTarget: perPeriodTarget,
        dayOfMonth: dayOfMonth)
    }
  }

  private static func habitCadenceRow(_ db: Database, id: String) throws -> HabitCadenceFields? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: "SELECT frequency_type, per_period_target, day_of_month, target_count "
          + "FROM habits WHERE id = ?",
        arguments: [id])
    else { return nil }
    return HabitCadenceFields(
      frequencyType: row["frequency_type"],
      weekdays: try Self.loadHabitWeekdayInts(db, habitId: id),
      perPeriodTarget: row["per_period_target"] as Int64,
      dayOfMonth: (row["day_of_month"] as Int64?).map { Int($0) },
      targetCount: row["target_count"] as Int64)
  }

  /// Summed completion `value` for `habitId` over the inclusive `[startDay,
  /// endDay]` range via `COALESCE(SUM(value), 0)`, the period-progress sum for
  /// week/month buckets; for a daily period the range is a single day, so the
  /// same sum yields that day's value.
  private static func periodProgressSum(
    _ db: Database, habitId: String, startDay: String, endDay: String
  ) throws -> Int64 {
    try Int64.fetchOne(
      db,
      sql: """
        SELECT COALESCE(SUM(value), 0) FROM habit_completions
        WHERE habit_id = ? AND completed_date >= ? AND completed_date <= ?
        """,
      arguments: [habitId, startDay, endDay]) ?? 0
  }

  /// The `last_delivered_at` instant recorded for `policyId` in
  /// `habit_reminder_delivery_state`, or `nil` when no row exists or the stored
  /// value is unparseable (a fresh nudge is the safe failsafe).
  private static func lastDeliveredAt(_ db: Database, policyId: String) throws -> Date? {
    guard
      let raw = try String.fetchOne(
        db,
        sql: "SELECT last_delivered_at FROM habit_reminder_delivery_state WHERE policy_id = ?",
        arguments: [policyId])
    else { return nil }
    return SyncTimestamp.parse(raw)?.date
  }

  private static func lastArmedAt(_ db: Database, policyId: String) throws -> Date? {
    guard
      let raw = try String.fetchOne(
        db,
        sql: "SELECT last_armed_at FROM habit_reminder_delivery_state WHERE policy_id = ?",
        arguments: [policyId])
    else { return nil }
    return SyncTimestamp.parse(raw)?.date
  }

  /// Replace this device's armed-occurrence record; see
  /// ``LorvexHabitServicing/replaceArmedHabitReminders(armedThroughByPolicyID:asOf:)``.
  public func replaceArmedHabitReminders(
    armedThroughByPolicyID: [String: Date], asOf now: Date
  ) async throws {
    try write { db in
      try HabitReminderOps.replaceHabitRemindersArmed(
        db,
        armedThroughByPolicy: armedThroughByPolicyID.mapValues {
          SyncTimestampFormat.formatSyncTimestamp($0)
        },
        now: SyncTimestampFormat.formatSyncTimestamp(now))
    }
  }
}
