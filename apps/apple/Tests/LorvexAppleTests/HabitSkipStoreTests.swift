import Foundation
import LorvexCore
import LorvexMobile
import Testing

@testable import LorvexApple

@MainActor
private final class SkipRecordingFeedbackProvider: LorvexFeedbackProviding {
  private(set) var recorded: [LorvexFeedbackKind] = []

  func playFeedback(_ kind: LorvexFeedbackKind) {
    recorded.append(kind)
  }
}

// MARK: - iPhone store

@MainActor
@Test
func mobileStoreSkipsAndUnskipsHabitThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let feedback = SkipRecordingFeedbackProvider()
  let store = MobileStore(core: core, feedbackProvider: feedback, todayString: { "2026-05-23" })

  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(!habit.isSkipped)

  #expect(await store.skipHabit(habit))
  let skipped = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(skipped.isSkipped)
  #expect(skipped.completionsToday == 0)
  #expect(feedback.recorded.contains(.habitSkipped))
  #expect(store.errorMessage == nil)
  #expect(store.isMutatingHabit == false)

  #expect(await store.unskipHabit(skipped))
  let reopened = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(!reopened.isSkipped)
  #expect(feedback.recorded.last == .habitReset)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreToggleHabitSkipFollowsTheDaysState() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  #expect(await store.toggleHabitSkip(habit))
  let skipped = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(skipped.isSkipped)

  #expect(await store.toggleHabitSkip(skipped))
  let open = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(!open.isSkipped)

  // A day that holds a check-in offers no skip: nothing is written and no
  // error is shown.
  #expect(await store.completeHabit(open))
  let done = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(LorvexHabitSkip.action(for: done) == nil)
  #expect(await store.toggleHabitSkip(done) == false)
  let unchanged = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(unchanged.completionsToday == 1)
  #expect(!unchanged.isSkipped)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreCheckingInOnASkippedDayLiftsTheSkip() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(await store.skipHabit(habit))
  let skipped = try #require(store.habits?.habits.first { $0.id == habit.id })

  #expect(await store.completeHabit(skipped))
  let done = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(done.completionsToday == 1)
  #expect(!done.isSkipped)
}

@MainActor
@Test
func mobileStoreRefreshesLoadedHabitDetailAfterSkip() async throws {
  let core = try await makeSeededInMemoryCore()
  let habit = try await core.createHabit(name: "Plan", cue: nil, targetCount: 1)
  // The habit-stats "today" is the store's real clock day, so the store must
  // write the skip on the same day the stats read uses.
  let todayYMD = LorvexDateFormatters.ymd.string(from: Date())
  let store = MobileStore(core: core, todayString: { todayYMD })

  await store.refresh()
  #expect(await store.loadHabitDetail(id: habit.id))
  let loaded = try #require(store.habits?.habits.first { $0.id == habit.id })

  #expect(await store.skipHabit(loaded))
  #expect(try #require(store.habitDetail(for: habit.id)).stats.recentSkips.contains(todayYMD))

  let skipped = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(await store.unskipHabit(skipped))
  #expect(try #require(store.habitDetail(for: habit.id)).stats.recentSkips.isEmpty)
}

// MARK: - Mac store

@MainActor
@Test
func appStoreSkipsAndUnskipsAHabitForToday() async throws {
  let feedback = SkipRecordingFeedbackProvider()
  let store = AppStore(core: try await makeSeededInMemoryCore(), feedbackProvider: feedback)

  await store.refresh()
  let habit = try #require(store.orderedHabits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(!habit.isSkipped)

  await store.skipHabit(habit)
  let skipped = try #require(store.orderedHabits.first { $0.id == habit.id })
  #expect(skipped.isSkipped)
  #expect(feedback.recorded.contains(.habitSkipped))
  #expect(store.errorMessage == nil)

  await store.unskipHabit(skipped)
  let reopened = try #require(store.orderedHabits.first { $0.id == habit.id })
  #expect(!reopened.isSkipped)
  #expect(feedback.recorded.last == .habitReset)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreToggleHabitSkipFollowsTheDaysState() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let habit = try #require(store.orderedHabits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  await store.toggleHabitSkip(habit)
  let skipped = try #require(store.orderedHabits.first { $0.id == habit.id })
  #expect(skipped.isSkipped)

  // Checking in on a skipped day lifts the skip.
  await store.completeHabit(skipped)
  let done = try #require(store.orderedHabits.first { $0.id == habit.id })
  #expect(done.completionsToday == 1)
  #expect(!done.isSkipped)

  // A day that holds a check-in offers no skip: nothing is written.
  await store.toggleHabitSkip(done)
  let unchanged = try #require(store.orderedHabits.first { $0.id == habit.id })
  #expect(unchanged.completionsToday == 1)
  #expect(!unchanged.isSkipped)
  #expect(store.errorMessage == nil)
}
