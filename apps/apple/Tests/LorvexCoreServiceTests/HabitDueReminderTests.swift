import Foundation
import LorvexStore
import Testing

@testable import LorvexCore

/// `getDueHabitReminderOccurrences` semantics against the real
/// `SwiftLorvexCoreService`. Mirrors the Tauri `reminders/tests.rs` cases
/// (scheduled vs unscheduled day, period met vs below target across cadences,
/// multi-time same day, past-time skip), but exercised over the rolling horizon
/// the Apple local scheduler consumes instead of a single "due now" tick.
///
/// Every call passes `deviceZone: utc` explicitly so the wall-clock fire
/// instants are deterministic regardless of the test machine's zone — habit
/// reminder fire times are device-zone-driven (an alarm-clock concept), never
/// the DB-anchored `PREF_TIMEZONE` value, so the injected `deviceZone` is what
/// controls determinism here, not the DB `timezone` preference. `seedUTC`
/// still pins the DB preference to UTC so these tests also incidentally cover
/// "DB zone == device zone"; ``deviceDivergesFromDbTimezone`` below is the one
/// that proves DB zone is NOT what drives the fire instant.
@Suite("Habit due reminder occurrences")
struct HabitDueReminderTests {
  private let utc = TimeZone(identifier: "UTC")!

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schema = try String(contentsOf: schemaURL, encoding: .utf8)
    let service = SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schema))
    return service
  }

  private func seedUTC(_ service: SwiftLorvexCoreService) async throws {
    _ = try await service.setPreference(key: "timezone", value: "\"UTC\"")
  }

  private func iso(_ raw: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: raw) ?? Date(timeIntervalSince1970: 0)
  }

  private func addPolicy(
    _ service: SwiftLorvexCoreService, habitID: String, habitName: String, time: String,
    enabled: Bool = true
  ) async throws {
    _ = try await service.upsertHabitReminderPolicy(
      id: habitID,
      policy: HabitReminderPolicy(
        id: "", habitID: habitID, habitName: habitName, reminderTime: time, enabled: enabled,
        createdAt: "", updatedAt: ""))
  }

  // MARK: - Future / past

  @Test("A daily habit's reminder schedules only future instants")
  func dailyFutureOnly() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(name: "Hydrate", cue: nil, targetCount: 1)
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "09:00")

    // now is 12:00 on 2026-03-29 (UTC). Today's 09:00 already passed.
    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-29T12:00:00Z"), horizonDays: 3, deviceZone: utc)

    #expect(!occurrences.isEmpty)
    #expect(occurrences.allSatisfy { $0.fireDate > iso("2026-03-29T12:00:00Z") })
    // No occurrence on the elapsed 2026-03-29 09:00; first is 2026-03-30 09:00.
    #expect(occurrences.contains { $0.fireDate == iso("2026-03-30T09:00:00Z") })
    #expect(!occurrences.contains { $0.fireDate == iso("2026-03-29T09:00:00Z") })
  }

  @Test("A reminder whose time is still ahead today fires today")
  func sameDayFutureFires() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(name: "Hydrate", cue: nil, targetCount: 1)
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "18:00")

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-29T12:00:00Z"), horizonDays: 1, deviceZone: utc)

    #expect(occurrences.contains { $0.fireDate == iso("2026-03-29T18:00:00Z") })
  }

  // MARK: - Cadence: scheduled vs unscheduled day

  @Test("A weekly Mon/Wed habit skips unscheduled days and fires on scheduled ones")
  func weeklyScheduledDays() async throws {
    let service = try makeService()
    try await seedUTC(service)
    // 2026-03-29 is a Sunday; 2026-03-30 Monday, 2026-04-01 Wednesday.
    let habit = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2]))
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "09:00")

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-29T06:00:00Z"), horizonDays: 7, deviceZone: utc)

    let fireDays = Set(occurrences.map { fireDayString($0.fireDate) })
    #expect(!fireDays.contains("2026-03-29"))  // Sunday — unscheduled
    #expect(fireDays.contains("2026-03-30"))  // Monday
    #expect(fireDays.contains("2026-04-01"))  // Wednesday
    #expect(!fireDays.contains("2026-03-31"))  // Tuesday — unscheduled
  }

  @Test("A monthly habit nudges only on its day-of-month, not every day")
  func monthlyFiresOnlyOnConfiguredDay() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(
      name: "Budget", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly", dayOfMonth: 1))
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "10:00")

    // now 2026-04-02 (April's day-1 reminder already elapsed); horizon spans into
    // May, so the only future fire is 2026-05-01. The old every-day behavior would
    // have flooded both months.
    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-04-02T08:00:00Z"), horizonDays: 45, deviceZone: utc)

    let fireDays = occurrences.map { fireDayString($0.fireDate) }
    #expect(fireDays == ["2026-05-01"])
  }

  // MARK: - Period met vs below target

  @Test("A daily reminder is suppressed once that day's target is met")
  func dailyTargetMetSuppressed() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 3,
      cadence: .daily)
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "18:00")
    // Meet tomorrow's target (3 of 3) before its 18:00 reminder.
    _ = try await service.adjustHabitCompletion(id: habit.id, date: "2026-03-30", delta: 3)

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-29T12:00:00Z"), horizonDays: 3, deviceZone: utc)

    let fireDays = Set(occurrences.map { fireDayString($0.fireDate) })
    #expect(!fireDays.contains("2026-03-30"))  // met → suppressed
    #expect(fireDays.contains("2026-03-31"))  // below target → fires
  }

  @Test("A daily reminder still fires while that day's count is below target")
  func dailyBelowTargetFires() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 3,
      cadence: .daily)
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "18:00")
    // 1 of 3 tomorrow — still below target.
    _ = try await service.adjustHabitCompletion(id: habit.id, date: "2026-03-30", delta: 1)

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-29T12:00:00Z"), horizonDays: 2, deviceZone: utc)

    #expect(occurrences.contains { fireDayString($0.fireDate) == "2026-03-30" })
  }

  @Test("A weekly habit's whole week is suppressed once the week's target is met")
  func weeklyTargetMetSuppressed() async throws {
    let service = try makeService()
    try await seedUTC(service)
    // Daily-scheduled weekly habit (no days → every day), target 1/week.
    let habit = try await service.createHabit(
      name: "Read", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly"))
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "18:00")
    // Complete once in the week of 2026-03-30..04-05 (Mon-Sun): meets target.
    _ = try await service.completeHabit(id: habit.id, date: "2026-03-31")

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-30T06:00:00Z"), horizonDays: 9, deviceZone: utc)

    let fireDays = Set(occurrences.map { fireDayString($0.fireDate) })
    // Every day in the met week (Mon 03-30 .. Sun 04-05) is suppressed.
    for day in ["2026-03-30", "2026-03-31", "2026-04-01", "2026-04-05"] {
      #expect(!fireDays.contains(day), "expected \(day) suppressed (week target met)")
    }
    // The next week (starting Mon 04-06) is below target again → fires.
    #expect(fireDays.contains("2026-04-06"))
  }

  @Test("A custom times_per_week habit fires while the week's count is below N")
  func customTimesPerWeekBelowTarget() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(
      name: "Run", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3))
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "18:00")
    // 2 of 3 completed this week → still below the required 3.
    _ = try await service.completeHabit(id: habit.id, date: "2026-03-30")
    _ = try await service.completeHabit(id: habit.id, date: "2026-03-31")

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-30T06:00:00Z"), horizonDays: 5, deviceZone: utc)
    #expect(occurrences.contains { fireDayString($0.fireDate) == "2026-04-01" })

    // A third completion meets the week → the rest of the week is suppressed.
    _ = try await service.completeHabit(id: habit.id, date: "2026-04-01")
    let after = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-30T06:00:00Z"), horizonDays: 5, deviceZone: utc)
    let afterDays = Set(after.map { fireDayString($0.fireDate) })
    #expect(!afterDays.contains("2026-04-02"))
  }

  @Test("A monthly habit's whole month is suppressed once the month's target is met")
  func monthlyTargetMetSuppressed() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(
      name: "Review", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly"))
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "18:00")
    _ = try await service.completeHabit(id: habit.id, date: "2026-03-15")

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-10T06:00:00Z"), horizonDays: 40, deviceZone: utc)
    let fireMonths = Set(occurrences.map { String(fireDayString($0.fireDate).prefix(7)) })
    #expect(!fireMonths.contains("2026-03"))  // March met → suppressed
    #expect(fireMonths.contains("2026-04"))  // April below target → fires
  }

  // MARK: - Multi-time same day

  @Test("Several reminder times on one habit each get their own occurrence")
  func multipleTimesSameDay() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(name: "Pills", cue: nil, targetCount: 2)
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "08:00")
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "20:00")

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-29T06:00:00Z"), horizonDays: 1, deviceZone: utc)

    #expect(occurrences.contains { $0.fireDate == iso("2026-03-29T08:00:00Z") })
    #expect(occurrences.contains { $0.fireDate == iso("2026-03-29T20:00:00Z") })
    #expect(occurrences.count == 2)
  }

  @Test("Multi-time slots self-silence once the day's accumulative target is met")
  func multipleTimesSilenceWhenMet() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(name: "Pills", cue: nil, targetCount: 2)
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "08:00")
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "20:00")
    // Meet today's target of 2 before either reminder.
    _ = try await service.adjustHabitCompletion(id: habit.id, date: "2026-03-29", delta: 2)

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-29T06:00:00Z"), horizonDays: 1, deviceZone: utc)

    #expect(occurrences.isEmpty)
  }

  // MARK: - Enabled / debounce

  @Test("A disabled policy contributes no occurrences")
  func disabledPolicySkipped() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(name: "Stretch", cue: nil, targetCount: 1)
    try await addPolicy(
      service, habitID: habit.id, habitName: habit.name, time: "09:00", enabled: false)

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: iso("2026-03-29T06:00:00Z"), horizonDays: 3, deviceZone: utc)
    #expect(occurrences.isEmpty)
  }

  // MARK: - Device zone vs DB-anchored zone

  /// The regression tripwire for the bug this file was updated to fix: a habit
  /// reminder's fire instant must be driven by the injected `deviceZone`, never
  /// by the DB-anchored `PREF_TIMEZONE` value that `WorkflowTimezone
  /// .anchoredTimezoneName` reads for the OTHER (cross-device, day-boundary)
  /// call sites. The DB preference here is deliberately pinned to
  /// America/New_York while `deviceZone` is America/Los_Angeles — a habit
  /// "08:00 daily" must fire at 08:00 PT (15:00Z), NOT at 08:00 ET reinterpreted
  /// (which would be 12:00Z). Asserting BOTH the correct instant and the
  /// explicit non-match against the old (buggy) DB-anchored instant means a
  /// regression back to reading `anchoredTimezoneName` for this purpose fails
  /// this test, since 2026-03-29 is after the US DST changeover (2026-03-08),
  /// so PT and ET differ by exactly 7 hours (PDT = UTC-7, EDT = UTC-4).
  @Test("A habit reminder fires in the device zone, not the DB-anchored zone")
  func deviceZoneDrivesFireInstantNotDbAnchoredZone() async throws {
    let service = try makeService()
    _ = try await service.setPreference(
      key: "timezone", value: "\"America/New_York\"")
    let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    let habit = try await service.createHabit(name: "Meditate", cue: nil, targetCount: 1)
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "08:00")

    // 08:00Z on 2026-03-29 is 01:00 PDT on 2026-03-29 in Los Angeles — already
    // into 2026-03-29's local calendar day there (LA is UTC-7), and well before
    // that day's 08:00 PT (15:00Z) fire, so the horizon's day-0 occurrence is
    // the one under test. (00:00Z would still read as LA's PREVIOUS day,
    // 2026-03-28, whose 08:00 PT fire has already elapsed — that would
    // spuriously miss the occurrence entirely rather than testing the zone.)
    let now = iso("2026-03-29T08:00:00Z")
    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: now, horizonDays: 1, deviceZone: losAngeles)

    let expectedDeviceZoneFire = iso("2026-03-29T15:00:00Z")  // 08:00 PDT (UTC-7)
    let wrongDbAnchoredFire = iso("2026-03-29T12:00:00Z")  // 08:00 EDT (UTC-4) — the bug
    #expect(occurrences.contains { $0.fireDate == expectedDeviceZoneFire })
    #expect(!occurrences.contains { $0.fireDate == wrongDbAnchoredFire })
  }

  /// `reconcileDeliveredHabitReminders` and `getDueHabitReminderOccurrences` must
  /// agree on what day it is under the SAME injected `deviceZone`, or the
  /// same-period debounce disagrees with the occurrence planner about which
  /// period is "already delivered." A DAILY habit can't exercise this: its
  /// period is a single day, so an occurrence is either already-elapsed
  /// (reconcile's candidate) or still-future (plan's candidate) but never
  /// both, so the debounce is never actually reached. A WEEKLY (daily-
  /// scheduled, target 1/week) habit's period spans the whole Mon–Sun week, so
  /// one elapsed same-week day can debounce a LATER same-week day that is
  /// still future — that's the real mechanism under test.
  ///
  /// Uses a DB-anchored zone (New York) that diverges from the device zone
  /// (Los Angeles) so this also proves the debounce is device-zone-driven,
  /// not DB-zone-driven: `now` is Tuesday 2026-03-31 03:00 PT — Monday's
  /// 08:00 PT fire (2026-03-30T15:00:00Z) has already elapsed, Tuesday's
  /// (2026-03-31T15:00:00Z) has not. Before reconciling, Tuesday's occurrence
  /// is due (progress 0 < target 1). After reconciling (which stamps
  /// Monday's elapsed fire), the WHOLE current week — including Tuesday — is
  /// debounced, while the NEXT week (starting Mon 2026-04-06) still fires.
  /// Commenting out the `reconcileDeliveredHabitReminders` call makes the "after"
  /// assertions fail, proving the debounce is load-bearing here (unlike the
  /// daily case).
  @Test("The debounce stays consistent between reconcile and plan under the device zone")
  func debounceConsistentAcrossReconcileAndPlanUnderDeviceZone() async throws {
    let service = try makeService()
    _ = try await service.setPreference(
      key: "timezone", value: "\"America/New_York\"")
    let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    // Daily-scheduled weekly habit (no `days` → every day), target 1/week, no
    // completions recorded — the week is below target throughout this test.
    let habit = try await service.createHabit(
      name: "Read", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly"))
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "08:00")

    let now = iso("2026-03-31T10:00:00Z")  // 03:00 PDT on 2026-03-31 (Tuesday)

    let before = try await service.getDueHabitReminderOccurrences(
      now: now, horizonDays: 10, deviceZone: losAngeles)
    let beforeDays = Set(before.map { fireDayString($0.fireDate) })
    #expect(beforeDays.contains("2026-03-31"))  // Tuesday: still due, below target

    // The delivered reconciler is gated on the armed record: arm the policy
    // through `now` (covering Monday's elapsed fire) the way the notification
    // scheduling pass does after the OS accepts the requests.
    let policyID = try await service.getHabitReminderPolicies(id: habit.id)[0].id
    try await service.replaceArmedHabitReminders(
      armedThroughByPolicyID: [policyID: now], asOf: now)
    try await service.reconcileDeliveredHabitReminders(asOf: now, deviceZone: losAngeles)

    let after = try await service.getDueHabitReminderOccurrences(
      now: now, horizonDays: 10, deviceZone: losAngeles)
    let afterDays = Set(after.map { fireDayString($0.fireDate) })
    // The whole current week (containing the just-reconciled Monday fire),
    // including Tuesday, is now debounced out...
    for day in ["2026-03-31", "2026-04-01", "2026-04-02", "2026-04-05"] {
      #expect(!afterDays.contains(day), "expected \(day) debounced (same week as reconciled fire)")
    }
    // ...but the NEXT week (starting Mon 2026-04-06) is unaffected.
    #expect(afterDays.contains("2026-04-06"))
  }

  /// N1 regression: reconcile is gated on the armed record. A policy whose
  /// notification requests were never accepted by the OS (permission denied,
  /// budgeted out, add failed — so no `last_armed_at`) records no delivery
  /// when its fire time elapses: nothing was shown, so the same-period
  /// debounce must not activate and the occurrence keeps surfacing as due.
  @Test("An elapsed but never-armed occurrence is not recorded as delivered")
  func neverArmedOccurrenceStaysDue() async throws {
    let service = try makeService()
    try await seedUTC(service)
    // Daily-scheduled weekly habit, target 1/week: Monday's elapsed fire
    // would debounce the whole week — exactly the silent-swallow shape.
    let habit = try await service.createHabit(
      name: "Read", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly"))
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "08:00")

    // Tuesday 06:00: Monday 08:00 elapsed, Tuesday 08:00 still future.
    let now = iso("2026-03-31T06:00:00Z")
    try await service.reconcileDeliveredHabitReminders(asOf: now, deviceZone: utc)

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: now, horizonDays: 3, deviceZone: utc)
    let days = Set(occurrences.map { fireDayString($0.fireDate) })
    #expect(days.contains("2026-03-31"))  // no phantom delivery, still due
  }

  /// The reconcile scan is clamped to the armed instant: with requests armed
  /// only through LAST week, this week's elapsed (but never-armed, never
  /// shown) fires record nothing, so the current week stays due while last
  /// week's genuinely shown fire is debounced within its own period.
  @Test("Delivered recording is clamped to the armed instant")
  func deliveredRecordingClampedToArmedInstant() async throws {
    let service = try makeService()
    try await seedUTC(service)
    let habit = try await service.createHabit(
      name: "Read", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly"))
    try await addPolicy(service, habitID: habit.id, habitName: habit.name, time: "08:00")
    let policyID = try await service.getHabitReminderPolicies(id: habit.id)[0].id

    // Armed through Friday of LAST week (2026-03-27); the device then never
    // re-armed (e.g. notifications were revoked before the weekly replace).
    let armedThrough = iso("2026-03-27T08:00:00Z")
    try await service.replaceArmedHabitReminders(
      armedThroughByPolicyID: [policyID: armedThrough], asOf: armedThrough)

    // Wednesday of the CURRENT week: Mon/Tue/Wed fires elapsed but none were
    // armed. Without the clamp, Wednesday's elapse would debounce the whole
    // current week.
    let now = iso("2026-04-01T10:00:00Z")
    try await service.reconcileDeliveredHabitReminders(asOf: now, deviceZone: utc)

    let occurrences = try await service.getDueHabitReminderOccurrences(
      now: now, horizonDays: 4, deviceZone: utc)
    let days = Set(occurrences.map { fireDayString($0.fireDate) })
    #expect(days.contains("2026-04-02"))  // current week still due
  }

  // MARK: - Helpers

  private func fireDayString(_ date: Date) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let c = cal.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }
}
