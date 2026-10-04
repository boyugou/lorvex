import Foundation
import Testing

@testable import LorvexCore

/// The day review's habit counts cover the habits that are on for the day, so
/// a day on which a habit rests does not read as that habit missed.
@Suite("Day review habit counts")
struct DayReviewHabitScopeTests {
  /// 2026-05-25 is a Monday.
  private static let monday = "2026-05-25"
  private static let tuesday = "2026-05-26"

  @Test("a weekday-pinned habit is counted on its days, and on a rest day only once checked in")
  func pinnedHabitIsCountedOnItsDaysOrWhenCheckedIn() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    _ = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily,
      milestoneTarget: nil)
    let gym = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2, 4]),
      milestoneTarget: nil)

    let monday = try await service.loadDaySummary(date: Self.monday)
    let tuesday = try await service.loadDaySummary(date: Self.tuesday)
    #expect(monday.habitsTotal == 2)
    #expect(tuesday.habitsTotal == 1, "Gym rests on Tuesdays")
    #expect(tuesday.habitsCompleted == 0)

    _ = try await service.completeHabit(id: gym.id, date: Self.tuesday)
    let checkedIn = try await service.loadDaySummary(date: Self.tuesday)
    #expect(checkedIn.habitsTotal == 2, "a check-in made on a rest day is counted")
    #expect(checkedIn.habitsCompleted == 1)
  }

  @Test("a day on which no habit is due names no habits in its sentence")
  func restDayWithNoHabitsDueSaysNothingAboutHabits() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    _ = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2, 4]),
      milestoneTarget: nil)

    let tuesday = try await service.loadDaySummary(date: Self.tuesday)

    #expect(tuesday.habitsTotal == 0)
    #expect(
      !LorvexReviewSentence.parts(tuesday).contains(.habitsNone),
      "the review must not say habits went unkept on a day none was due")
  }
}
