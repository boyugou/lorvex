import LorvexStore
import XCTest

@testable import LorvexCore

/// `LorvexHabit.periodMetDays` on `SwiftLorvexCoreService.loadHabits(date:)`:
/// how many days of the habit's current period met its per-day target through
/// the loaded day. The period is the Gregorian month for a monthly habit and
/// the ISO week (Monday first) for a times-per-week habit; other cadences read
/// 0. 2026-04-06 is a Monday.
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

  func testDailyAndWeeklyHabitsReadZero() async throws {
    let service = try makeService()
    let water = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily)
    let gym = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2, 4]))
    for habit in [water, gym] {
      _ = try await service.completeHabit(id: habit.id, date: "2026-04-06")
    }

    let waterMet = try await periodMetDays(service, habit: water, on: "2026-04-06")
    let gymMet = try await periodMetDays(service, habit: gym, on: "2026-04-06")

    XCTAssertEqual(waterMet, 0)
    XCTAssertEqual(gymMet, 0)
  }
}
