import Foundation
import LorvexCore
import Testing

@testable import LorvexSystemIntents

/// Skip Habit and Undo Habit Skip, the Shortcuts and Siri actions that set a
/// habit's day aside and take it back.
@Suite("Habit skip intents")
struct HabitSkipIntentTests {
  private func makeHabit(_ core: any LorvexCoreServicing) async throws -> LorvexHabit {
    try await LorvexTaskIntentRunner.createHabit(
      name: "Cardio", cue: nil, targetCount: 1, core: core)
  }

  private func isSkipped(
    _ id: LorvexHabit.ID, on date: String, in core: any LorvexCoreServicing
  ) async throws -> Bool {
    try await core.loadHabits(date: date).habits.first { $0.id == id }?.isSkipped ?? false
  }

  @Test("Skip Habit sets the named day aside and no other day")
  func skipSetsOnlyThatDayAside() async throws {
    let core = try await makeSeededInMemoryCore()
    let habit = try await makeHabit(core)

    let skipped = try await LorvexTaskIntentRunner.skipHabit(
      id: " \(habit.id) ", date: " 2026-05-24 ", core: core)
    #expect(skipped.id == habit.id)
    #expect(skipped.isSkipped)
    #expect(try await isSkipped(habit.id, on: "2026-05-24", in: core))
    #expect(try await !isSkipped(habit.id, on: "2026-05-25", in: core))
  }

  @Test("Skipping a day twice leaves it skipped once")
  func skippingAgainChangesNothing() async throws {
    let core = try await makeSeededInMemoryCore()
    let habit = try await makeHabit(core)
    // `recentSkips` covers the trailing year, so the day moves with the clock.
    let threeDaysAgo = LorvexDateFormatters.ymdUTC.string(
      from: Date(timeIntervalSinceNow: -3 * 86_400))

    _ = try await LorvexTaskIntentRunner.skipHabit(id: habit.id, date: threeDaysAgo, core: core)
    let again = try await LorvexTaskIntentRunner.skipHabit(
      id: habit.id, date: threeDaysAgo, core: core)
    #expect(again.isSkipped)
    let stats = try await core.getHabitStats(id: habit.id)
    #expect(stats.recentSkips.filter { $0 == threeDaysAgo }.count == 1)
  }

  @Test("Undo Habit Skip opens the day again, and an open day stays open")
  func unskipOpensTheDay() async throws {
    let core = try await makeSeededInMemoryCore()
    let habit = try await makeHabit(core)
    _ = try await LorvexTaskIntentRunner.skipHabit(id: habit.id, date: "2026-05-24", core: core)

    let restored = try await LorvexTaskIntentRunner.unskipHabit(
      id: " \(habit.id) ", date: " 2026-05-24 ", core: core)
    #expect(restored.id == habit.id)
    #expect(!restored.isSkipped)
    #expect(try await !isSkipped(habit.id, on: "2026-05-24", in: core))

    let untouched = try await LorvexTaskIntentRunner.unskipHabit(
      id: habit.id, date: "2026-05-24", core: core)
    #expect(!untouched.isSkipped)
  }

  @Test("A day that already holds a check-in cannot be skipped")
  func skipRefusesACheckedInDay() async throws {
    let core = try await makeSeededInMemoryCore()
    let habit = try await makeHabit(core)
    _ = try await LorvexTaskIntentRunner.completeHabit(
      id: habit.id, date: "2026-05-24", core: core)

    await #expect(throws: LorvexIntentFailure.self) {
      _ = try await LorvexTaskIntentRunner.skipHabit(
        id: habit.id, date: "2026-05-24", core: core)
    }
    #expect(try await !isSkipped(habit.id, on: "2026-05-24", in: core))
  }

  @Test("A check-in on a skipped day lifts the skip")
  func checkInLiftsTheSkip() async throws {
    let core = try await makeSeededInMemoryCore()
    let habit = try await makeHabit(core)
    _ = try await LorvexTaskIntentRunner.skipHabit(id: habit.id, date: "2026-05-24", core: core)

    let completed = try await LorvexTaskIntentRunner.completeHabit(
      id: habit.id, date: "2026-05-24", core: core)
    #expect(!completed.isSkipped)
    #expect(completed.completionsToday == 1)
  }

  @Test("An unknown or blank habit is refused with the shared failure")
  func unknownAndBlankHabitsAreRefused() async throws {
    let core = try await makeSeededInMemoryCore()
    await #expect(throws: LorvexIntentFailure.self) {
      _ = try await LorvexTaskIntentRunner.skipHabit(id: "   ", date: nil, core: core)
    }
    await #expect(throws: LorvexIntentFailure.self) {
      _ = try await LorvexTaskIntentRunner.unskipHabit(id: "   ", date: nil, core: core)
    }
    await #expect(throws: LorvexIntentFailure.self) {
      _ = try await LorvexTaskIntentRunner.skipHabit(
        id: "no-such-habit", date: "2026-05-24", core: core)
    }
  }

  @Test("Both actions refuse a blank habit before touching the store")
  func intentsRefuseABlankHabit() async throws {
    let blank = LorvexHabitEntity(id: "   ", name: "", completionsToday: 0, targetCount: 1)
    await #expect(throws: LorvexIntentFailure.self) {
      _ = try await SkipLorvexHabitIntent(habit: blank).perform()
    }
    await #expect(throws: LorvexIntentFailure.self) {
      _ = try await UnskipLorvexHabitIntent(habit: blank).perform()
    }
  }
}
