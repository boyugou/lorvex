import LorvexCore
import Testing

@testable import LorvexMobile

/// The mobile store threads the optional milestone goal through create, edit, and
/// clear — a positive field sets it, editing seeds and raises it, and blanking it
/// clears the goal (a `.clear` patch, not a silent leave-as-is).
@MainActor
@Test
func mobileStoreThreadsMilestoneGoalThroughCreateEditAndClear() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // Create carries the optional milestone goal to the core.
  store.habitDraft.name = "Meditate"
  store.habitDraft.milestoneTargetText = "30"
  #expect(await store.createDraftHabit())
  let created = try #require(store.habits?.habits.first { $0.name == "Meditate" })
  #expect(created.milestoneTarget == 30)
  // The draft is reset after a create, like the other draft fields.
  #expect(store.habitDraft.milestoneTargetText == "")

  // Editing seeds the field from the stored goal, then raises it.
  store.prepareHabitDraft(for: created)
  #expect(store.habitDraft.milestoneTargetText == "30")
  store.habitDraft.milestoneTargetText = "66"
  #expect(await store.updateHabit(created))
  let raised = try #require(store.habits?.habits.first { $0.id == created.id })
  #expect(raised.milestoneTarget == 66)

  // Clearing the field clears the goal (Patch.clear), not leaves it unchanged.
  store.prepareHabitDraft(for: raised)
  store.habitDraft.milestoneTargetText = ""
  #expect(await store.updateHabit(raised))
  let cleared = try #require(store.habits?.habits.first { $0.id == created.id })
  #expect(cleared.milestoneTarget == nil)
  #expect(store.errorMessage == nil)
}

/// Completing a habit that crosses a milestone stages the celebration; a
/// completion that crosses nothing stages none.
@MainActor
@Test
func mobileStoreStagesMilestoneCelebrationOnCrossing() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // A daily habit with a personal goal of 1: the first completion reaches it.
  store.habitDraft.name = "First step"
  store.habitDraft.milestoneTargetText = "1"
  #expect(await store.createDraftHabit())
  let habit = try #require(store.habits?.habits.first { $0.name == "First step" })
  #expect(store.milestoneCelebration == nil)

  #expect(await store.completeHabit(habit))
  let celebration = try #require(store.milestoneCelebration)
  #expect(celebration.milestone == 1)
  #expect(celebration.habitName == "First step")

  // A completion that crosses nothing leaves no new celebration staged.
  store.milestoneCelebration = nil
  let plain = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(await store.completeHabit(plain))
  #expect(store.milestoneCelebration == nil)
  #expect(store.errorMessage == nil)
}

/// Batch completion stages the celebration for a crossed milestone, matching the
/// single-complete paths — the batch path used to play only the plain completion
/// note and silently drop every milestone the batch crossed.
@MainActor
@Test
func mobileStoreStagesMilestoneCelebrationOnBatchCrossing() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // Two daily habits, each with a personal goal of 1: completing both in one
  // batch crosses both milestones at once.
  store.habitDraft.name = "Alpha"
  store.habitDraft.milestoneTargetText = "1"
  #expect(await store.createDraftHabit())
  let alpha = try #require(store.habits?.habits.first { $0.name == "Alpha" })

  store.habitDraft.name = "Beta"
  store.habitDraft.milestoneTargetText = "1"
  #expect(await store.createDraftHabit())
  let beta = try #require(store.habits?.habits.first { $0.name == "Beta" })

  #expect(store.milestoneCelebration == nil)
  #expect(await store.completeHabits([alpha.id, beta.id]))

  let celebration = try #require(store.milestoneCelebration)
  #expect(celebration.milestone == 1)
  #expect([alpha.name, beta.name].contains(celebration.habitName))
  #expect(store.errorMessage == nil)

  // A batch that crosses no milestone stages none.
  store.milestoneCelebration = nil
  let plain = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(await store.completeHabits([plain.id]))
  #expect(store.milestoneCelebration == nil)
}
