import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

/// A day review lists the habits that were due on the reviewed day: a weekly
/// habit pinned to weekdays is absent on its rest days, a monthly habit on every
/// day but its own and a times-per-week habit on every day, unless it was
/// checked in that day.
@Suite("Day review habits")
@MainActor
struct ReviewDayHabitScopeTests {
  /// 2026-05-25 is a Monday; the pinned habit is on Mondays, Wednesdays and Fridays.
  private nonisolated static let monday = "2026-05-25"
  private nonisolated static let tuesday = "2026-05-26"

  private func coreWithAPinnedHabit() async throws -> (SwiftLorvexCoreService, LorvexHabit) {
    let core = try await makeSeededInMemoryCore()
    let gym = try await core.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2, 4]),
      milestoneTarget: nil)
    return (core, gym)
  }

  @Test("the phone's review leaves a habit out on its rest day")
  func phoneReviewListsOnlyTheHabitsThatAreOn() async throws {
    let (core, gym) = try await coreWithAPinnedHabit()
    let store = MobileStore(core: core, todayString: { Self.tuesday })

    let onMonday = try #require(await store.loadReviewHabits(date: Self.monday))
    let onTuesday = try #require(await store.loadReviewHabits(date: Self.tuesday))

    #expect(onMonday.contains { $0.id == gym.id })
    #expect(!onTuesday.contains { $0.id == gym.id })
    #expect(onTuesday.count == onMonday.count - 1, "the daily habits are on both days")
  }

  @Test("the Mac's review leaves a habit out on its rest day")
  func macReviewListsOnlyTheHabitsThatAreOn() async throws {
    let (core, gym) = try await coreWithAPinnedHabit()
    let store = AppStore(core: core)

    let onMonday = try #require(await store.loadReviewHabits(date: Self.monday))
    let onTuesday = try #require(await store.loadReviewHabits(date: Self.tuesday))

    #expect(onMonday.contains { $0.id == gym.id })
    #expect(!onTuesday.contains { $0.id == gym.id })
    #expect(onTuesday.count == onMonday.count - 1, "the daily habits are on both days")
  }

  @Test("a check-in made on a rest day keeps the habit on that day's review")
  func restDayCheckInStaysOnTheReview() async throws {
    let (core, gym) = try await coreWithAPinnedHabit()
    _ = try await core.completeHabit(id: gym.id, date: Self.tuesday)
    let phone = MobileStore(core: core, todayString: { Self.tuesday })
    let mac = AppStore(core: core)

    let onPhone = try #require(await phone.loadReviewHabits(date: Self.tuesday))
    let onMac = try #require(await mac.loadReviewHabits(date: Self.tuesday))

    #expect(onPhone.contains { $0.id == gym.id })
    #expect(onMac.contains { $0.id == gym.id })
  }

  @Test("a review lists a monthly habit on its day and a times-per-week habit when checked in")
  func periodHabitsAppearOnTheReviewOnlyWhenDueOrCheckedIn() async throws {
    let core = try await makeSeededInMemoryCore()
    let rent = try await core.createHabit(
      name: "Rent", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "monthly", dayOfMonth: 26),
      milestoneTarget: nil)
    let run = try await core.createHabit(
      name: "Run", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3),
      milestoneTarget: nil)
    let phone = MobileStore(core: core, todayString: { Self.tuesday })
    let mac = AppStore(core: core)

    let dayBefore = try #require(await phone.loadReviewHabits(date: Self.monday))
    let onItsDay = try #require(await phone.loadReviewHabits(date: Self.tuesday))
    let macOnItsDay = try #require(await mac.loadReviewHabits(date: Self.tuesday))

    #expect(!dayBefore.contains { $0.id == rent.id || $0.id == run.id })
    #expect(onItsDay.contains { $0.id == rent.id })
    #expect(macOnItsDay.contains { $0.id == rent.id })
    #expect(!onItsDay.contains { $0.id == run.id })
    #expect(!macOnItsDay.contains { $0.id == run.id })

    _ = try await core.completeHabit(id: run.id, date: Self.monday)
    let checkedInPhone = try #require(await phone.loadReviewHabits(date: Self.monday))
    let checkedInMac = try #require(await mac.loadReviewHabits(date: Self.monday))

    #expect(checkedInPhone.contains { $0.id == run.id })
    #expect(checkedInMac.contains { $0.id == run.id })
  }
}
