import LorvexStore
import XCTest

@testable import LorvexCore

/// `LorvexHabit.periodMetDays` and `periodExcusedDays` on
/// `SwiftLorvexCoreService.loadHabits(date:)`: how many days of the habit's
/// current period met its per-day target through the loaded day, and how many
/// scheduled days of a weekly habit's week were set aside. The period is the
/// Gregorian month for a monthly habit and the ISO week (Monday first) for a
/// times-per-week or weekly one; a daily habit reads 0. 2026-04-06 is a
/// Monday, and 2026-06-24 a Wednesday.
final class SwiftLorvexCoreServiceHabitPeriodTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(
      schemaSQL: schemaSQL, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations())
    return SwiftLorvexCoreService(store: store)
  }

  private func periodMetDays(
    _ service: SwiftLorvexCoreService, habit: LorvexHabit, on day: String
  ) async throws -> Int {
    let snapshot = try await service.loadHabits(date: day)
    return try XCTUnwrap(snapshot.habits.first { $0.id == habit.id }).periodMetDays
  }

  func testTimesPerWeekHabitCountsTheWeeksMetDaysThroughTheLoadedDay() async throws {
    let service = try makeService()
    let run = try await service.createHabit(
      name: "Run", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3),
      milestoneTarget: nil)
    // A Sunday of the previous week, then Monday, Wednesday and Friday.
    for day in ["2026-04-05", "2026-04-06", "2026-04-08", "2026-04-10"] {
      _ = try await service.completeHabit(id: run.id, date: day)
    }

    let monday = try await periodMetDays(service, habit: run, on: "2026-04-06")
    let wednesday = try await periodMetDays(service, habit: run, on: "2026-04-08")
    let sunday = try await periodMetDays(service, habit: run, on: "2026-04-12")
    let nextMonday = try await periodMetDays(service, habit: run, on: "2026-04-13")

    XCTAssertEqual(monday, 1, "the previous Sunday belongs to the previous week")
    XCTAssertEqual(wednesday, 2)
    XCTAssertEqual(sunday, 3, "Monday, Wednesday and Friday")
    XCTAssertEqual(nextMonday, 0, "a new week starts empty")
  }

  func testMonthlyHabitCountsTheMonthsDaysThatMetTheTarget() async throws {
    let service = try makeService()
    let report = try await service.createHabit(
      name: "Report", cue: nil, icon: nil, color: nil, targetCount: 2,
      cadence: HabitCadenceInput(frequencyType: "monthly"))
    // Met on the last day of March, one of two on April 3, met on April 9.
    for day in ["2026-03-31", "2026-03-31", "2026-04-03", "2026-04-09", "2026-04-09"] {
      _ = try await service.completeHabit(id: report.id, date: day)
    }

    let beforePartial = try await periodMetDays(service, habit: report, on: "2026-04-02")
    let partial = try await periodMetDays(service, habit: report, on: "2026-04-03")
    let met = try await periodMetDays(service, habit: report, on: "2026-04-09")
    let monthEnd = try await periodMetDays(service, habit: report, on: "2026-04-30")
    let nextMonth = try await periodMetDays(service, habit: report, on: "2026-05-01")

    XCTAssertEqual(beforePartial, 0, "a met day in March, or one later in April, is not counted")
    XCTAssertEqual(partial, 0, "one of two is not a met day")
    XCTAssertEqual(met, 1)
    XCTAssertEqual(monthEnd, 1)
    XCTAssertEqual(nextMonth, 0, "a new month starts empty")
  }

  func testDailyHabitReadsZero() async throws {
    let service = try makeService()
    let water = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily)
    _ = try await service.completeHabit(id: water.id, date: "2026-04-06")

    let waterMet = try await periodMetDays(service, habit: water, on: "2026-04-06")
    let waterExcused = try await load(service, water, on: "2026-04-06").periodExcusedDays

    XCTAssertEqual(waterMet, 0)
    XCTAssertEqual(waterExcused, 0)
  }

  // MARK: - Weekly habits

  /// The Mon–Sun week of the loaded day below is 2026-06-22…06-28.
  private let wednesday = "2026-06-24"

  private func load(
    _ service: SwiftLorvexCoreService, _ habit: LorvexHabit, on day: String
  ) async throws -> LorvexHabit {
    let snapshot = try await service.loadHabits(date: day)
    return try XCTUnwrap(snapshot.habits.first { $0.id == habit.id })
  }

  private func gym(
    _ service: SwiftLorvexCoreService, name: String = "Gym", weekdays: [Int]? = [0, 2, 4]
  ) async throws -> LorvexHabit {
    try await service.createHabit(
      name: name, cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: weekdays))
  }

  func testWeeklyHabitCountsOnlyItsPinnedDaysOfTheWeekThroughTheLoadedDay() async throws {
    let service = try makeService()
    let habit = try await gym(service)  // Monday, Wednesday, Friday
    // Friday of the previous week, then Monday, an unpinned Tuesday, and Wednesday.
    for day in ["2026-06-19", "2026-06-22", "2026-06-23", "2026-06-24"] {
      _ = try await service.completeHabit(id: habit.id, date: day)
    }

    let tuesday = try await periodMetDays(service, habit: habit, on: "2026-06-23")
    let wednesdayMet = try await periodMetDays(service, habit: habit, on: wednesday)
    let nextMonday = try await periodMetDays(service, habit: habit, on: "2026-06-29")

    XCTAssertEqual(tuesday, 1, "Monday; Tuesday is not a pinned day")
    XCTAssertEqual(wednesdayMet, 2, "Monday and Wednesday; last week's Friday and this Tuesday do not count")
    XCTAssertEqual(nextMonday, 0, "a new week starts empty")
  }

  func testWeeklyEveryDayHabitCountsEveryMetDayOfTheWeek() async throws {
    let service = try makeService()
    let habit = try await gym(service, weekdays: nil)
    for day in ["2026-06-21", "2026-06-22", "2026-06-23"] {
      _ = try await service.completeHabit(id: habit.id, date: day)
    }

    let met = try await periodMetDays(service, habit: habit, on: wednesday)

    XCTAssertEqual(met, 2, "Sunday of the previous week is not counted")
  }

  func testSkippedPinnedDaysLowerTheWeeklyRequirementAndCompleteTheWeekSooner() async throws {
    let service = try makeService()
    let habit = try await gym(service)
    _ = try await service.completeHabit(id: habit.id, date: "2026-06-22")
    _ = try await service.skipHabit(id: habit.id, date: wednesday)

    let loaded = try await load(service, habit, on: wednesday)
    let progress = HabitPeriodProgress.current(habit: loaded)

    XCTAssertEqual(loaded.periodExcusedDays, 1)
    XCTAssertEqual(progress, HabitPeriodProgress.Value(completed: 1, required: 2))

    _ = try await service.completeHabit(id: habit.id, date: "2026-06-26")
    let friday = try await load(service, habit, on: "2026-06-26")
    XCTAssertEqual(
      HabitPeriodProgress.current(habit: friday), HabitPeriodProgress.Value(completed: 2, required: 2))
    XCTAssertTrue(HabitPeriodProgress.current(habit: friday).isComplete)
  }

  func testASkipOnAnUnpinnedDayOrInAnotherWeekExcusesNothing() async throws {
    let service = try makeService()
    let habit = try await gym(service)
    for day in ["2026-06-23", "2026-06-17", "2026-07-01"] {  // Tuesday; last and next week's Wednesday
      _ = try await service.skipHabit(id: habit.id, date: day)
    }

    let loaded = try await load(service, habit, on: wednesday)

    XCTAssertEqual(loaded.periodExcusedDays, 0)
    XCTAssertEqual(
      HabitPeriodProgress.current(habit: loaded), HabitPeriodProgress.Value(completed: 0, required: 3))
  }

  func testSkippingEveryPinnedDayLeavesARequirementOfOne() async throws {
    let service = try makeService()
    let habit = try await gym(service)  // Monday, Wednesday, Friday
    for day in ["2026-06-22", "2026-06-24", "2026-06-26"] {
      _ = try await service.skipHabit(id: habit.id, date: day)
    }
    let pinnedOnce = try await gym(service, name: "Stretch", weekdays: [2])
    _ = try await service.skipHabit(id: pinnedOnce.id, date: wednesday)

    let allThree = try await load(service, habit, on: "2026-06-26")
    let only = try await load(service, pinnedOnce, on: wednesday)

    XCTAssertEqual(allThree.periodExcusedDays, 3)
    XCTAssertEqual(
      HabitPeriodProgress.current(habit: allThree), HabitPeriodProgress.Value(completed: 0, required: 1))
    XCTAssertEqual(
      HabitPeriodProgress.current(habit: only), HabitPeriodProgress.Value(completed: 0, required: 1))
  }

  func testAnEveryDayWeeklyHabitLosesOneRequiredDayPerSkippedDay() async throws {
    let service = try makeService()
    let habit = try await gym(service, weekdays: nil)
    for day in ["2026-06-23", "2026-06-24"] {
      _ = try await service.skipHabit(id: habit.id, date: day)
    }

    let loaded = try await load(service, habit, on: wednesday)

    XCTAssertEqual(loaded.periodExcusedDays, 2)
    XCTAssertEqual(
      HabitPeriodProgress.current(habit: loaded), HabitPeriodProgress.Value(completed: 0, required: 5))
  }

  func testOtherCadencesExcuseNothingAndKeepTheirOwnPeriods() async throws {
    let service = try makeService()
    let quota = try await service.createHabit(
      name: "Run", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3),
      milestoneTarget: nil)
    let monthly = try await service.createHabit(
      name: "Report", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly"))
    let water = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 8, cadence: .daily)
    for habit in [quota, monthly, water] {
      _ = try await service.skipHabit(id: habit.id, date: wednesday)
    }
    for day in ["2026-06-22", "2026-06-23", "2026-06-15"] {
      _ = try await service.completeHabit(id: quota.id, date: day)
    }
    _ = try await service.completeHabit(id: monthly.id, date: "2026-06-01")
    for _ in 0..<3 { _ = try await service.completeHabit(id: water.id, date: wednesday) }

    let quotaLoaded = try await load(service, quota, on: wednesday)
    let monthlyLoaded = try await load(service, monthly, on: wednesday)
    let waterLoaded = try await load(service, water, on: wednesday)

    XCTAssertEqual(quotaLoaded.periodExcusedDays + monthlyLoaded.periodExcusedDays + waterLoaded.periodExcusedDays, 0)
    XCTAssertEqual(
      HabitPeriodProgress.current(habit: quotaLoaded), HabitPeriodProgress.Value(completed: 2, required: 3))
    XCTAssertEqual(
      HabitPeriodProgress.current(habit: monthlyLoaded), HabitPeriodProgress.Value(completed: 1, required: 1))
    XCTAssertEqual(
      HabitPeriodProgress.current(habit: waterLoaded), HabitPeriodProgress.Value(completed: 3, required: 8))
  }
}
