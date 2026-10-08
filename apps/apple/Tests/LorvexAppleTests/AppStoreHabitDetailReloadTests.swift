import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// The habit inspector shows the habit's cached detail (history, stats, reminder
// policies), loaded when the habit is selected. A change made outside the app's
// own habit actions (the assistant, another device) must reach that cached
// detail, or the inspector keeps showing the old history beside a ring that
// already shows the new check-in.

@MainActor
private func openHabitDetail(
  core: SwiftLorvexCoreService
) async throws -> (store: AppStore, habit: LorvexHabit) {
  let habit = try await core.createHabit(
    name: "Stretch", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily,
    milestoneTarget: nil)
  let store = AppStore(core: core)
  await store.refresh()
  store.selection = .habits
  store.selectedHabitID = habit.id
  await store.loadHabitDetail(id: habit.id)
  #expect(store.habitDetail(for: habit.id)?.stats.totalCompletions == 0)
  return (store, habit)
}

@MainActor
@Test
func appStoreRefreshKeepsTheOpenHabitDetailCurrent() async throws {
  let core = try await makeSeededInMemoryCore()
  let (store, habit) = try await openHabitDetail(core: core)

  _ = try await core.completeHabit(id: habit.id, date: store.logicalTodayDateString)
  await store.refresh()

  let shown = try #require(store.habitDetail(for: habit.id))
  #expect(shown.stats == (try await core.getHabitStats(id: habit.id)))
  #expect(shown.stats.totalCompletions == 1)
  #expect(shown.completions.completions.count == 1)
}

@MainActor
@Test
func appStoreHabitsReloadFromAPeerKeepsTheOpenHabitDetailCurrent() async throws {
  let core = try await makeSeededInMemoryCore()
  let (store, habit) = try await openHabitDetail(core: core)

  _ = try await core.completeHabit(id: habit.id, date: store.logicalTodayDateString)
  _ = try await core.upsertHabitReminderPolicy(
    id: habit.id,
    policy: HabitReminderPolicy(
      id: "", habitID: habit.id, habitName: "", reminderTime: "08:15", enabled: true,
      createdAt: "", updatedAt: ""))
  await store.performSelectiveInboundReload([.habits])

  let shown = try #require(store.habitDetail(for: habit.id))
  #expect(shown.stats.totalCompletions == 1)
  #expect(shown.reminderPolicies.map(\.reminderTime) == ["08:15"])
}

@MainActor
@Test
func appStoreRefreshRaisesNoErrorWhenTheOpenHabitWasDeletedElsewhere() async throws {
  let core = try await makeSeededInMemoryCore()
  let (store, habit) = try await openHabitDetail(core: core)

  _ = try await core.deleteHabit(id: habit.id)
  await store.refresh()

  #expect(store.errorMessage == nil)
  #expect(store.habits?.habits.contains { $0.id == habit.id } == false)
  #expect(store.selectedHabitID == nil)
}

@MainActor
@Test
func appStoreHabitsReloadFromAPeerClosesTheInspectorOfAnArchivedHabit() async throws {
  let core = try await makeSeededInMemoryCore()
  let (store, habit) = try await openHabitDetail(core: core)

  _ = try await core.updateHabit(
    id: habit.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil, archived: true)
  await store.performSelectiveInboundReload([.habits])

  #expect(store.selectedHabitID == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreHabitsReloadFromAPeerClosesTheInspectorOfADeletedHabit() async throws {
  let core = try await makeSeededInMemoryCore()
  let (store, habit) = try await openHabitDetail(core: core)

  _ = try await core.deleteHabit(id: habit.id)
  await store.performSelectiveInboundReload([.habits])

  #expect(store.selectedHabitID == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreHabitsReloadFromAPeerKeepsTheInspectorOnAHabitThatRemains() async throws {
  let core = try await makeSeededInMemoryCore()
  let (store, habit) = try await openHabitDetail(core: core)
  let other = try await core.createHabit(
    name: "Read", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily,
    milestoneTarget: nil)

  _ = try await core.deleteHabit(id: other.id)
  await store.performSelectiveInboundReload([.habits])

  #expect(store.selectedHabitID == habit.id)
}
