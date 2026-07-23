import Foundation
import LorvexCore
import LorvexMobile
import Testing

@MainActor
private final class MobileHabitRecordingFeedbackProvider: LorvexFeedbackProviding {
  private(set) var recorded: [LorvexFeedbackKind] = []

  func playFeedback(_ kind: LorvexFeedbackKind) {
    recorded.append(kind)
  }
}

@MainActor
@Test
func mobileStoreCompletesAndResetsHabitThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let feedback = MobileHabitRecordingFeedbackProvider()
  let store = MobileStore(core: core, feedbackProvider: feedback, todayString: { "2026-05-23" })

  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(habit.completionsToday == 0)

  let completed = await store.completeHabit(habit)
  let completedHabit = try #require(store.habits?.habits.first { $0.id == habit.id })

  #expect(completed)
  #expect(completedHabit.completionsToday == 1)
  #expect(feedback.recorded.contains(.habitCompleted))
  #expect(store.errorMessage == nil)
  #expect(store.isMutatingHabit == false)

  let reset = await store.uncompleteHabit(completedHabit)
  let resetHabit = try #require(store.habits?.habits.first { $0.id == habit.id })

  #expect(reset)
  #expect(resetHabit.completionsToday == 0)
  #expect(feedback.recorded.contains(.habitReset))
  #expect(store.errorMessage == nil)
  #expect(store.isMutatingHabit == false)
}

@MainActor
@Test
func mobileStoreBatchCompletesHabitsThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let feedback = MobileHabitRecordingFeedbackProvider()
  let store = MobileStore(core: core, feedbackProvider: feedback, todayString: { "2026-05-23" })

  await store.refresh()
  let first = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  let second = try #require(store.habits?.habits.first { $0.id != first.id && !$0.archived })

  let completed = await store.completeHabits([first.id, second.id, first.id])

  #expect(completed)
  #expect(store.habits?.habits.first { $0.id == first.id }?.completionsToday == 1)
  #expect(store.habits?.habits.first { $0.id == second.id }?.completionsToday == 1)
  #expect(feedback.recorded.contains(.habitCompleted))
  #expect(store.errorMessage == nil)
  #expect(store.isMutatingHabit == false)
}

@MainActor
@Test
func mobileStoreBatchResetsHabitsThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let feedback = MobileHabitRecordingFeedbackProvider()
  let store = MobileStore(core: core, feedbackProvider: feedback, todayString: { "2026-05-23" })

  await store.refresh()
  let first = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  let second = try #require(store.habits?.habits.first { $0.id != first.id && !$0.archived })
  #expect(await store.completeHabits([first.id, second.id]))

  let reset = await store.uncompleteHabits([first.id, second.id, first.id])

  #expect(reset)
  #expect(store.habits?.habits.first { $0.id == first.id }?.completionsToday == 0)
  #expect(store.habits?.habits.first { $0.id == second.id }?.completionsToday == 0)
  #expect(feedback.recorded.contains(.habitReset))
  #expect(store.errorMessage == nil)
  #expect(store.isMutatingHabit == false)
}

@MainActor
@Test
func mobileStoreLoadsHabitDetailStatsCompletionsAndReminders() async throws {
  let core = try await makeSeededInMemoryCore()
  let habit = try await core.createHabit(name: "Hydrate", cue: nil, targetCount: 1)
  _ = try await core.completeHabit(id: habit.id, date: "2026-05-22")
  _ = try await core.upsertHabitReminderPolicy(
    id: habit.id,
    policy: HabitReminderPolicy(
      id: "",
      habitID: habit.id,
      habitName: habit.name,
      reminderTime: "08:00",
      enabled: true,
      createdAt: "",
      updatedAt: ""
    )
  )
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let loaded = await store.loadHabitDetail(id: habit.id)
  let detail = try #require(store.habitDetail(for: habit.id))

  #expect(loaded)
  #expect(detail.completions.habitID == habit.id)
  #expect(detail.completions.completions.contains { $0.completedDate == "2026-05-22" })
  #expect(detail.stats.habitID == habit.id)
  #expect(detail.stats.totalCompletions >= 1)
  #expect(detail.reminderPolicies.contains { $0.reminderTime == "08:00" })
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreLoadsHabitDetailForDisplayedHeatmapWindow() async throws {
  let core = try await makeSeededInMemoryCore()
  let habit = try await core.createHabit(name: "Hydrate", cue: nil, targetCount: 1)
  _ = try await core.completeHabit(id: habit.id, date: "2026-01-30")
  _ = try await core.completeHabit(id: habit.id, date: "2026-05-22")
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  #expect(await store.loadHabitDetail(id: habit.id))
  let detail = try #require(store.habitDetail(for: habit.id))

  #expect(detail.completions.completions.contains { $0.completedDate == "2026-05-22" })
  #expect(!detail.completions.completions.contains { $0.completedDate == "2026-01-30" })
}

@MainActor
@Test
func mobileStoreRefreshesLoadedHabitDetailAfterCompletion() async throws {
  let core = try await makeSeededInMemoryCore()
  let habit = try await core.createHabit(name: "Plan", cue: nil, targetCount: 1)
  // The habit-stats "today" is the store's real clock day, so the store must
  // write the completion on the same day the stats read uses.
  let todayYMD = LorvexDateFormatters.ymd.string(from: Date())
  let store = MobileStore(core: core, todayString: { todayYMD })

  await store.refresh()
  #expect(await store.loadHabitDetail(id: habit.id))
  let loadedHabit = try #require(store.habits?.habits.first { $0.id == habit.id })

  #expect(await store.completeHabit(loadedHabit))
  let detail = try #require(store.habitDetail(for: habit.id))

  #expect(detail.stats.completionsToday == 1)
  #expect(detail.completions.completions.contains { $0.completedDate == todayYMD })
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreCreatesHabitThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  store.habitDraft = MobileHabitDraft(
    name: "  Morning Review  ",
    cue: "  After coffee  ",
    targetCountText: "2"
  )

  let created = await store.createDraftHabit()
  let habit = try #require(store.habits?.habits.first { $0.name == "Morning Review" })

  #expect(created)
  #expect(habit.cue == "After coffee")
  #expect(habit.targetCount == 2)
  #expect(habit.completionsToday == 0)
  #expect(store.habitDraft == MobileHabitDraft())
  #expect(store.errorMessage == nil)
  #expect(store.isCreatingHabit == false)
}

@MainActor
@Test
func mobileStoreUpdatesHabitThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  store.prepareHabitDraft(for: habit)
  store.habitDraft.name = "  Planning Review  "
  store.habitDraft.cue = "  After standup  "
  store.habitDraft.targetCountText = "3"

  let updated = await store.updateHabit(habit)
  let updatedHabit = try #require(store.habits?.habits.first { $0.id == habit.id })

  #expect(updated)
  #expect(updatedHabit.name == "Planning Review")
  #expect(updatedHabit.cue == "After standup")
  #expect(updatedHabit.targetCount == 3)
  #expect(store.habitDraft == MobileHabitDraft())
  #expect(store.errorMessage == nil)
  #expect(store.isUpdatingHabit == false)
}

@MainActor
@Test
func mobileStoreDeletesHabitThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  let deleted = await store.deleteHabit(habit)

  #expect(deleted)
  #expect(store.habits?.habits.contains { $0.id == habit.id } == false)
  #expect(store.errorMessage == nil)
  #expect(store.isDeletingHabit == false)
}

@MainActor
@Test
func mobileStoreBatchDeletesHabitsThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let first = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  let second = try #require(store.habits?.habits.first { $0.id != first.id && !$0.archived })
  store.selectHabit(first.id)

  let deleted = await store.deleteHabits([first.id, second.id, first.id])

  #expect(deleted)
  #expect(store.habits?.habits.contains { $0.id == first.id || $0.id == second.id } == false)
  #expect(store.selectedHabitID == nil)
  #expect(store.errorMessage == nil)
  #expect(store.isDeletingHabit == false)
}
