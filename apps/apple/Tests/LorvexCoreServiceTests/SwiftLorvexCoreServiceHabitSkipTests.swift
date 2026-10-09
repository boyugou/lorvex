import GRDB
import LorvexStore
import XCTest

@testable import LorvexCore

/// Skipped days on `SwiftLorvexCoreService`: the write funnel, its sync and audit
/// side effects, the interaction with check-ins, and the effect on stats. A skip
/// excuses one day for one habit; a day holds a check-in or a skip, never both.
final class SwiftLorvexCoreServiceHabitSkipTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    try SwiftLorvexCoreService.inMemory()
  }

  /// `YYYY-MM-DD` for a calendar-day offset from today in `TimeZone.current`, the
  /// timezone the service resolves `today` in when no preference is set.
  private func ymd(daysFromToday days: Int) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let shifted = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: shifted)
  }

  /// A canonical RFC 3339 UTC sync timestamp `days` days before now, at the same
  /// wall-clock time in `TimeZone.current`, so it resolves back to the day
  /// `ymd(daysFromToday: -days)` as a habit's creation day.
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

  private func createDaily(
    _ service: SwiftLorvexCoreService, name: String = "Cardio"
  ) async throws -> LorvexHabit {
    try await service.createHabit(
      name: name, cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily)
  }

  private func loaded(
    _ service: SwiftLorvexCoreService, _ habit: LorvexHabit, on date: String
  ) async throws -> LorvexHabit {
    let snapshot = try await service.loadHabits(date: date)
    return try XCTUnwrap(snapshot.habits.first { $0.id == habit.id })
  }

  private func skipDates(_ service: SwiftLorvexCoreService, habitID: String) throws -> [String] {
    try service.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT skipped_date FROM habit_skips WHERE habit_id = ? ORDER BY skipped_date",
        arguments: [habitID])
    }
  }

  /// The queued outbox operation per entity id. The outbox keeps one pending
  /// envelope per entity, so a later write replaces an earlier one.
  private func queuedOperations(
    _ service: SwiftLorvexCoreService, entityType: String
  ) throws -> [String: String] {
    try service.read { db in
      var queued: [String: String] = [:]
      for row in try Row.fetchAll(
        db, sql: "SELECT entity_id, operation FROM sync_outbox WHERE entity_type = ?",
        arguments: [entityType])
      {
        queued[row["entity_id"]] = row["operation"] as String
      }
      return queued
    }
  }

  private func mutationCounts(_ service: SwiftLorvexCoreService) throws
    -> (outbox: Int64, changelog: Int64)
  {
    try service.read { db in
      (
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? 0,
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
      )
    }
  }

  // MARK: - Skip and unskip

  func testSkipExcusesTheDayAndIsIdempotent() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    let today = ymd(daysFromToday: 0)
    let beforeSkip = try await loaded(service, habit, on: today)
    XCTAssertFalse(beforeSkip.isSkipped)

    let snapshot = try await service.skipHabit(id: habit.id, date: today)
    XCTAssertTrue(try XCTUnwrap(snapshot.habits.first { $0.id == habit.id }).isSkipped)
    let afterSkip = try await loaded(service, habit, on: today)
    XCTAssertTrue(afterSkip.isListed(on: today))
    let tomorrow = try await loaded(service, habit, on: ymd(daysFromToday: 1))
    XCTAssertFalse(tomorrow.isSkipped, "a skip excuses only its own day")
    XCTAssertEqual(try skipDates(service, habitID: habit.id), [today])

    let before = try mutationCounts(service)
    _ = try await service.skipHabit(id: habit.id, date: today)
    let after = try mutationCounts(service)
    XCTAssertEqual(before.outbox, after.outbox, "skipping a skipped day enqueues nothing")
    XCTAssertEqual(before.changelog, after.changelog, "skipping a skipped day writes no audit row")
    XCTAssertEqual(try skipDates(service, habitID: habit.id), [today])
  }

  func testSkipAndUnskipSyncAsAnEdgeUpsertThenDeleteAndAreAudited() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    let today = ymd(daysFromToday: 0)

    let entityId = "\(habit.id):\(today)"

    _ = try await service.skipHabit(id: habit.id, date: today)
    XCTAssertEqual(try queuedOperations(service, entityType: "habit_skip"), [entityId: "upsert"])

    let snapshot = try await service.unskipHabit(id: habit.id, date: today)
    XCTAssertFalse(try XCTUnwrap(snapshot.habits.first { $0.id == habit.id }).isSkipped)
    XCTAssertEqual(try skipDates(service, habitID: habit.id), [])
    XCTAssertEqual(
      try queuedOperations(service, entityType: "habit_skip"), [entityId: "delete"],
      "the queued upsert is replaced by the delete")
    let tombstones = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'habit_skip'")
    }
    XCTAssertEqual(tombstones, 1, "removing a skip leaves a tombstone so peers drop it too")

    let operations = try service.read { db in
      try String.fetchAll(
        db, sql: "SELECT operation FROM ai_changelog WHERE entity_type = 'habit' ORDER BY rowid")
    }
    XCTAssertTrue(operations.contains("skip"))
    XCTAssertTrue(operations.contains("unskip"))

    let before = try mutationCounts(service)
    _ = try await service.unskipHabit(id: habit.id, date: today)
    let after = try mutationCounts(service)
    XCTAssertEqual(before.outbox, after.outbox, "lifting a day that holds no skip enqueues nothing")
    XCTAssertEqual(before.changelog, after.changelog)
  }

  func testSkippingTheSameDayAgainAfterAnUnskipWritesANewerEdge() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    let today = ymd(daysFromToday: 0)
    func storedVersion() throws -> String {
      try service.read { db in
        try XCTUnwrap(String.fetchOne(db, sql: "SELECT version FROM habit_skips"))
      }
    }
    _ = try await service.skipHabit(id: habit.id, date: today)
    let first = try storedVersion()
    _ = try await service.unskipHabit(id: habit.id, date: today)
    _ = try await service.skipHabit(id: habit.id, date: today)

    XCTAssertEqual(try skipDates(service, habitID: habit.id), [today])
    XCTAssertGreaterThan(try storedVersion(), first, "the new skip must dominate the old one")
    XCTAssertEqual(
      try queuedOperations(service, entityType: "habit_skip"),
      ["\(habit.id):\(today)": "upsert"])
    let tombstones = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'habit_skip'")
    }
    XCTAssertEqual(tombstones, 0, "a skip that is back has no tombstone left to block it")
  }

  // MARK: - Check-ins

  func testSkipIsRejectedOnACheckedInDay() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    let today = ymd(daysFromToday: 0)
    _ = try await service.completeHabit(id: habit.id, date: today)

    do {
      _ = try await service.skipHabit(id: habit.id, date: today)
      XCTFail("a checked-in day cannot be skipped")
    } catch LorvexCoreError.validation(let field, _) {
      XCTAssertEqual(field, "date")
    }
    XCTAssertEqual(try skipDates(service, habitID: habit.id), [])
  }

  func testEveryCheckInPathLiftsTheSkipOnItsDay() async throws {
    let service = try makeService()
    let single = try await createDaily(service, name: "Single")
    let adjusted = try await createDaily(service, name: "Adjusted")
    let batched = try await createDaily(service, name: "Batched")
    let today = ymd(daysFromToday: 0)
    for habit in [single, adjusted, batched] {
      _ = try await service.skipHabit(id: habit.id, date: today)
    }

    _ = try await service.completeHabit(id: single.id, date: today)
    _ = try await service.adjustHabitCompletion(id: adjusted.id, date: today, delta: 1)
    _ = try await service.batchCompleteHabits(ids: [batched.id], date: today)

    for habit in [single, adjusted, batched] {
      XCTAssertEqual(try skipDates(service, habitID: habit.id), [], habit.name)
      let reloaded = try await loaded(service, habit, on: today)
      XCTAssertFalse(reloaded.isSkipped, habit.name)
      XCTAssertEqual(reloaded.completionsToday, 1, habit.name)
    }
    XCTAssertEqual(
      try queuedOperations(service, entityType: "habit_skip"),
      [
        "\(single.id):\(today)": "delete", "\(adjusted.id):\(today)": "delete",
        "\(batched.id):\(today)": "delete",
      ],
      "each check-in sends the skip's delete to peers")
  }

  func testACheckInOnAnotherDayLeavesTheSkipAlone() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    let today = ymd(daysFromToday: 0)
    _ = try await service.skipHabit(id: habit.id, date: today)
    _ = try await service.completeHabit(id: habit.id, date: ymd(daysFromToday: -1))
    XCTAssertEqual(try skipDates(service, habitID: habit.id), [today])
  }

  // MARK: - Rejections

  func testSkipRejectsUnknownArchivedAndMalformedInput() async throws {
    let service = try makeService()
    let today = ymd(daysFromToday: 0)
    do {
      _ = try await service.skipHabit(id: "00000000-0000-4000-8000-000000000000", date: today)
      XCTFail("an unknown habit cannot be skipped")
    } catch LorvexCoreError.notFound(let entity, _) {
      XCTAssertEqual(entity, .habit)
    }

    let habit = try await createDaily(service)
    for bad in ["2026-6-9", "June 9", "2026-13-01", ""] {
      do {
        _ = try await service.skipHabit(id: habit.id, date: bad)
        XCTFail("\(bad) is not a canonical date")
      } catch LorvexCoreError.validation(let field, _) {
        XCTAssertEqual(field, "date", bad)
      }
      do {
        _ = try await service.unskipHabit(id: habit.id, date: bad)
        XCTFail("\(bad) is not a canonical date")
      } catch LorvexCoreError.validation(let field, _) {
        XCTAssertEqual(field, "date", bad)
      }
    }

    _ = try await service.updateHabit(
      id: habit.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
      archived: true, cadence: nil)
    do {
      _ = try await service.skipHabit(id: habit.id, date: today)
      XCTFail("an archived habit cannot be skipped")
    } catch LorvexCoreError.validation(let field, _) {
      XCTAssertEqual(field, "id")
    }
    XCTAssertEqual(try skipDates(service, habitID: habit.id), [])
  }

  func testDeletingAHabitSendsDeletesForItsSkips() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    _ = try await service.skipHabit(id: habit.id, date: ymd(daysFromToday: 0))
    _ = try await service.skipHabit(id: habit.id, date: ymd(daysFromToday: -1))
    _ = try await service.deleteHabit(id: habit.id)

    XCTAssertEqual(
      try queuedOperations(service, entityType: "habit_skip"),
      [
        "\(habit.id):\(ymd(daysFromToday: 0))": "delete",
        "\(habit.id):\(ymd(daysFromToday: -1))": "delete",
      ])
    XCTAssertEqual(try skipDates(service, habitID: habit.id), [])
  }

  // MARK: - Stats

  func testSkippedDayKeepsADailyStreakAlive() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    _ = try await service.completeHabit(id: habit.id, date: ymd(daysFromToday: -3))
    _ = try await service.completeHabit(id: habit.id, date: ymd(daysFromToday: -2))
    let before = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(before.currentStreak, 0, "yesterday was missed")

    _ = try await service.skipHabit(id: habit.id, date: ymd(daysFromToday: -1))
    let after = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(after.currentStreak, 2, "the skipped day neither adds to nor ends the streak")
    XCTAssertEqual(after.bestStreak, 2)
    XCTAssertEqual(after.recentSkips, [ymd(daysFromToday: -1)])
    let reloaded = try await loaded(service, habit, on: ymd(daysFromToday: 0))
    XCTAssertEqual(
      reloaded.milestone?.value, 2, "the milestone reading uses the same excused streak")
  }

  func testSkippedDaysAreNotCountedAsMissedInTheRate() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    // Backdate creation to nine days ago: a ten-day active window including today.
    let createdAt = utcTimestamp(daysAgo: 9)
    try service.write { db in
      try db.execute(
        sql: "UPDATE habits SET created_at = ? WHERE id = ?", arguments: [createdAt, habit.id])
    }
    for back in 5...9 {
      _ = try await service.completeHabit(id: habit.id, date: ymd(daysFromToday: -back))
    }
    let unexcused = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(unexcused.completionRate30d, 0.5, accuracy: 0.001, "5 of 10 days")

    for back in 1...4 {
      _ = try await service.skipHabit(id: habit.id, date: ymd(daysFromToday: -back))
    }
    let excused = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      excused.completionRate30d, 5.0 / 6.0, accuracy: 0.001,
      "the four skipped days are not due, leaving 5 of 6")
  }

  func testMonthlyAndTimesPerWeekHabitsKeepTheirStatsWhenSkipped() async throws {
    let service = try makeService()
    let monthly = try await service.createHabit(
      name: "Rent", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly", dayOfMonth: 1))
    let weekly = try await service.createHabit(
      name: "Run", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3))
    let today = ymd(daysFromToday: 0)
    let monthlyBefore = try await service.getHabitStats(id: monthly.id)
    let weeklyBefore = try await service.getHabitStats(id: weekly.id)

    _ = try await service.skipHabit(id: monthly.id, date: today)
    _ = try await service.skipHabit(id: weekly.id, date: today)

    let monthlyAfter = try await service.getHabitStats(id: monthly.id)
    let weeklyAfter = try await service.getHabitStats(id: weekly.id)
    XCTAssertEqual(monthlyAfter.completionRate30d, monthlyBefore.completionRate30d)
    XCTAssertEqual(monthlyAfter.currentStreak, monthlyBefore.currentStreak)
    XCTAssertEqual(weeklyAfter.completionRate30d, weeklyBefore.completionRate30d)
    XCTAssertEqual(weeklyAfter.currentStreak, weeklyBefore.currentStreak)
    let monthlyToday = try await loaded(service, monthly, on: today)
    let weeklyToday = try await loaded(service, weekly, on: today)
    XCTAssertTrue(monthlyToday.isSkipped)
    XCTAssertTrue(weeklyToday.isSkipped, "the skip still sets the habit aside for the day")
  }

  // MARK: - Day scope

  func testSkippedHabitStaysListedButLeavesTheReview() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    let today = ymd(daysFromToday: 0)
    _ = try await service.skipHabit(id: habit.id, date: today)
    let skipped = try await loaded(service, habit, on: today)

    XCTAssertTrue(skipped.isListed(on: today), "a skip stays on the list so it can be undone")
    XCTAssertFalse(skipped.isReviewed(on: today), "an excused day is not counted for or against")
    XCTAssertTrue(skipped.isDue(on: today))
  }

  func testRecentSkipsReachBackAsFarAsTheHistoryGrid() async throws {
    let service = try makeService()
    let habit = try await createDaily(service)
    _ = try await service.skipHabit(id: habit.id, date: ymd(daysFromToday: -1))
    _ = try await service.skipHabit(id: habit.id, date: ymd(daysFromToday: -300))
    _ = try await service.skipHabit(id: habit.id, date: ymd(daysFromToday: -420))

    let stats = try await service.getHabitStats(id: habit.id)
    XCTAssertEqual(
      stats.recentSkips, [ymd(daysFromToday: -300), ymd(daysFromToday: -1)],
      "skips from the trailing year are listed, ascending; older ones are not")
  }
}
