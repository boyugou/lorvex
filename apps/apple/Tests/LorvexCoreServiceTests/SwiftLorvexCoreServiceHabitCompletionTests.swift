import GRDB
import LorvexStore
import XCTest

@testable import LorvexCore

/// Date-validation coverage for habit completion on `SwiftLorvexCoreService`.
/// A non-canonical completion date must be rejected at the service funnel so
/// every surface (app, MCP, CLI) shares the guard, rather than landing a
/// malformed key that miscounts streaks and coexists with the canonical row.
final class SwiftLorvexCoreServiceHabitCompletionTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func mutationCounts(_ service: SwiftLorvexCoreService) throws
    -> (outbox: Int64, changelog: Int64)
  {
    try service.read { db in
      let outbox = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? 0
      let changelog = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
      return (outbox, changelog)
    }
  }

  /// Today's `YYYY-MM-DD` in the current timezone — the same day the service
  /// computes via `WorkflowTimezone.todayYmdForConn` when no `timezone`
  /// preference is set (it falls back to `TimeZone.current`).
  private func todayYmd() -> String { ymdOffsetFromToday(byDays: 0) }

  /// `YYYY-MM-DD` for a calendar-day offset from today in `TimeZone.current`,
  /// matching the timezone the service resolves `today` in.
  private func ymdOffsetFromToday(byDays days: Int) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let shifted = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: shifted)
  }

  /// A canonical RFC 3339 UTC sync timestamp `days` days before now, for
  /// backdating a habit's `created_at`. The instant is `now - days` at the same
  /// wall-clock time in `TimeZone.current`, so it resolves back to
  /// `ymdOffsetFromToday(byDays: -days)` as the habit's creation day.
  private func utcTimestamp(daysAgo days: Int) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let shifted = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return f.string(from: shifted)
  }

  /// `update_habit`'s rich return must report the real `completionsToday`. The
  /// snapshot is built by `mapHabitRow`, whose `date` argument keys
  /// `habit_completions.completed_date` (a YMD). Passing the full `updated_at`
  /// timestamp there matched no completion row, so an edited habit wrongly came
  /// back with `completionsToday: 0` even after a same-day completion.
  func testUpdateHabitReturnsRealCompletionsToday() async throws {
    let service = try makeService()
    let today = todayYmd()
    let habit = try await service.createHabit(
      name: "Stretch", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily)
    XCTAssertEqual(habit.completionsToday, 0)

    _ = try await service.completeHabit(id: habit.id, date: today)

    let updated = try await service.updateHabit(
      id: habit.id, name: "Stretch (edited)", cue: nil, color: nil, icon: nil,
      targetCount: nil, archived: nil, cadence: nil)
    XCTAssertEqual(updated.name, "Stretch (edited)")
    XCTAssertEqual(
      updated.completionsToday, 1,
      "an edited habit must keep the same-day completion in its rich return")

    // The authoritative stats reader agrees — the return value is not a fluke.
    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(stats.completionsToday, 1)
  }

  func testHabitCompletionRejectsNonCanonicalDates() async throws {
    let service = try makeService()
    for bad in ["2026-6-9", "June 9", "2026/06/09", "2026-13-01", "20260609", ""] {
      var completeThrew = false
      do { _ = try await service.completeHabit(id: "missing", date: bad) } catch { completeThrew = true }
      XCTAssertTrue(completeThrew, "completeHabit should reject \(bad)")

      var batchThrew = false
      do { _ = try await service.batchCompleteHabits(ids: ["missing"], date: bad) } catch { batchThrew = true }
      XCTAssertTrue(batchThrew, "batchCompleteHabits should reject \(bad)")
    }
  }

  /// An unknown habit id in a batch is skipped, not written, and never poisons
  /// the valid habits sharing the transaction. `habit_completions.habit_id`
  /// carries a foreign key onto `habits(id)`, so the pre-guard fallthrough would
  /// have raised an FK violation and rolled back the whole batch. Skip-and-report
  /// matches `batchCompleteTasks` / `batchCancelTasks`: the unknown id is simply
  /// absent from the returned snapshot (the MCP adapter reports it as
  /// `not found`), while the real habit still records its completion.
  func testBatchCompleteHabitsSkipsUnknownIdsWithoutPoisoningTheBatch() async throws {
    let service = try makeService()
    let date = "2026-06-20"
    let real = try await service.createHabit(
      name: "Real habit", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily)

    let snapshot = try await service.batchCompleteHabits(
      ids: [real.id, "does-not-exist", "also-missing"], date: date)

    // The valid habit completed; the unknown ids are absent (skip-and-report).
    let completedReal = try XCTUnwrap(snapshot.habits.first { $0.id == real.id })
    XCTAssertEqual(completedReal.completionsToday, 1)
    XCTAssertFalse(snapshot.habits.contains { $0.id == "does-not-exist" })
    XCTAssertFalse(snapshot.habits.contains { $0.id == "also-missing" })

    // The real habit's completion, sync outbox, and changelog rows all landed —
    // proof the unknown ids did not roll the transaction back.
    let counts = try mutationCounts(service)
    XCTAssertGreaterThan(counts.outbox, 0)
    XCTAssertGreaterThan(counts.changelog, 0)
    let value = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT value FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
        arguments: [real.id, date])
    }
    XCTAssertEqual(value, 1)

    // No orphan completion row was written for a non-existent habit.
    let orphanCount = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM habit_completions WHERE habit_id = ?",
        arguments: ["does-not-exist"]) ?? 0
    }
    XCTAssertEqual(orphanCount, 0)
  }

  func testAdjustHabitCompletionIncrementsDecrementsTogglesAndClamps() async throws {
    let service = try makeService()
    let date = "2026-06-15"
    let habit = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 3,
      cadence: .daily)

    func today() async throws -> Int {
      let snapshot = try await service.loadHabits(date: date)
      return try XCTUnwrap(snapshot.habits.first { $0.id == habit.id }).completionsToday
    }

    // +1 twice → 2.
    _ = try await service.adjustHabitCompletion(id: habit.id, date: date, delta: 1)
    _ = try await service.adjustHabitCompletion(id: habit.id, date: date, delta: 1)
    var value = try await today()
    XCTAssertEqual(value, 2)
    var snapshot = try await service.loadHabits(date: date)
    XCTAssertEqual(snapshot.habits.first { $0.id == habit.id }?.totalCompletions, 2)
    var stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(stats.totalCompletions, 2)

    // −1 → 1: a true per-step decrement, not a full wipe.
    _ = try await service.adjustHabitCompletion(id: habit.id, date: date, delta: -1)
    value = try await today()
    XCTAssertEqual(value, 1)

    // Increment clamps at target_count.
    for _ in 0..<5 {
      _ = try await service.adjustHabitCompletion(id: habit.id, date: date, delta: 1)
    }
    value = try await today()
    XCTAssertEqual(value, 3)
    snapshot = try await service.loadHabits(date: date)
    XCTAssertEqual(snapshot.habits.first { $0.id == habit.id }?.totalCompletions, 3)
    stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(stats.totalCompletions, 3)

    // Toggle (delta 0) on a met day clears to 0.
    _ = try await service.adjustHabitCompletion(id: habit.id, date: date, delta: 0)
    value = try await today()
    XCTAssertEqual(value, 0)

    // Toggle on an unmet day jumps straight to target_count.
    _ = try await service.adjustHabitCompletion(id: habit.id, date: date, delta: 0)
    value = try await today()
    XCTAssertEqual(value, 3)

    // Decrement clamps at 0 (and drops the row at zero without underflowing).
    for _ in 0..<5 {
      _ = try await service.adjustHabitCompletion(id: habit.id, date: date, delta: -1)
    }
    value = try await today()
    XCTAssertEqual(value, 0)
  }

  func testHabitCompleteAtTargetNoOpDoesNotWriteSyncOrChangelog() async throws {
    let service = try makeService()
    let date = "2026-06-16"
    let habit = try await service.createHabit(
      name: "Binary habit", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily)
    _ = try await service.completeHabit(id: habit.id, date: date)
    let beforeSingle = try mutationCounts(service)

    _ = try await service.completeHabit(id: habit.id, date: date)
    let afterSingle = try mutationCounts(service)

    XCTAssertEqual(afterSingle.outbox, beforeSingle.outbox)
    XCTAssertEqual(afterSingle.changelog, beforeSingle.changelog)

    let other = try await service.createHabit(
      name: "Batch binary habit", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily)
    _ = try await service.batchCompleteHabits(ids: [other.id], date: date)
    let beforeBatch = try mutationCounts(service)

    _ = try await service.batchCompleteHabits(ids: [other.id], date: date)
    let afterBatch = try mutationCounts(service)

    XCTAssertEqual(afterBatch.outbox, beforeBatch.outbox)
    XCTAssertEqual(afterBatch.changelog, beforeBatch.changelog)
  }

  /// A weekly-bucket streak must clear the habit's full per-week quota, not the
  /// per-day `target_count`. "Gym 3×/week" (per_period_target=3, target_count=1)
  /// completed once a week satisfies only 1 of the 3 required completions per ISO
  /// week, so no week counts and the streak stays 0. Feeding the raw
  /// `target_count` (1) into the week bucket wrongly credited one met week per
  /// completion, reporting a 5-week streak for five isolated completions.
  func testTimesPerWeekStreakRequiresFullWeeklyQuota() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3),
      milestoneTarget: nil)

    // One completion in each of five consecutive ISO weeks (this week plus the
    // four prior). Dates exactly 7 days apart always land in adjacent weeks.
    for weeksBack in 0..<5 {
      _ = try await service.completeHabit(
        id: habit.id, date: ymdOffsetFromToday(byDays: -7 * weeksBack))
    }

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      stats.currentStreak, 0,
      "one of three required weekly completions never satisfies a 3×/week week")
    XCTAssertEqual(
      stats.bestStreak, 0,
      "no week reached the 3×/week quota, so the longest streak is also 0")
  }

  func testStreakRequiresDailyTargetAndIgnoresFutureCompletions() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 2,
      cadence: .daily)

    _ = try await service.completeHabit(id: habit.id, date: todayYmd())
    _ = try await service.completeHabit(id: habit.id, date: ymdOffsetFromToday(byDays: 1))

    var stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(stats.currentStreak, 0, "a partial day does not count as a met day")
    XCTAssertEqual(stats.bestStreak, 0, "a future row cannot create a historical streak")
    XCTAssertFalse(stats.recentCompletions.contains(ymdOffsetFromToday(byDays: 1)))

    _ = try await service.completeHabit(id: habit.id, date: todayYmd())
    stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(stats.currentStreak, 1, "reaching target_count makes today a met day")
    XCTAssertEqual(stats.bestStreak, 1)
  }

  func testHabitVisualizationHistoryCoversSixWholeCalendarMonths() {
    XCTAssertEqual(
      SwiftLorvexCoreService.habitVisualizationHistoryCutoff(today: "2026-08-31"),
      "2026-03-01")
    XCTAssertEqual(
      SwiftLorvexCoreService.habitVisualizationHistoryCutoff(today: "2026-03-31"),
      "2025-10-01")
  }

  func testWeeklyEveryDayStreakRequiresAllSevenMetDays() async throws {
    let service = try makeService()
    let priorMondayOffset = -mondayFirstWeekday(daysFromToday: 0) - 7

    let partial = try await service.createHabit(
      name: "Partial every day", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: []))
    for day in 0..<6 {
      _ = try await service.completeHabit(
        id: partial.id, date: ymdOffsetFromToday(byDays: priorMondayOffset + day))
    }
    let partialStats = try await service.getHabitStats(id: partial.id)
    XCTAssertEqual(partialStats.currentStreak, 0)
    XCTAssertEqual(partialStats.bestStreak, 0)

    let met = try await service.createHabit(
      name: "Met every day", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: []))
    for day in 0..<7 {
      _ = try await service.completeHabit(
        id: met.id, date: ymdOffsetFromToday(byDays: priorMondayOffset + day))
    }
    let metStats = try await service.getHabitStats(id: met.id)
    XCTAssertEqual(metStats.currentStreak, 1)
    XCTAssertEqual(metStats.bestStreak, 1)
  }

  func testPinnedWeeklyStreakCountsTargetMetDaysNotCompletionUnits() async throws {
    let service = try makeService()
    let priorMondayOffset = -mondayFirstWeekday(daysFromToday: 0) - 7
    let pins = [
      mondayFirstWeekday(daysFromToday: priorMondayOffset),
      mondayFirstWeekday(daysFromToday: priorMondayOffset + 1),
    ]

    let met = try await service.createHabit(
      name: "Two target days", cue: nil, icon: nil, color: nil, targetCount: 2,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: pins))
    for offset in [priorMondayOffset, priorMondayOffset + 1] {
      _ = try await service.completeHabit(id: met.id, date: ymdOffsetFromToday(byDays: offset))
      _ = try await service.completeHabit(id: met.id, date: ymdOffsetFromToday(byDays: offset))
    }
    let metStats = try await service.getHabitStats(id: met.id)
    XCTAssertEqual(
      metStats.currentStreak, 1,
      "two independently met pinned days satisfy the week; value=2 is not two dates")
    XCTAssertEqual(metStats.bestStreak, 1)

    let partial = try await service.createHabit(
      name: "One partial target day", cue: nil, icon: nil, color: nil, targetCount: 2,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: pins))
    _ = try await service.completeHabit(
      id: partial.id, date: ymdOffsetFromToday(byDays: priorMondayOffset))
    for _ in 0..<2 {
      _ = try await service.completeHabit(
        id: partial.id, date: ymdOffsetFromToday(byDays: priorMondayOffset + 1))
    }
    let partialStats = try await service.getHabitStats(id: partial.id)
    XCTAssertEqual(partialStats.currentStreak, 0)
    XCTAssertEqual(partialStats.bestStreak, 0)
  }

  func testPinnedWeeklyStreakIgnoresMetCompletionsOnUnscheduledDays() async throws {
    let service = try makeService()
    let priorMondayOffset = -mondayFirstWeekday(daysFromToday: 0) - 7
    let monday = mondayFirstWeekday(daysFromToday: priorMondayOffset)
    let habit = try await service.createHabit(
      name: "Pinned days only", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [monday]))

    _ = try await service.completeHabit(
      id: habit.id, date: ymdOffsetFromToday(byDays: priorMondayOffset + 1))

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(stats.currentStreak, 0)
    XCTAssertEqual(stats.bestStreak, 0)
  }

  func testMonthlyStreakCountsOneMetDateRegardlessOfPerDayTarget() async throws {
    let service = try makeService()
    let partial = try await service.createHabit(
      name: "Partial monthly", cue: nil, icon: nil, color: nil, targetCount: 2,
      cadence: HabitCadenceInput(frequencyType: "monthly"))
    _ = try await service.completeHabit(id: partial.id, date: todayYmd())
    let partialStats = try await service.getHabitStats(id: partial.id)
    XCTAssertEqual(partialStats.currentStreak, 0)
    XCTAssertEqual(partialStats.bestStreak, 0)

    let met = try await service.createHabit(
      name: "Met monthly", cue: nil, icon: nil, color: nil, targetCount: 2,
      cadence: HabitCadenceInput(frequencyType: "monthly"))
    _ = try await service.completeHabit(id: met.id, date: todayYmd())
    _ = try await service.completeHabit(id: met.id, date: todayYmd())
    let metStats = try await service.getHabitStats(id: met.id)
    XCTAssertEqual(metStats.currentStreak, 1)
    XCTAssertEqual(metStats.bestStreak, 1)
  }

  /// A brand-new habit that is completed on its only active day reads 100%
  /// adherent. The adherence denominator is the days the habit has actually
  /// existed, not a fixed 30 — a one-day-old perfect daily habit scored against
  /// a full 30-day expectation would report ~3% (1/30) instead of 100%.
  func testCompletionRateForBrandNewHabitScoresOnlyActiveDays() async throws {
    let service = try makeService()
    let today = todayYmd()
    let habit = try await service.createHabit(
      name: "Meditate", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily)
    _ = try await service.completeHabit(id: habit.id, date: today)

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      stats.completionRate30d, 1.0, accuracy: 0.0001,
      "a one-day-old habit completed on its only active day is 100%, not 1/30")
  }

  /// Adherence denominates by the habit's active days for a habit younger than
  /// the 30-day window. A daily habit created three days ago (four active days
  /// including today) that is completed every day reads 100%; clearing two of
  /// those days reads 50% — both against a 4-day expectation, never 30.
  func testCompletionRateDenominatesByActiveDaysForYoungHabit() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Read", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily)
    // Backdate creation to three days ago: four active days including today.
    let createdAt = utcTimestamp(daysAgo: 3)
    try service.write { db in
      try db.execute(
        sql: "UPDATE habits SET created_at = ? WHERE id = ?",
        arguments: [createdAt, habit.id])
    }

    for back in 0...3 {
      _ = try await service.completeHabit(
        id: habit.id, date: ymdOffsetFromToday(byDays: -back))
    }
    let perfect = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      perfect.completionRate30d, 1.0, accuracy: 0.0001,
      "four completions over a four-day-old daily habit is 100%")

    // Clear two of the four met days (delta 0 toggles a met day back to 0).
    _ = try await service.adjustHabitCompletion(
      id: habit.id, date: ymdOffsetFromToday(byDays: -1), delta: 0)
    _ = try await service.adjustHabitCompletion(
      id: habit.id, date: ymdOffsetFromToday(byDays: -3), delta: 0)
    let partial = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      partial.completionRate30d, 0.5, accuracy: 0.0001,
      "two of four active days is 50%, denominated by active days not 30")
  }

  /// Monday-first weekday index (0=Mon … 6=Sun, matching `HabitCadenceInput`'s
  /// weekday ints) for a calendar-day offset from today in `TimeZone.current` —
  /// the timezone the service resolves scheduled days in.
  private func mondayFirstWeekday(daysFromToday days: Int) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let date = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
    return (cal.component(.weekday, from: date) + 5) % 7  // Sun=1..Sat=7 → Mon=0..Sun=6
  }

  /// Day-of-month for a calendar-day offset from today in `TimeZone.current`.
  private func dayOfMonth(daysFromToday days: Int) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let date = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
    return cal.component(.day, from: date)
  }

  /// A young pinned-weekday habit is denominated by the scheduled weekdays that
  /// have actually come due, not a linear pro-rate that saturates. Pinned to
  /// today's and yesterday's weekdays and backdated to yesterday, two occurrences
  /// are due; completing only today reads 50%, where the pro-rate reported a
  /// saturated ~100% (`expected = 2 × 2/7 ≈ 0.57 < 1`).
  func testCompletionRateWeeklyPinnedYoungDoesNotSaturate() async throws {
    let service = try makeService()
    let pins = [mondayFirstWeekday(daysFromToday: 0), mondayFirstWeekday(daysFromToday: -1)]
    let habit = try await service.createHabit(
      name: "Gym pinned", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: pins))
    let createdAt_habit = utcTimestamp(daysAgo: 1)
    try service.write { db in
      try db.execute(
        sql: "UPDATE habits SET created_at = ? WHERE id = ?",
        arguments: [createdAt_habit, habit.id])
    }
    _ = try await service.completeHabit(id: habit.id, date: todayYmd())

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      stats.completionRate30d, 0.5, accuracy: 0.0001,
      "one of two due scheduled weekdays is 50%, not a saturated 100%")
  }

  /// A pinned-weekday habit created on a day it is NOT scheduled has no due
  /// occurrence yet, so nothing has been missed: the rate is a full 100%, not the
  /// spurious ~0% the schedule-blind pro-rate produced.
  func testCompletionRatePinnedWeekdayCreatedOnNonScheduledDayReadsFull() async throws {
    let service = try makeService()
    // Two weekdays neither of which is today's; the window is only today.
    let pins = [mondayFirstWeekday(daysFromToday: 2), mondayFirstWeekday(daysFromToday: 3)]
    let habit = try await service.createHabit(
      name: "Weekend run", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: pins))

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      stats.completionRate30d, 1.0, accuracy: 0.0001,
      "no scheduled weekday has come due yet, so nothing has been missed (not a spurious fraction)")
  }

  /// A young `times_per_week` habit reads a real fraction of its weekly quota,
  /// not a saturated 100%. One completion into a 3×/week week is 1/3 — the exact
  /// case the pro-rate mis-scored (`expected = 3 × 1/7 ≈ 0.43`, so one completion
  /// clamped to 100%).
  func testCompletionRateTimesPerWeekYoungDoesNotSaturate() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Gym 3x", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3))
    _ = try await service.completeHabit(id: habit.id, date: todayYmd())

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      stats.completionRate30d, 1.0 / 3.0, accuracy: 0.0001,
      "one completion into a 3×/week week is 1/3, not a saturated 100%")
  }

  /// A monthly habit's adherence is sensible around its single due day: full
  /// before the day-of-month comes round (nothing due yet), full when the due
  /// occurrence was completed, and zero when it was missed — replacing the
  /// pro-rate's "0% until the first completion, then a jump to 100%".
  func testCompletionRateMonthlyYoungIsSensibleAroundDueDay() async throws {
    let service = try makeService()

    // Before the due day: day-of-month other than today's, created today → the
    // occurrence has not come due, so nothing has been missed.
    let todayDom = dayOfMonth(daysFromToday: 0)
    let futureDom = todayDom < 28 ? todayDom + 1 : 1
    let before = try await service.createHabit(
      name: "Pay rent", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly", dayOfMonth: futureDom))
    let beforeStats = try await service.getHabitStats(id: before.id)
    XCTAssertEqual(
      beforeStats.completionRate30d, 1.0, accuracy: 0.0001,
      "a monthly habit whose day-of-month has not come round has nothing due, not 0%")

    // After the due day, completed: day-of-month = yesterday, backdated to
    // yesterday, completed yesterday → the one due occurrence was met.
    let yesterdayDom = dayOfMonth(daysFromToday: -1)
    let met = try await service.createHabit(
      name: "Monthly met", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly", dayOfMonth: yesterdayDom))
    let createdAt_met = utcTimestamp(daysAgo: 1)
    try service.write { db in
      try db.execute(
        sql: "UPDATE habits SET created_at = ? WHERE id = ?",
        arguments: [createdAt_met, met.id])
    }
    _ = try await service.completeHabit(id: met.id, date: ymdOffsetFromToday(byDays: -1))
    let metStats = try await service.getHabitStats(id: met.id)
    XCTAssertEqual(
      metStats.completionRate30d, 1.0, accuracy: 0.0001,
      "the one monthly occurrence that came due was completed → 100%")

    // After the due day, missed: same setup with no completion → the occurrence
    // that came due was missed.
    let missed = try await service.createHabit(
      name: "Monthly missed", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly", dayOfMonth: yesterdayDom))
    let createdAt_missed = utcTimestamp(daysAgo: 1)
    try service.write { db in
      try db.execute(
        sql: "UPDATE habits SET created_at = ? WHERE id = ?",
        arguments: [createdAt_missed, missed.id])
    }
    let missedStats = try await service.getHabitStats(id: missed.id)
    XCTAssertEqual(
      missedStats.completionRate30d, 0.0, accuracy: 0.0001,
      "the one monthly occurrence that came due was missed → 0%")
  }

  /// A habit older than 30 days is still scored over the full trailing 30-day
  /// window (the L12 intent), and daily denomination is unchanged: a daily habit
  /// backdated 40 days with a single completion reads 1/30, not 100%.
  func testCompletionRateDailyOldHabitUsesFull30DayWindow() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Old daily", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily)
    let createdAt_habit = utcTimestamp(daysAgo: 40)
    try service.write { db in
      try db.execute(
        sql: "UPDATE habits SET created_at = ? WHERE id = ?",
        arguments: [createdAt_habit, habit.id])
    }
    _ = try await service.completeHabit(id: habit.id, date: todayYmd())

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      stats.completionRate30d, 1.0 / 30.0, accuracy: 0.0005,
      "an old daily habit is scored over the full 30-day window: one of 30 due days")
  }

  /// A `times_per_week` habit older than 30 days computes a real adherence over
  /// the full window: completing every day over-satisfies the 3×/week quota and
  /// reads 100% (clamped), confirming the denominator scales with the window
  /// rather than collapsing.
  func testCompletionRateTimesPerWeekOldHabitComputesRealAdherence() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Old gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3))
    let createdAt_habit = utcTimestamp(daysAgo: 40)
    try service.write { db in
      try db.execute(
        sql: "UPDATE habits SET created_at = ? WHERE id = ?",
        arguments: [createdAt_habit, habit.id])
    }
    for back in 0..<30 {
      _ = try await service.completeHabit(id: habit.id, date: ymdOffsetFromToday(byDays: -back))
    }

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      stats.completionRate30d, 1.0, accuracy: 0.0001,
      "completing every day over-satisfies a 3×/week quota across the full window → 100%")
  }

  /// A pinned-weekday habit older than 30 days computes a real adherence over the
  /// full window: completing every scheduled occurrence (each day in the window
  /// whose weekday is pinned) reads 100%, denominated by the scheduled weekdays
  /// that came due rather than a linear pro-rate.
  func testCompletionRateWeeklyPinnedOldHabitComputesRealAdherence() async throws {
    let service = try makeService()
    let pinnedWeekday = mondayFirstWeekday(daysFromToday: 0)  // today's weekday
    let habit = try await service.createHabit(
      name: "Old weekly", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [pinnedWeekday]))
    let createdAt = utcTimestamp(daysAgo: 40)
    try service.write { db in
      try db.execute(
        sql: "UPDATE habits SET created_at = ? WHERE id = ?",
        arguments: [createdAt, habit.id])
    }
    // Complete every scheduled occurrence in the 30-day window: numerator equals
    // the number of pinned-weekday days that came due, so the rate is exactly 1.
    for back in 0..<30 where mondayFirstWeekday(daysFromToday: -back) == pinnedWeekday {
      _ = try await service.completeHabit(id: habit.id, date: ymdOffsetFromToday(byDays: -back))
    }

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      stats.completionRate30d, 1.0, accuracy: 0.0001,
      "completing every scheduled weekday in the 30-day window is 100%")
  }

  func testHabitCompletionAcceptsCanonicalDatePastTheDateGuard() async throws {
    let service = try makeService()
    // A canonical date clears the date guard and then fails on the missing
    // habit — proving the date itself was accepted rather than format-rejected.
    do {
      _ = try await service.completeHabit(id: "missing", date: "2026-06-09")
      XCTFail("expected a not-found error for the missing habit")
    } catch let error as LorvexCoreError {
      // A canonical date clears the date guard, so the failure is the typed habit
      // lookup miss — not a date-format validation error.
      if case .notFound(.habit, let id) = error {
        XCTAssertEqual(id, "missing", "the missing habit id is carried; got: \(error)")
      } else {
        XCTFail("unexpected error: \(error)")
      }
    }
  }
}
