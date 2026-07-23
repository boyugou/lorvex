import Foundation
import LorvexDomain

public protocol LorvexHabitServicing: Sendable {
  func loadHabits(date: String) async throws -> HabitCatalogSnapshot

  /// The archived habits (hidden from `loadHabits`), for the restore surface.
  /// Defaults to empty so non-storage backends need not implement it.
  func loadArchivedHabits(date: String) async throws -> HabitCatalogSnapshot

  /// Create a habit. `cadence` carries the typed rhythm + detail
  /// (`frequency_type` ∈ {daily, weekly, monthly, times_per_week}, weekday set,
  /// per-week count, day-of-month). `targetCount` is the per-day accumulative
  /// goal, fully decoupled from the cadence. `milestoneTarget`, when non-nil, is
  /// the user-set milestone goal (must be positive); nil leaves it unset.
  func createHabit(
    name: String, cue: String?, icon: String?, color: String?, targetCount: Int,
    cadence: HabitCadenceInput, milestoneTarget: Int?
  ) async throws -> LorvexHabit

  /// Create a habit and its initial reminder slots as one canonical mutation.
  /// Storage-backed implementations must commit the parent row, every reminder
  /// row, their changelog entries, and their sync envelopes atomically.
  func createHabit(
    name: String, cue: String?, icon: String?, color: String?, targetCount: Int,
    cadence: HabitCadenceInput, milestoneTarget: Int?, reminderTimes: [String]
  ) async throws -> LorvexHabit

  /// Id-preserving idempotent upsert for data import/restore. Inserts the habit
  /// at the supplied `id`, or overwrites the existing row when that id is already
  /// present. No version gate: an import always wins, so re-importing the same
  /// payload overwrites in place rather than duplicating. The full cadence
  /// round-trips: `frequencyType` (`daily` / `weekly` / `monthly` /
  /// `times_per_week`) plus `weekdays` (Monday-first 0=Mon … 6=Sun),
  /// `perPeriodTarget`, and `dayOfMonth`. Appearance, archived state, and
  /// synced display order are preserved by newer exports. `milestoneTarget` is
  /// set only when supplied (non-nil): on an id conflict a nil leaves any
  /// existing value in place, so a milestone that arrived via sync is never
  /// clobbered by a milestone-less re-import.
  func importHabit(
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
  ) async throws -> LorvexHabit

  func completeHabit(id: LorvexHabit.ID, date: String) async throws -> HabitCatalogSnapshot

  func uncompleteHabit(id: LorvexHabit.ID, date: String) async throws -> HabitCatalogSnapshot

  /// Adjust a habit's completion `value` for `date` by `delta`, clamped to
  /// `[0, target_count]`. `delta == 0` toggles the day (a met day clears to 0, an
  /// unmet day jumps straight to `target_count`); a non-zero delta is a relative
  /// bump. This gives accumulative habits (target_count > 1) a true per-step
  /// decrement that `completeHabit` (+1 only) and `uncompleteHabit` (clear to 0)
  /// cannot express. Returns a fresh catalog snapshot.
  func adjustHabitCompletion(id: LorvexHabit.ID, date: String, delta: Int) async throws
    -> HabitCatalogSnapshot

  /// Update a habit. `cadence` nil = leave the cadence unchanged; a non-nil
  /// value replaces the whole cadence atomically (interpreted as in
  /// `createHabit`). `milestoneTarget` is a three-state patch: `.unset` leaves
  /// the milestone goal untouched, `.clear` removes it (SQL NULL), and
  /// `.set(value)` sets it (value must be positive).
  func updateHabit(
    id: LorvexHabit.ID,
    name: String?,
    cue: String?,
    color: String?,
    icon: String?,
    targetCount: Int?,
    archived: Bool?,
    cadence: HabitCadenceInput?,
    milestoneTarget: Patch<Int>
  ) async throws -> LorvexHabit

  func deleteHabit(id: LorvexHabit.ID) async throws -> HabitCatalogSnapshot

  /// Return completion records for a habit, newest first, bounded by `limit`.
  /// The caller requests `limit` rows; to detect truncation without a separate
  /// count query it may request one extra row (`limit + 1`) and compare the
  /// returned count against its intended page size.
  func getHabitCompletions(id: LorvexHabit.ID, from: String?, to: String?, limit: Int) async throws
    -> HabitCompletionsSnapshot

  func getHabitStats(id: LorvexHabit.ID) async throws -> HabitStats

  func batchCompleteHabits(ids: [LorvexHabit.ID], date: String) async throws -> HabitCatalogSnapshot

  func getHabitReminderPolicies(id: LorvexHabit.ID) async throws -> [HabitReminderPolicy]

  /// Every stored reminder policy across all habits — the read the local
  /// notification scheduler re-plans from after each mutation.
  func getAllHabitReminderPolicies() async throws -> [HabitReminderPolicy]

  /// Concrete habit-reminder firings the user should actually be nudged with,
  /// over the next `horizonDays` days starting from `now`, with each policy's
  /// stored `HH:MM` interpreted in `deviceZone`.
  ///
  /// For each enabled policy with a valid `HH:MM`, walks the horizon day by day
  /// and emits one occurrence per day where the habit is scheduled on that day
  /// (its cadence includes it), that day's period progress is still below the
  /// required count, and the resolved fire instant is strictly after `now`. A
  /// multi-time-per-day habit yields one occurrence per reminder time, each
  /// gated by the same shared "this period's count < target" test, so the slots
  /// self-silence once the target is met. The due-and-progress rules (whether
  /// the habit is scheduled on a day, its required completions per period, and
  /// the daily / week-bucket / monthly progress buckets) run over a forward
  /// horizon rather than a single "due now" instant, so the local scheduler can
  /// place one-shot notifications. Periods already delivered (per
  /// `habit_reminder_delivery_state`) are suppressed.
  ///
  /// `deviceZone` is deliberately NOT the DB-anchored `PREF_TIMEZONE` value —
  /// a habit reminder is a device-local alarm-clock concept ("ring at 8am on
  /// THIS device"), not shared cross-device data, so it is always the live
  /// timezone of the device doing the scheduling. Callers should not override
  /// the default except in tests that need a deterministic zone.
  func getDueHabitReminderOccurrences(
    now: Date, horizonDays: Int, deviceZone: TimeZone
  ) async throws -> [DueHabitReminderOccurrence]

  /// Stamp `last_delivered_at` for each enabled policy whose most recent
  /// armed in-period occurrence has already elapsed while the period is still
  /// below target, so ``getDueHabitReminderOccurrences`` debounces same-period
  /// re-nudges. The deterministic device-local analog of an OS delivery
  /// callback; run on the reschedule cadence BEFORE
  /// ``getDueHabitReminderOccurrences``.
  ///
  /// Gated on the armed record maintained by
  /// ``replaceArmedHabitReminders(armedThroughByPolicyID:asOf:)``: only
  /// occurrences at or before the policy's `last_armed_at` are considered —
  /// an occurrence whose OS request was never accepted (permission denied,
  /// budgeted out, add failed) was never shown, stays undebounced, and keeps
  /// surfacing as due.
  ///
  /// `deviceZone` must match the zone passed to
  /// ``getDueHabitReminderOccurrences`` on the same reschedule pass — both
  /// functions must agree on what day it is device-locally, or the debounce
  /// they share will disagree with the occurrence planner.
  func reconcileDeliveredHabitReminders(asOf: Date, deviceZone: TimeZone) async throws

  /// Replace this device's armed-occurrence record with exactly the
  /// occurrences the habit notification scheduler reported as accepted on
  /// this replace pass. `armedThroughByPolicyID` maps a policy id to the
  /// latest accepted occurrence fire time (per policy the armed set is its
  /// contiguous earliest prefix, so one instant fully describes it); every
  /// policy absent from the map has its armed stamp cleared, because the
  /// replace pass just dropped its OS requests. The stamp therefore mirrors
  /// the currently pending `UNUserNotificationCenter` request set, and
  /// ``reconcileDeliveredHabitReminders(asOf:deviceZone:)`` only records
  /// deliveries covered by it.
  func replaceArmedHabitReminders(
    armedThroughByPolicyID: [String: Date], asOf: Date
  ) async throws

  func upsertHabitReminderPolicy(id: LorvexHabit.ID, policy: HabitReminderPolicy) async throws
    -> HabitReminderPolicy

  /// Delete one reminder policy by its id. Returns the removed policy, or
  /// nil when no such policy existed (idempotent).
  func deleteHabitReminderPolicy(policyID: String) async throws -> HabitReminderPolicy?

  /// Persist the manual display order of the active habits board. `orderedIDs`
  /// is the full desired order of active habit ids; each listed habit's synced
  /// `position` is rewritten to its index, so a reorder on one device converges
  /// across peers as an ordinary last-writer-wins field. Ids absent from
  /// `orderedIDs` are left untouched. Returns the refreshed active catalog
  /// projected for `date`.
  func reorderHabits(orderedIDs: [LorvexHabit.ID], date: String) async throws
    -> HabitCatalogSnapshot
}

extension LorvexHabitServicing {
  /// Compatibility default for simple/test backends. Non-empty reminders require
  /// an implementation that can honor the protocol's atomicity contract.
  public func createHabit(
    name: String, cue: String?, icon: String?, color: String?, targetCount: Int,
    cadence: HabitCadenceInput, milestoneTarget: Int?, reminderTimes: [String]
  ) async throws -> LorvexHabit {
    guard reminderTimes.isEmpty else {
      throw LorvexCoreError.unsupportedOperation(
        "This storage backend cannot create a habit and reminders atomically.")
    }
    return try await createHabit(
      name: name, cue: cue, icon: icon, color: color, targetCount: targetCount,
      cadence: cadence, milestoneTarget: milestoneTarget)
  }

  /// Default: no archived habits. Storage-backed services override this.
  public func loadArchivedHabits(date: String) async throws -> HabitCatalogSnapshot {
    HabitCatalogSnapshot(habits: [])
  }

  /// Convenience for callers that set a cadence but no milestone goal.
  public func createHabit(
    name: String, cue: String?, icon: String?, color: String?, targetCount: Int,
    cadence: HabitCadenceInput
  ) async throws -> LorvexHabit {
    try await createHabit(
      name: name, cue: cue, icon: icon, color: color, targetCount: targetCount,
      cadence: cadence, milestoneTarget: nil)
  }

  /// Convenience for callers that create a plain daily habit without an explicit
  /// cadence.
  public func createHabit(
    name: String, cue: String?, icon: String?, color: String?, targetCount: Int
  ) async throws -> LorvexHabit {
    try await createHabit(
      name: name, cue: cue, icon: icon, color: color, targetCount: targetCount,
      cadence: .daily, milestoneTarget: nil)
  }

  /// Convenience for callers that don't set appearance: creates with the
  /// default icon and auto color, daily cadence.
  public func createHabit(name: String, cue: String?, targetCount: Int) async throws -> LorvexHabit
  {
    try await createHabit(
      name: name, cue: cue, icon: nil, color: nil, targetCount: targetCount,
      cadence: .daily, milestoneTarget: nil)
  }

  /// Convenience for production call sites: habit-reminder fire times are
  /// always interpreted in the device's live current timezone, so real
  /// callers never need to pass `deviceZone` explicitly. Only tests that need
  /// a deterministic zone should call the full form directly.
  public func getDueHabitReminderOccurrences(
    now: Date, horizonDays: Int
  ) async throws -> [DueHabitReminderOccurrence] {
    try await getDueHabitReminderOccurrences(
      now: now, horizonDays: horizonDays, deviceZone: TimeZone.current)
  }

  /// Convenience for production call sites: same device-zone default as the
  /// `getDueHabitReminderOccurrences(now:horizonDays:)` overload above.
  public func reconcileDeliveredHabitReminders(asOf now: Date) async throws {
    try await reconcileDeliveredHabitReminders(asOf: now, deviceZone: TimeZone.current)
  }

  /// Convenience for callers that set a cadence but leave the milestone goal
  /// untouched.
  public func updateHabit(
    id: LorvexHabit.ID, name: String?, cue: String?, color: String?, icon: String?,
    targetCount: Int?, archived: Bool?, cadence: HabitCadenceInput?
  ) async throws -> LorvexHabit {
    try await updateHabit(
      id: id, name: name, cue: cue, color: color, icon: icon, targetCount: targetCount,
      archived: archived, cadence: cadence, milestoneTarget: .unset)
  }

  /// Convenience for import callers that carry no milestone goal.
  public func importHabit(
    id: LorvexHabit.ID, name: String, cue: String?, frequencyType: String, weekdays: [Int],
    perPeriodTarget: Int?, dayOfMonth: Int?, targetCount: Int
  ) async throws -> LorvexHabit {
    try await importHabit(
      id: id, name: name, icon: nil, color: nil, cue: cue, frequencyType: frequencyType,
      weekdays: weekdays,
      perPeriodTarget: perPeriodTarget, dayOfMonth: dayOfMonth, targetCount: targetCount,
      milestoneTarget: nil, archived: false, position: 0)
  }

  /// Convenience for callers that carry no appearance, archive state, or
  /// explicit display order.
  public func importHabit(
    id: LorvexHabit.ID, name: String, cue: String?, frequencyType: String, weekdays: [Int],
    perPeriodTarget: Int?, dayOfMonth: Int?, targetCount: Int, milestoneTarget: Int?
  ) async throws -> LorvexHabit {
    try await importHabit(
      id: id, name: name, icon: nil, color: nil, cue: cue, frequencyType: frequencyType,
      weekdays: weekdays,
      perPeriodTarget: perPeriodTarget, dayOfMonth: dayOfMonth, targetCount: targetCount,
      milestoneTarget: milestoneTarget, archived: false, position: 0)
  }

  /// Convenience for callers that don't change the cadence.
  public func updateHabit(
    id: LorvexHabit.ID, name: String?, cue: String?, color: String?, icon: String?,
    targetCount: Int?, archived: Bool?
  ) async throws -> LorvexHabit {
    try await updateHabit(
      id: id, name: name, cue: cue, color: color, icon: icon, targetCount: targetCount,
      archived: archived, cadence: nil, milestoneTarget: .unset)
  }

  /// Convenience for callers that don't change the archived flag or cadence.
  public func updateHabit(
    id: LorvexHabit.ID, name: String?, cue: String?, color: String?, icon: String?,
    targetCount: Int?
  ) async throws -> LorvexHabit {
    try await updateHabit(
      id: id, name: name, cue: cue, color: color, icon: icon, targetCount: targetCount,
      archived: nil, cadence: nil, milestoneTarget: .unset)
  }
}
