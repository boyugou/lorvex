import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// The Habits screen re-reads the archived habits when the set of active habits
// changes. A rename or a deletion of an archived habit leaves that set alone, so
// once the screen has loaded the archived habits the store's own reload paths
// keep them current.

@MainActor
@Test
func mobileStoreRefreshKeepsLoadedArchivedHabitsCurrent() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let first = try #require(store.habits?.habits.first)
  #expect(await store.setHabitArchived(first, archived: true))
  #expect(store.archivedHabits.map(\.id) == [first.id])

  _ = try await core.updateHabit(
    id: first.id, name: "Renamed elsewhere", cue: .unset, color: nil, icon: nil,
    targetCount: nil, archived: nil)
  await store.refresh()
  #expect(store.archivedHabits.map(\.name) == ["Renamed elsewhere"])

  let second = try #require(store.habits?.habits.first)
  _ = try await core.updateHabit(
    id: second.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
    archived: true)
  await store.refresh()
  #expect(Set(store.archivedHabits.map(\.id)) == [first.id, second.id])

  _ = try await core.deleteHabit(id: first.id)
  await store.refresh()
  #expect(store.archivedHabits.map(\.id) == [second.id])
}

@MainActor
@Test
func mobileStoreHabitsReloadFromAPeerKeepsLoadedArchivedHabitsCurrent() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let habit = try #require(store.habits?.habits.first)
  #expect(await store.setHabitArchived(habit, archived: true))

  _ = try await core.updateHabit(
    id: habit.id, name: "Renamed on a peer", cue: .unset, color: nil, icon: nil,
    targetCount: nil, archived: nil)
  await store.reloadInboundDomains([.habits])
  #expect(store.archivedHabits.map(\.name) == ["Renamed on a peer"])

  _ = try await core.deleteHabit(id: habit.id)
  await store.reloadInboundDomains([.habits])
  #expect(store.archivedHabits.isEmpty)
}

@MainActor
@Test
func mobileStoreLeavesArchivedHabitsUnreadUntilTheScreenLoadsThem() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let habit = try #require(store.habits?.habits.first)
  _ = try await core.updateHabit(
    id: habit.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
    archived: true)

  await store.refresh()
  #expect(store.archivedHabits.isEmpty)

  await store.loadArchivedHabits()
  #expect(store.archivedHabits.map(\.id) == [habit.id])
}
